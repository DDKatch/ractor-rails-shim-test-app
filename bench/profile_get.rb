#!/usr/bin/env ruby
# frozen_string_literal: true

# Profile a realistic GET (/posts: DB query + Kaminari + view render) to find
# where time is spent, and to isolate the ractor-mode per-request overhead.
#
#   ruby bench/profile_get.rb [baseline|ractor] [iterations]
#
# Boots the REAL app via config_ractor.ru (Rack::Builder) so the boot path is
# byte-identical to the live kino server (which already serves /posts at 200).
#   baseline: KINO_MODE=threaded  -> plain Rails, no Ractor freeze/wrap.
#   ractor:   KINO_MODE=ractor    -> shim shareable graph + WorkerApp wrap.
# The delta between them is (roughly) the ractor per-request tax.
#
# Emits a StackProf CPU dump + allocation dump to bench/results/ and prints the
# top methods by total samples.

require "stackprof"
require "rack"
require "fileutils"

# Shareable stand-in for rack.input / rack.errors: only holds a frozen string,
# so instances are Ractor-shareable (worker Ractors can't touch StringIO's
# unshareable internals). GET requests don't read the body.
class ShareableInput
  def initialize(s = "")
    @s = s.freeze
  end

  def gets; @s; end
  def read(*_); @s; end
  def each; yield @s; end
  def rewind; end
  def size; @s.bytesize; end
  def eof?; true; end
  def close; end
  def write(*_); 0; end
  def puts(*_); end
  def flush; end
end

def shareable_env(path = "/posts")
  e = Rack::MockRequest.env_for(path)
  e["rack.input"]  = ShareableInput.new
  e["rack.errors"] = ShareableInput.new
  e
end

MODE   = (ARGV[0] || "ractor").to_sym
ITERS  = (ARGV[1] || 1000).to_i
OUTDIR = File.expand_path("../results", __dir__)
FileUtils.mkdir_p(OUTDIR)

ENV["RAILS_ENV"]        = "production"
ENV["SECRET_KEY_BASE"]  = "dummy"
ENV["DATABASE_URL"]     = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
ENV["KINO_MODE"]        = (MODE == :ractor) ? "ractor" : "threaded"

puts "Booting #{MODE} app via config_ractor.ru ..."
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# Boot the real app. Rack::Builder.parse_file evaluates config_ractor.ru in a
# builder context; the final `run app` becomes the returned app.
ru = File.expand_path("../config_ractor.ru", __dir__)
built = Rack::Builder.parse_file(ru)
app   = built.is_a?(Array) ? built.first : built

boot = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
puts "  boot: #{(boot * 1000).round(1)} ms"

# The production request path only runs correctly INSIDE a worker Ractor
# (kino calls the frozen app from workers). To profile steady state we reuse a
# SINGLE worker Ractor across all iterations (kino keeps workers alive), so we
# don't pay per-Ractor setup_once! on every request. For :threaded (baseline)
# we just call the app directly. The shared env is copied inside the worker so
# the app can mutate it without touching the shared original.
def dispatch(app, mode, iters)
  if mode == :ractor
    env = shareable_env
    r = Ractor.new(app, env, iters) do |a, e, n|
      e = e.dup
      n.times { a.call(e.dup) }
      :done
    end
    r.value
  else
    env = Rack::MockRequest.env_for("/posts")
    iters.times { app.call(env.dup) }
  end
end

begin
  if MODE == :ractor
    env = shareable_env
    status = Ractor.new(app, env) { |a, e| a.call(e.dup); :done }.value
    puts "  first GET /posts -> ok (worker Ractor)"
  else
    first = app.call(Rack::MockRequest.env_for("/posts").dup)
    puts "  first GET /posts -> HTTP #{first[0]}"
  end
rescue => e
  puts "  FIRST CALL FAILED: #{e.class}: #{e.message}"
  puts "  #{e.backtrace.first(5).join("\n  ")}"
  raise
end
dispatch(app, MODE, 50) # warm up
puts "Warmed up. Profiling #{ITERS} GET /posts ..."

dump     = File.join(OUTDIR, "profile_posts_#{MODE}.stackprof")
dump_obj = File.join(OUTDIR, "profile_posts_#{MODE}_alloc.stackprof")

cpu_data = StackProf.run(mode: :cpu, raw: false, interval: 500) do
  dispatch(app, MODE, ITERS)
end
File.binwrite(dump, Marshal.dump(cpu_data))
puts "  cpu dump -> #{dump}"

obj_data = StackProf.run(mode: :object) do
  dispatch(app, MODE, ITERS)
end
File.binwrite(dump_obj, Marshal.dump(obj_data))
puts "  alloc dump -> #{dump_obj}"

# ---- report ----------------------------------------------------------
report = StackProf::Report.new(cpu_data)
frames = report.data[:frames].values
total  = report.overall_samples.to_i
gc     = frames.select { |m| m[:name].to_s =~ /\(sweeping|marking|garbage collection\)/ }.sum { |m| m[:samples].to_i }
puts "\n=== CPU TOP METHODS BY TOTAL (#{MODE}) ==="
puts "total samples: #{total}  (1 sample ~= 500us); GC-related ~= #{gc} (#{(gc*100.0/total).round(1)}%)"
rows = frames.sort_by { |m| -m[:samples].to_i }.first(30)
printf("%7s %7s %s\n", "self", "total", "method")
rows.each do |m|
  nm = "#{m[:file]}:#{m[:line]} #{m[:name]}"
  printf("%7d %7d %s\n", m[:self_samples].to_i, m[:samples].to_i, nm)
end
puts "\n=== CPU TOP METHODS BY SELF (exclusive) ==="
rows = frames.sort_by { |m| -m[:self_samples].to_i }.first(15)
printf("%7s %s\n", "self", "method")
rows.each do |m|
  nm = "#{m[:file]}:#{m[:line]} #{m[:name]}"
  printf("%7d %s\n", m[:self_samples].to_i, nm)
end
File.open(dump.sub(/\.stackprof$/, ".html"), "w") { |f| report.print_flamegraph(f) } rescue nil
puts "  flamegraph -> #{dump.sub(/\.stackprof$/, '.html')}"

report_obj = StackProf::Report.new(obj_data)
oframes = report_obj.data[:frames].values
oalloc  = oframes.sum { |m| m[:samples].to_i }
puts "\n=== ALLOCATION TOP METHODS (#{MODE}) ==="
puts "total allocations: #{oalloc}  (~#{(oalloc/ITERS.to_f).round(0)}/req)"
rows = oframes.sort_by { |m| -m[:samples].to_i }.first(15)
printf("%9s %s\n", "allocs", "method")
rows.each do |m|
  nm = "#{m[:file]}:#{m[:line]} #{m[:name]}"
  printf("%9d %s\n", m[:samples].to_i, nm)
end
# Per-gem allocation share (who is allocating?)
by_gem = Hash.new(0)
oframes.each do |m|
  f = m[:file].to_s
  gem = f[/gems\/([^\/]+)/, 1] || (f.include?("ractor-rails-shim") ? "ractor-rails-shim" : (f.include?("app/") ? "app" : "other"))
  by_gem[gem] += m[:samples].to_i
end
puts "\n=== ALLOCATION SHARE BY GEM ==="
by_gem.sort_by { |_, v| -v }.each do |g, v|
  printf("%9d  %5.1f%%  %s\n", v, v*100.0/oalloc, g)
end
