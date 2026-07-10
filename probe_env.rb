require "stringio"
ENV["RAILS_ENV"] ||= "production"
ENV["SECRET_KEY_BASE"] ||= "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)
puts "app shareable? #{Ractor.shareable?(app)}"

dispatch = lambda do |env|
  r = Ractor.new(app, env) do |a, e|
    re = e.dup
    re["rack.input"] ||= StringIO.new("")
    re["rack.errors"] ||= StringIO.new("")
    re["rack.version"] ||= [3, 0]
    begin
      s, h, b = a.call(re)
      body = +""
      b.each { |c| body << c.to_s } rescue nil
      b.close if b.respond_to?(:close) rescue nil
      [s, h["content-type"], body[0, 200]]
    rescue => ex
      root = ex
      root = root.cause while root.respond_to?(:cause) && root.cause
      [:err, ex.class.name, ex.message[0, 300],
       "ROOT: #{root.class}: #{root.message[0, 300]}",
       (root.backtrace || []).first(8)]
    end
  end
  r.value
end

base = {
  "REQUEST_METHOD"  => "GET",
  "PATH_INFO"       => "/up",
  "SCRIPT_NAME"     => "",
  "QUERY_STRING"    => "",
  "SERVER_NAME"     => "localhost",
  "SERVER_PORT"     => "9293",
  "rack.url_scheme" => "http",
}

tests = [
  ["1. + HTTP_HOST + Accept",     base.merge("HTTP_HOST" => "localhost", "HTTP_ACCEPT" => "text/html")],
  ["2. + HTTP_HOST (no Accept)",  base.merge("HTTP_HOST" => "localhost")],
  ["3. + Accept (no HTTP_HOST)",  base.merge("HTTP_ACCEPT" => "text/html")],
  ["4. bare (no HTTP_*)",         base.dup],
  ["5. + empty HTTP_ACCEPT",      base.merge("HTTP_HOST" => "localhost", "HTTP_ACCEPT" => "")],
  ["6. + SERVER_PROTOCOL",        base.merge("HTTP_HOST" => "localhost", "SERVER_PROTOCOL" => "HTTP/1.1")],
  ["7. + HTTP_VERSION",           base.merge("HTTP_HOST" => "localhost", "HTTP_VERSION" => "HTTP/1.1")],
]

tests.each do |label, env|
  puts "#{label} => #{dispatch.call(Ractor.make_shareable(env)).inspect[0, 300]}"
end
