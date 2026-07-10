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
  orig = ::Proc.instance_method(:call)
  ::Proc.define_method(:call) do |*args, &blk|
    begin
      orig.bind(self).call(*args, &blk)
    rescue RuntimeError => ex
      if ex.message.include?("un-shareable")
        $stderr.puts "PROC DEFINED AT: #{self.source_location.inspect}"
      end
      raise
    end
  end
  begin
    RactorRailsShim.init_worker_ar_connections!
    a.call(e)
    [200]
  rescue => ex
    ["ERR", ex.class.name, ex.message[0, 120]]
  end
end.value
require "pp"
pp result
