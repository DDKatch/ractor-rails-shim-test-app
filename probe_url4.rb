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
Ractor.new(app, helpers) do |a, h|
  RactorRailsShim.init_worker_ar_connections!
  post = Post.first
  begin
    h.post_path(post)
    [:ok]
  rescue => ex
    root = ex; root = root.cause while root.respond_to?(:cause) && root.cause
    [:err, root.class.name, root.message[0,140], (root.backtrace||[])]
  end
end.value.tap { |r| p r }
