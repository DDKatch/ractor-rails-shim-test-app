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
helpers = Rails.application.routes.url_helpers
puts "MAIN post_path(1): #{helpers.post_path(1).inspect}"
puts "MAIN post_path(Post.first): #{helpers.post_path(Post.first).inspect rescue $!.message[0,80]}"
puts "owner: #{helpers.method(:post_path).owner.class}"
puts "_routes class: #{helpers._routes.class}"
