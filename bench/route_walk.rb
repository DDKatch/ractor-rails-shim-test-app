#!/usr/bin/env ruby
# frozen_string_literal: true
# Boot config_ractor.ru, then fire EVERY route (GET/POST) inside a single
# worker Ractor and report status codes. Usage:
#   ruby bench/route_walk.rb <valid_post_id>

require "rack"

ENV["RAILS_ENV"]       = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
ENV["DATABASE_URL"]    = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
ENV["KINO_MODE"]       = "ractor"

ru   = File.expand_path("../config_ractor.ru", __dir__)
app  = Rack::Builder.parse_file(ru)
app  = app.first if app.is_a?(Array)

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

pid   = (ARGV[0] || "2149286").to_s
paths = [
  ["GET",  "/"],
  ["GET",  "/up"],
  ["GET",  "/posts"],
  ["GET",  "/posts/new"],
  ["GET",  "/posts/#{pid}"],
  ["GET",  "/posts/#{pid}/edit"],
  ["GET",  "/stats"],
  ["POST", "/posts"], # no CSRF/session -> expect 422, not a crash
]

def build_env(method, path)
  {
    "REQUEST_METHOD"    => method,
    "PATH_INFO"         => path,
    "QUERY_STRING"      => "",
    "SERVER_NAME"       => "127.0.0.1",
    "SERVER_PORT"       => "80",
    "rack.version"      => [1, 2],
    "rack.url_scheme"   => "http",
    "rack.input"        => ShareableInput.new,
    "rack.errors"       => ShareableInput.new,
    "rack.multithread"  => false,
    "rack.multiprocess" => false,
    "rack.run_once"     => false,
    "HTTP_HOST"         => "127.0.0.1",
    "SCRIPT_NAME"       => "",
    "REQUEST_URI"       => path,
  }
end

results = Ractor.new(app, paths) do |a, ps|
  out = []
  ps.each do |method, p|
    env = build_env(method, p)
    begin
      resp = a.call(env)
      body = resp[2]
      sz = if body.is_a?(Array)
             body.map(&:bytesize).sum
           elsif body.respond_to?(:each)
             s = 0; body.each { |c| s += c.to_s.bytesize }; s
           else
             body.to_s.bytesize
           end
      out << [method, p, resp[0], sz]
    rescue => e
      out << [method, p, "RAISED #{e.class}: #{e.message[0, 120]}"]
    end
  end
  out
end.value

results.each { |r| puts r.inspect }
