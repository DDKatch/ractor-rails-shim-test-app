# frozen_string_literal: true

# Puma / Falcon (thread-server) boot for full_test_app.
#
# This file boots the app under a normal multi-threaded Rack server instead of
# kino's Ractor mode. It selects the ractor-rails-shim's THREAD mode via the
# SERVER environment variable (puma|falcon|thin|webrick|thread*), which:
#
#   * installs ONLY the class_attribute callback-chain isolation fix and the
#     nil-safe callback replay (the app is broken on Ruby 4.0.5 + Rails 8.1.3
#     by an eager-load class_attribute leak that corrupts __callbacks), and
#   * routes class_attribute values through a SHARED (process-wide) store
#     instead of thread-local IsolatedExecutionState, which is empty on Puma's
#     request threads and would otherwise break the app.
#
# The Ractor-only shim patches (mattr_accessor/zeitwerk/rubygems/...) are
# skipped, because Rails' own globals (class variables / class ivars) are
# thread-safe.
#
# Run:
#   SERVER=puma   bundle exec puma config.ru -p 3000 -e production
#   SERVER=falcon bundle exec falcon config.ru -e production   # (falcon in Gemfile)

ENV["RAILS_ENV"] ||= ENV["RACK_ENV"] || "production"
ENV["SERVER"] ||= "puma"

require "ractor_rails_shim"
RactorRailsShim.install

require_relative "config/application"

# Mirror config_ractor.ru's working boot: eager load, let exceptions propagate
# so the real backtrace is logged.
Rails.application.config.eager_load = true
Rails.application.config.action_dispatch.show_exceptions = :none

# Point the default ActionDispatch::Executor middleware at the Reloader (which
# owns the :run reload callbacks) instead of the bare ActiveSupport::Executor
# class. With config.enable_reloading = false (production) the reload callbacks
# never fire, but this keeps the shared :run chain from erroring if they do.
Rails.application.instance_variable_set(:@executor, ActiveSupport::Reloader)

Rails.application.initialize!

# Build the captured symbolic-filter table (SHAREABLE_DECLARED_CALLBACKS) that
# the shim's nil-safe run_callbacks replays for :process_action in thread mode.
RactorRailsShim._freeze_declared_callbacks! if RactorRailsShim.respond_to?(:_freeze_declared_callbacks!)

Rails.application.config.middleware.delete(ActionDispatch::ShowExceptions) rescue nil
Rails.application.config.middleware.delete(ActionDispatch::DebugExceptions) rescue nil
Rails.application.config.middleware.delete(Rails::Rack::Logger) rescue nil
Rails.application.config.middleware.delete(Rails::Rack::SilenceRequest) rescue nil

run Rails.application
