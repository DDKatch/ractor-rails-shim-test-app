# frozen_string_literal: true
require "stringio"
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.config.action_dispatch.show_exceptions = :none
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)

env = {
  "REQUEST_METHOD" => "GET", "PATH_INFO" => "/users/sign_in", "SCRIPT_NAME" => "",
  "QUERY_STRING" => "", "SERVER_NAME" => "localhost", "SERVER_PORT" => "9293",
  "rack.url_scheme" => "http", "HTTP_HOST" => "localhost",
  "HTTP_ACCEPT" => "text/html", "rack.input" => StringIO.new(""),
  "rack.errors" => StringIO.new(""), "rack.version" => [3, 0],
}

result = Ractor.new(app, env) do |a, e|
  begin
    RactorRailsShim.init_worker_ar_connections!
    s, h, b = a.call(e)
    body = +""; b.each { |c| body << c.to_s } rescue nil
    [s, body[0, 500]]
  rescue => ex
    out = []
    cur = ex
    while cur
      out << "#{cur.class}: #{cur.message[0, 300]}"
      out << (cur.backtrace || []).first(30).join("\n")
      out << "---CAUSE---"
      cur = cur.cause
    end
    out
  end
end.value

require "pp"
pp result
