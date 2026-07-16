#!/usr/bin/env ruby
# frozen_string_literal: true
# Boot config_ractor.ru and run ONE request to PATH inside a worker Ractor,
# printing any raised exception with its backtrace. Usage: ruby bench/debug_request.rb /posts/1

require "rack"

ENV["RAILS_ENV"]       = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
ENV["DATABASE_URL"]    = "postgresql://dev@127.0.0.1:5432/ractor_rails_shim_test_app_test"
ENV["KINO_MODE"]       = "ractor"

path = ARGV[0] || "/posts/1"
ru   = File.expand_path("../config_ractor.ru", __dir__)
app  = Rack::Builder.parse_file(ru)
app  = app.is_a?(Array) ? app.first : app

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

env = Rack::MockRequest.env_for(path)
env["rack.input"]  = ShareableInput.new
env["rack.errors"] = ShareableInput.new

begin
  result = Ractor.new(app, env) { |a, e| [a.call(e.dup), :done] }.value
  resp, _ = result
  puts "OK  HTTP #{resp[0]}  body=#{resp[2].map(&:bytesize).sum} bytes"
  puts resp[2].first(300) if resp[0] >= 400
rescue => e
  puts "RAISED #{e.class}: #{e.message}"
  puts e.backtrace.first(40).join("\n")
end
