# frozen_string_literal: true
ENV["RAILS_ENV"] = "production"
ENV["SECRET_KEY_BASE"] = "dummy"
require File.expand_path("config/boot")
require File.expand_path("config/application")
Bundler.require(*Rails.groups)
Rails.application.initialize!
RactorRailsShim.prepare_for_ractors!
app = RactorRailsShim.make_app_shareable!(Rails.application)
Ractor.new(app) do |a|
  out = {}
  out[:routes_defined] = RactorRailsShim.const_defined?(:SHAREABLE_ROUTES)
  out[:routes_shareable] = (RactorRailsShim::SHAREABLE_ROUTES ? Ractor.shareable?(RactorRailsShim::SHAREABLE_ROUTES) : "nil")
  begin
    path_lambda = ActionDispatch::Routing::RouteSet.const_get(:PATH)
    out[:path_is_proc] = path_lambda.is_a?(Proc)
    out[:path_shareable] = Ractor.shareable?(path_lambda)
  rescue => e
    out[:path_err] = e.message[0,80]
  end
  out
end.value.tap { |r| p r }
