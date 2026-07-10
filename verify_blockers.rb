# frozen_string_literal: true
require "stringio"
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)
puts "app shareable? #{Ractor.shareable?(app)}"

dispatch = lambda do |path|
  env = {
    "REQUEST_METHOD" => "GET", "PATH_INFO" => path, "SCRIPT_NAME" => "",
    "QUERY_STRING" => "", "SERVER_NAME" => "localhost", "SERVER_PORT" => "9293",
    "rack.url_scheme" => "http", "HTTP_HOST" => "localhost",
    "HTTP_ACCEPT" => "text/html", "rack.input" => StringIO.new(""),
    "rack.errors" => StringIO.new(""), "rack.version" => [3, 0],
  }
  r = Ractor.new(app, env) do |a, e|
    begin
      RactorRailsShim.init_worker_ar_connections!
      s, h, b = a.call(e)
      body = +""; b.each { |c| body << c.to_s } rescue nil
      [s, h["content-type"], body[0, 200]]
    rescue => ex
      root = ex; root = root.cause while root.respond_to?(:cause) && root.cause
      [:err, ex.class.name, ex.message[0, 400],
       "ROOT: #{root.class}: #{root.message[0, 400]}",
       (root.backtrace || []).first(12)]
    end
  end
  r.value
end

data = Ractor.new(app) do |a|
  RactorRailsShim.init_worker_ar_connections!
  out = {}
  out[:post_count] = (Post.count rescue "ERR #{$!.class}: #{$!.message[0,120]}")
  out[:kaminari_config] = (Kaminari.config.class.to_s rescue "ERR #{$!.class}: #{$!.message[0,120]}")
  out[:kaminari_page] = (Post.page(1).per(10).to_a.size rescue "ERR #{$!.class}: #{$!.message[0,200]}")
  out
end.value

puts "=== DATA-LAYER (worker Ractor) ==="
data.each { |k, v| puts "  #{k}: #{v.inspect[0, 240]}" }
puts "=== HTTP DISPATCH (worker Ractor) ==="
["/up", "/users/sign_in", "/posts"].each do |path|
  puts "#{path} => #{dispatch.call(path).inspect[0, 400]}"
end
