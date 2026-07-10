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

# Inspect the devise route constraint objects
rset = RactorRailsShim::SHAREABLE_ROUTES
rset.set.routes.each do |route|
  next unless route.app.is_a?(::ActionDispatch::Routing::Mapper::Constraints) rescue next
  cons = route.app.instance_variable_get(:@constraints) rescue nil
  if cons
    cons.each do |c|
      puts "CONSTRAINT class=#{c.class} inspect=#{c.inspect[0,120]}"
    end
  end
end
