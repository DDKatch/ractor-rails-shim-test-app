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

puts "assets shareable? #{Ractor.shareable?(Rails.application.assets)}"
begin
  a = Rails.application.assets
  puts "assets class: #{a.class}"
  puts "load_path shareable? #{Ractor.shareable?(a.load_path)}"
  paths = a.load_path.asset_paths_by_glob("#{Rails.root.join("app/assets")}/**/*.css") rescue nil
  puts "glob paths: #{paths.inspect[0,200]}"
rescue => e
  puts "ERR main: #{e.class}: #{e.message[0,200]}"
end
