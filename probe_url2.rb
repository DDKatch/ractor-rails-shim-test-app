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
    r = h.post_path(post)
    [:ok, r]
  rescue => ex
    root = ex; root = root.cause while root.respond_to?(:cause) && root.cause
    [:err, ex.class.name, ex.message[0,140], "ROOT: #{root.class}: #{root.message[0,140]}", (root.backtrace||[]).first(12)]
  end
end.value.tap { |r| puts r.inspect[0,500]; puts "---" }
