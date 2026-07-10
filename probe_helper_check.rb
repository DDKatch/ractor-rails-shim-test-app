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

result = Ractor.new(app) do |a|
  RactorRailsShim.init_worker_ar_connections!
  routes = RactorRailsShim::SHAREABLE_ROUTES
  uh = routes.url_helpers
  {
    has_session_path: uh.respond_to?(:session_path),
    has_session_url: uh.respond_to?(:session_url),
    session_methods: uh.instance_methods.grep(/session/),
    has_url_helpers_const: RactorRailsShim.const_defined?(:URL_HELPERS),
    url_helpers_keys: (RactorRailsShim::URL_HELPERS.keys.grep(/session/) rescue "N/A"),
    main_app_class: (begin; c = Devise::Controllers::UrlHelpers.instance_method(:main_app); c.source_location.inspect; rescue => e; e.message; end),
  }
end.value

require "pp"; pp result
