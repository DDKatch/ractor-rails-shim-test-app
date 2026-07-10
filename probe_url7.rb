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

puts "SHAREABLE_ROUTES defined? #{RactorRailsShim.const_defined?(:SHAREABLE_ROUTES)}"
if RactorRailsShim.const_defined?(:SHAREABLE_ROUTES)
  sr = RactorRailsShim.const_get(:SHAREABLE_ROUTES)
  puts "SHAREABLE_ROUTES value shareable? #{Ractor.shareable?(sr)} (#{sr.class})"
end
puts "URL_HELPERS: #{RactorRailsShim.const_get(:URL_HELPERS).keys.inspect}" rescue puts "no URL_HELPERS"
puts "URL_OPTIONS_DEFAULTS: #{RactorRailsShim.const_get(:URL_OPTIONS_DEFAULTS).inspect rescue 'n/a'}"

result = Ractor.new(app) do |a|
  RactorRailsShim.init_worker_ar_connections!
  ctx = ActionView::Base.with_empty_template_cache; 
  vc = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
  begin
    h = vc.respond_to?(:post_path) ? "has post_path" : "no post_path"
    out = vc.post_path(Post.first)
    "OK: #{out}"
  rescue => e
    root = e; root = root.cause while root.respond_to?(:cause) && root.cause
    "ERR #{e.class}: #{e.message[0,400]}\nROOT: #{root.class}: #{root.message[0,400]}\n#{(root.backtrace || []).first(30).join("\n")}"
  end
end.value

puts result
