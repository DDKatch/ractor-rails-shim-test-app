#!/usr/bin/env ruby
# frozen_string_literal: true
# Where does GET /posts time actually go? Captures the real SQL via
# ActiveSupport::Notifications (inside a worker Ractor, since subscriptions are
# thread-local) and runs StackProf (cpu + object) from the MAIN Ractor.
# StackProf's sampling timer is process-wide, so it still captures the worker
# thread's CPU even though run() is called in main. Samples are then bucketed by
# category: GC / PG / ActiveRecord / ActiveSupport / ActionView / Rack / app.
#
#   ruby bench/profile_pg_gc.rb [iters]

require "stackprof"
require "rack"
require "fileutils"

class ShareableInput
  def initialize(s = ""); @s = s.freeze; end
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

ITERS  = (ARGV[0] || 1500).to_i
MODE   = (ENV["PROFILE_MODE"] || "threaded").to_sym   # threaded = accurate CPU (main thread); ractor = worker (CPU undersampled)
OUTDIR = File.expand_path("../results", __dir__)
FileUtils.mkdir_p(OUTDIR)

ENV["RAILS_ENV"]       = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
ENV["DATABASE_URL"]    = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
ENV["KINO_MODE"]       = (MODE == :ractor) ? "ractor" : "threaded"
# Force the shim into THREAD mode (minimal install, no ractor require_unload_lock!
# hook) so app.call runs in the MAIN thread and StackProf can sample it. The
# request path (AR query + view) is identical to ractor mode.
ENV["SERVER"]          = "thread" unless MODE == :ractor
ENV["BENCHMARK_STATS"] = "1" unless MODE == :ractor

ru    = File.expand_path("../config_ractor.ru", __dir__)
built = Rack::Builder.parse_file(ru)
app   = built.is_a?(Array) ? built.first : built

cpu_dump = File.join(OUTDIR, "profile_posts_#{MODE}_cpu.stackprof")
obj_dump = File.join(OUTDIR, "profile_posts_#{MODE}_alloc.stackprof")
sql_file = File.join(OUTDIR, "profile_posts_#{MODE}_sql.txt")

# --- SQL capture ---
if MODE == :ractor
  # subscriptions are thread-local -> must run inside the worker Ractor
  queries = Ractor.new(app, shareable_env) do |a, env|
    qs = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      ev = ActiveSupport::Notifications::Event.new(*args)
      qs << ev.payload[:sql]
    end
    a.call(env.dup)
    ActiveSupport::Notifications.unsubscribe(sub)
    qs
  end.value
else
  qs = []
  sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    ev = ActiveSupport::Notifications::Event.new(*args)
    qs << ev.payload[:sql]
  end
  app.call(shareable_env.dup)
  ActiveSupport::Notifications.unsubscribe(sub)
  queries = qs
end
File.write(sql_file, queries.join("\n"))
puts "=== SQL for ONE GET /posts (#{MODE}) ==="
puts "total queries: #{queries.size}, unique: #{queries.uniq.size}"
queries.uniq.each { |q| puts "  #{q[0, 200]}" }

# --- dispatch ---
def dispatch_ractor(app, env, n)
  e = env.dup
  Ractor.new(app, e, n) { |a, e2, k| k.times { a.call(e2.dup) }; :done }.value
end
def dispatch_main(app, env, n)
  e = env.dup
  n.times { app.call(e.dup) }
end

env = shareable_env
(MODE == :ractor ? dispatch_ractor(app, env, 30) : dispatch_main(app, env, 30)) # warm up
puts "\nWarmed up (#{MODE}). Profiling #{ITERS} GET /posts ..."

cpu_data = StackProf.run(mode: :cpu, raw: false, interval: 500) do
  MODE == :ractor ? dispatch_ractor(app, env, ITERS) : dispatch_main(app, env, ITERS)
end
File.binwrite(cpu_dump, Marshal.dump(cpu_data))
puts "  cpu dump -> #{cpu_dump}"

obj_data = StackProf.run(mode: :object) do
  MODE == :ractor ? dispatch_ractor(app, env, ITERS) : dispatch_main(app, env, ITERS)
end
File.binwrite(obj_dump, Marshal.dump(obj_data))
puts "  alloc dump -> #{obj_dump}"

# ---- analysis ---------------------------------------------------------
def categorize(file, name)
  f = file.to_s
  n = name.to_s
  return "GC" if n =~ /sweeping|marking|garbage collection|gc_|newobj|rb_gc|objspace|GC::/ || f =~ /gc\.c/
  gem = f[/gems\/([^\/]+)/, 1]
  map = {
    "activerecord"    => "ActiveRecord",
    "activesupport"   => "ActiveSupport",
    "actionview"      => "ActionView",
    "actionpack"      => "ActionPack",
    "actioncontroller" => "ActionController",
    "activemodel"     => "ActiveModel",
    "rack"            => "Rack",
    "pg"              => "PG",
  }
  return map[gem] if gem && map[gem]
  return "shim" if f.include?("ractor-rails-shim")
  return "app"  if f.include?("ractor-rails-shim-test-app") || f =~ %r{/app/}
  return "ruby/core" if f.empty? || f == "(unknown)" || f =~ /\.c$/
  gem || "other"
end

def bucket(report)
  frames = report.data[:frames].values
  total  = report.overall_samples.to_i
  by_cat = Hash.new { |h, k| h[k] = { self: 0, total: 0 } }
  frames.each do |m|
    cat = categorize(m[:file], m[:name])
    by_cat[cat][:self]  += m[:self_samples].to_i
    by_cat[cat][:total] += m[:samples].to_i
  end
  [total, by_cat]
end

puts "\n=== CPU SAMPLES BY CATEGORY (exclusive / inclusive) ==="
cpu = StackProf::Report.new(cpu_data)
total, by_cat = bucket(cpu)
printf("%-14s %10s %8s %10s %8s\n", "category", "self", "self%", "total", "total%")
by_cat.sort_by { |_, v| -v[:self] }.each do |cat, v|
  printf("%-14s %10d %7.1f%% %10d %7.1f%%\n", cat, v[:self], v[:self] * 100.0 / total,
         v[:total], v[:total] * 100.0 / total)
end
puts "total samples: #{total}  (interval 500us)"

puts "\n=== ALLOCATION SAMPLES BY CATEGORY ==="
obj = StackProf::Report.new(obj_data)
ototal, oby = bucket(obj)
printf("%-14s %12s %8s\n", "category", "allocs", "alloc%")
oby.sort_by { |_, v| -v[:total] }.each do |cat, v|
  printf("%-14s %12d %7.1f%%\n", cat, v[:total], v[:total] * 100.0 / ototal)
end
puts "total allocations: #{ototal}  (~#{(ototal / ITERS.to_f).round(0)}/req)"

puts "\n=== TOP CPU METHODS BY EXCLUSIVE (self) ==="
frames = cpu.data[:frames].values.sort_by { |m| -m[:self_samples].to_i }.first(20)
printf("%7s %s\n", "self", "method")
frames.each { |m| printf("%7d %s:%d %s\n", m[:self_samples].to_i, m[:file], m[:line].to_i, m[:name]) }
