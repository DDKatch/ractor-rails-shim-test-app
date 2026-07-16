#!/usr/bin/env ruby
# frozen_string_literal: true
# Count Random.urandom (SecureRandom.random_bytes) calls per GET /posts and
# capture the app-side caller. Boot is in main Ractor; the TracePoint + request
# run inside a single worker Ractor.

require "rack"

ENV["RAILS_ENV"]       = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
ENV["DATABASE_URL"]    = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
ENV["KINO_MODE"]       = "ractor"

ru  = File.expand_path("../config_ractor.ru", __dir__)
app = Rack::Builder.parse_file(ru)
app = app.first if app.is_a?(Array)

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

def build_env(method, path)
  {
    "REQUEST_METHOD"    => method, "PATH_INFO" => path, "QUERY_STRING" => "",
    "SERVER_NAME" => "127.0.0.1", "SERVER_PORT" => "80", "rack.version" => [1, 2],
    "rack.url_scheme" => "http", "rack.input" => ShareableInput.new,
    "rack.errors" => ShareableInput.new, "rack.multithread" => false,
    "rack.multiprocess" => false, "rack.run_once" => false,
    "HTTP_HOST" => "127.0.0.1", "SCRIPT_NAME" => "", "REQUEST_URI" => path,
  }
end

path = ARGV[0] || "/posts"

result = Ractor.new(app, path) do |a, p|
  counts = Hash.new(0)
  callers = []
  tp = TracePoint.new(:c_call) do |t|
    if (t.method_id == :urandom || t.method_id == :random_bytes) &&
       (t.defined_class == Random || t.defined_class == SecureRandom)
      counts[t.method_id] += 1
      loc = caller_locations(1, 10).find { |l| l.path.to_s.include?("/ractor-rails-shim-test-app/") || l.label =~ /authenticity|csrf|token|mask/i }
      callers << "#{t.defined_class}##{t.method_id} @ #{loc ? loc.path + ':' + loc.lineno.to_s + ' ' + loc.label : 'n/a'}" if counts[t.method_id] <= 4
    end
  end
  env = build_env("GET", p)
  tp.enable { a.call(env) }
  [counts, callers.uniq]
end.value

puts "path=#{path}"
puts "SecureRandom.random_bytes calls: #{result[0][:random_bytes]}"
puts "callers (app-side):"
result[1].each { |c| puts "  #{c}" }
