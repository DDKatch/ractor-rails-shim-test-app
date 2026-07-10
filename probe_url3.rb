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
  "REQUEST_METHOD" => "GET", "PATH_INFO" => "/posts", "SCRIPT_NAME" => "",
  "QUERY_STRING" => "", "SERVER_NAME" => "localhost", "SERVER_PORT" => "9293",
  "rack.url_scheme" => "http", "HTTP_HOST" => "localhost",
  "HTTP_ACCEPT" => "text/html", "rack.input" => StringIO.new(""),
  "rack.errors" => StringIO.new(""), "rack.version" => [3, 0],
}
r = Ractor.new(app, env) do |a, e|
  RactorRailsShim.init_worker_ar_connections!
  begin
    a.call(e)
    [200]
  rescue => ex
    chain = []
    cur = ex
    while cur
      chain << [cur.class.to_s, cur.message[0, 200], (cur.backtrace || []).first(15)]
      cur = cur.respond_to?(:cause) ? cur.cause : nil
      break if chain.size > 4
    end
    chain
  end
end.value
puts r.inspect
