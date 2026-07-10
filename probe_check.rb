# frozen_string_literal: true
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
m = ActionDispatch::Routing::RouteSet::NamedRouteCollection::UrlHelper::OptimizedUrlHelper.instance_method(:call)
puts "OptimizedUrlHelper#call source: #{m.source_location.inspect}"
rs = ActionDispatch::Routing::RouteSet.instance_method(:url_for)
puts "RouteSet#url_for source: #{rs.source_location.inspect}"
puts "AVPathStrategy defined? #{RactorRailsShim.const_defined?(:AVPathStrategy)}"
puts "AVPathStrategy shareable? #{Ractor.shareable?(RactorRailsShim::AVPathStrategy)}"
