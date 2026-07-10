# frozen_string_literal: true
require "stringio"
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.initialize!
Rails.application.config.action_dispatch.show_exceptions = :none
Rails.application.config.log_level = :fatal
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)

result = Ractor.new(app) do |a|
  RactorRailsShim.init_worker_ar_connections!
  env = {
    "REQUEST_METHOD" => "GET", "PATH_INFO" => "/posts", "SCRIPT_NAME" => "",
    "QUERY_STRING" => "", "SERVER_NAME" => "localhost", "SERVER_PORT" => "9293",
    "rack.url_scheme" => "http", "HTTP_HOST" => "localhost",
    "HTTP_ACCEPT" => "text/html", "rack.input" => StringIO.new(""),
    "rack.errors" => StringIO.new(""), "rack.version" => [3, 0],
  }
  begin
    s, h, b = a.call(env)
    body = +""; b.each { |c| body << c.to_s } rescue nil
    "STATUS: #{s} body: #{body[0, 500]}"
  rescue => e
    root = e; root = root.cause while root.respond_to?(:cause) && root.cause
    "ERR #{e.class}: #{e.message[0, 400]}\nROOT: #{root.class}: #{root.message[0, 400]}\n#{(root.backtrace || []).first(25).join("\n")}"
  end
end.value

puts result
