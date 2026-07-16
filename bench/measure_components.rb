#!/usr/bin/env ruby
# frozen_string_literal: true
# Authoritative ractor-mode component split for GET /posts. Measures the three
# cost sources directly (process_action timings are dropped by the shim's
# nil-safe callback wrapper in ractor mode):
#   - DB    : sql.active_record :db_runtime (summed over run / N)
#   - Views : render_template/render_collection :runtime (summed over run / N)
#   - GC    : GC::Profiler.total_time (summed over run / N)
#
#   ruby bench/measure_components.rb [n]

require "rack"

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

N = (ARGV[0] || 100).to_i
ENV["RAILS_ENV"]       = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
ENV["DATABASE_URL"]    = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
ENV["KINO_MODE"]       = "ractor"

ru  = File.expand_path("../config_ractor.ru", __dir__)
app = Rack::Builder.parse_file(ru)
app = app.first if app.is_a?(Array)

result = Ractor.new(app, shareable_env, N) do |a, env, n|
  db_total = 0.0
  view_total = 0.0
  GC::Profiler.enable
  subs = []
  subs << ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    db_total += ActiveSupport::Notifications::Event.new(*args).payload[:db_runtime].to_f
  end
  subs << ActiveSupport::Notifications.subscribe("render_template.action_view") do |*args|
    view_total += ActiveSupport::Notifications::Event.new(*args).payload[:runtime].to_f
  end
  subs << ActiveSupport::Notifications.subscribe("render_collection.action_view") do |*args|
    view_total += ActiveSupport::Notifications::Event.new(*args).payload[:runtime].to_f
  end
  n.times { a.call(env.dup) }
  subs.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
  gc_ms = GC::Profiler.total_time * 1000.0
  GC::Profiler.disable
  { db: db_total, view: view_total, gc: gc_ms }
end.value

db_avg   = (result[:db] / N)
view_avg = (result[:view] / N)
gc_avg   = (result[:gc] / N)
puts "STEADY STATE (ractor mode) GET /posts, N=#{N}:"
puts "  avg DB    : #{db_avg.round(2)} ms   (1 query, no N+1)"
puts "  avg Views : #{view_avg.round(2)} ms"
puts "  avg GC    : #{gc_avg.round(2)} ms"
puts "  (DB+Views+GC = #{(db_avg + view_avg + gc_avg).round(2)} ms of per-request work;"
puts "   remaining is controller/rack/serialization overhead + the fixed ractor wrapper)"
