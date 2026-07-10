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

# Inspect what `t` is in a real render: patch the helper to log
r = Ractor.new(app) do |a|
  RactorRailsShim.init_worker_ar_connections!
  out = {}
  out[:av_base_has_routes] = ActionView::Base.method_defined?(:_routes)
  out[:ac_base_has_routes] = ActionController::Base.method_defined?(:_routes)
  # find the patch method owner
  out[:av_routes_owner] = (ActionView::Base.instance_method(:_routes).owner rescue nil).to_s
  out[:av_routes_source] = (ActionView::Base.instance_method(:_routes).source_location rescue nil).inspect
  out[:shareable_routes] = RactorRailsShim.const_defined?(:SHAREABLE_ROUTES)
  out[:av_url_options_owner] = (ActionView::Base.instance_method(:url_options).owner rescue nil).to_s
  out
rescue => e
  root = e; root = root.cause while root.respond_to?(:cause) && root.cause
  "ERR #{e.class}: #{e.message[0,300]}\nROOT: #{root.class}: #{root.message[0,300]}\n#{(root.backtrace||[]).first(20).join("\n")}"
end.value
p r
