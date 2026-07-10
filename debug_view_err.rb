# frozen_string_literal: true
require "stringio"
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
# Re-raise the real exception to the caller instead of rendering a 500 page.
Rails.application.config.action_dispatch.show_exceptions = :none
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)

paths = ["/posts", "/users/sign_in", "/posts/1"]
paths.each do |path|
  env = {
    "REQUEST_METHOD" => "GET", "PATH_INFO" => path, "SCRIPT_NAME" => "",
    "QUERY_STRING" => "", "SERVER_NAME" => "localhost", "SERVER_PORT" => "9293",
    "rack.url_scheme" => "http", "HTTP_HOST" => "localhost",
    "HTTP_ACCEPT" => "text/html", "rack.input" => StringIO.new(""),
    "rack.errors" => StringIO.new(""), "rack.version" => [3, 0],
  }
  result = Ractor.new(app, env) do |a, e|
    begin
      RactorRailsShim.init_worker_ar_connections!
      a.call(e)
      [200]
    rescue => ex
      root = ex
      root = root.cause while root.respond_to?(:cause) && root.cause
      [:err, ex.class.name, ex.message[0, 300],
       "ROOT: #{root.class}: #{root.message[0, 300]}",
       (root.backtrace || []).first(40)]
    end
  end.value
  puts "=== #{path} ==="
  p result
end
