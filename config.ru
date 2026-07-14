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
# BOOT IS IDEMPOTENT (guarded by $booted). Falcon's threaded container
# re-evaluates this rackup inside each child thread, which would otherwise
# re-require the shim (=> "cannot load such file -- ractor_rails_shim" when the
# child thread lacks the Bundler LOAD_PATH) and re-run Rails.application.
# initialize! (=> duplicate Devise routes such as 'new_user_session'). The
# guard skips the boot block on re-evaluation and just serves the already-built
# app. Falcon's FORKED mode evaluates this once in the parent and forks, so the
# guard is mainly for threaded mode, but it is safe in both.
#
# Forked servers (Falcon --forked) inherit the parent's open PostgreSQL socket;
# using it from a child PID aborts libpq. We disconnect the pool here (inside
# the boot guard, once) so each forked child opens its own connection on first
# query. Harmless for threaded servers (the single process just reconnects).
#
# Run:
#   SERVER=puma   bundle exec puma config.ru -p 3000 -e production
#   SERVER=falcon bundle exec falcon config.ru -e production   # (falcon in Gemfile)

# Capture the parent process's gem load paths ONCE (on the first evaluation,
# in Falcon's main process). Falcon's THREADED container re-evaluates this
# rackup inside each child thread with a reset $LOAD_PATH that no longer
# includes the bundled gems, so a later `require "ractor_rails_shim"` fails
# with "cannot load such file". We restore the captured paths before each
# (re-)evaluation so the gem is resolvable in those child threads. Harmless
# under normal single-evaluation servers (bundle exec already set them).
$rrs_parent_load_path ||= $LOAD_PATH.dup
$rrs_parent_gem_path   ||= Gem.path.dup

ENV["RAILS_ENV"] ||= ENV["RACK_ENV"] || "production"
ENV["SERVER"] ||= "puma"

# Restore the captured load paths (see note above) so `require "bundler/setup"`
# and the shim resolve in Falcon's threaded child threads too. Guarded so a
# missing method on some Ruby builds can't abort boot.
$LOAD_PATH.replace($rrs_parent_load_path) if defined?($rrs_parent_load_path)
Gem.path.replace($rrs_parent_gem_path) if defined?($rrs_parent_gem_path)
require "bundler/setup" rescue nil

# Falcon's threaded / hybrid container starts the rack app in several threads
# that each re-evaluate this rackup. The `$booted` flag alone is NOT safe: two
# threads can both observe `$booted == false` and run `Rails.application.
# initialize!` concurrently, drawing Devise's routes twice ("new_user_session
# already in use"). Serialize the boot with a process-wide mutex so exactly one
# thread initializes Rails; the rest wait and then skip via the flag.
$boot_mutex ||= Mutex.new
$booted    ||= false
$boot_mutex.synchronize do
  unless $booted
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

  # Close the parent's DB connections so forked children don't inherit a shared
  # socket (see comment above). Each child reconnects lazily on first query.
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection_pool.disconnect! rescue nil
  end

  $booted = true
  end
end

run Rails.application
