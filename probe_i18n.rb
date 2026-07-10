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

dbg = Ractor.new(app) do |a|
  RactorRailsShim.init_worker_ar_connections!
  cfg = I18n.config
  b = cfg.backend
  [
    "config_class=#{cfg.class}",
    "backend_class=#{b.class}",
    "backend_init=#{b.initialized? rescue 'ERR'}",
    "translations_set=#{b.instance_variable_defined?(:@translations)}",
    "translations_class=#{b.instance_variable_get(:@translations)&.class}",
    "I18N_TRANSLATIONS_defined=#{RactorRailsShim.const_defined?(:I18N_TRANSLATIONS)}",
    "I18N_TRANSLATIONS=#{RactorRailsShim::I18N_TRANSLATIONS.inspect[0,80] rescue 'ERR'}",
    "backend_eq_config_backend=#{b.equal?(cfg.backend)}",
  ]
end.value
require "pp"; pp dbg
