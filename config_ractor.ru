# frozen_string_literal: true

# kino boot file for the dummy app. Mode-aware:
#
#   - :ractor   (production): eager-load + freeze + RactorRailsShim shareable
#               graph. Memory-efficient; no code reloading (frozen graph can't
#               be hot-reloaded).
#   - :threaded (development): plain Rails boot, lazy-load + code reloading ON,
#               so `kino config_ractor.ru` in dev gives live reload with no
#               Ractor isolation. The app is NOT frozen, so the eager-load
#               class_attribute callback-chain leak (Ruby 4.0.5 + Rails 8.1.3 +
#               Devise) never triggers and before_action/after_action filters
#               run normally.
#
# Mode is chosen by KINO_MODE (threaded|ractor); if unset it defaults to
# threaded in development and ractor in production. kino's own -m flag is
# consumed by kino itself, so SET KINO_MODE TO MATCH -m, e.g.:
#
#   KINO_MODE=ractor   kino -m ractor   config_ractor.ru   # production
#   KINO_MODE=threaded kino -m threaded config_ractor.ru   # development
#
# The default (dev -> threaded, prod -> ractor) lets you just run `kino
# config_ractor.ru` in the right RAILS_ENV.
#
# RactorRailsShim.install MUST run before Rails.application.initialize! when
# using :ractor (the shim patches Journey/ActiveRecord internals Rails uses
# while drawing routes; installed after boot the RouteSet holds only the
# railtie route and every application route 404s).

mode = (ENV["KINO_MODE"] ||
        ((ENV["RAILS_ENV"] || "development") == "production" ? "ractor" : "threaded")).to_sym

if mode == :ractor
  # Full shim load BEFORE the app boots. See notes above.
  begin
    require "ractor_rails_shim"
    RactorRailsShim.install
  rescue LoadError
    nil
  end

  # Boot the dummy app for kino. In development we force eager loading so the
  # shared app graph is fully loaded *before* being frozen and made shareable
  # for kino's :ractor workers — autoloading is not Ractor-safe.
  require_relative "config/application"
  # Install the Ractor-safe URL-helper generation BEFORE routes are drawn
  # (Rails.application.initialize! draws them). This regenerates the named
  # route helpers and `_routes`/`_generate_paths_by_default` as compiled `def`
  # methods and replaces the PATH/UNKNOWN lambdas with shareable Method
  # objects, so workers can call them without "un-shareable Proc" errors.
  RactorRailsShim.install_route_helpers_patch if RactorRailsShim.respond_to?(:install_route_helpers_patch)
  Rails.application.config.eager_load = true if Rails.env.development?
  # Disable the Propshaft sweep_cache watcher (mutates the frozen shared
  # LoadPath cache in workers -> FrozenError). Production defaults it to false.
  Rails.application.config.assets.sweep_cache = false if Rails.env.development?
  # Turn on template caching for the kino :ractor boot (dev enables reload
  # watchers that mutate the frozen shared graph).
  Rails.application.config.action_view.cache_template_loading = true if Rails.env.development?
  Rails.application.config.enable_reloading = false if Rails.env.development?
  # Force single-threaded eager load. Parallel eager loading races with the
  # RouteSet draw and leaves the shared graph holding only the railtie route
  # (rails/info), so every application route 404s. Single thread draws all
  # routes deterministically; we then confirm >1 anchored route before freeze.
  Rails.application.config.eager_load_threads = 1 if Rails.env.development?
  # Let exceptions propagate so the real backtrace is logged; otherwise
  # swallow (render 500) to keep workers alive.
  Rails.application.config.action_dispatch.show_exceptions = :none
  Rails.application.initialize!

  # --- CSRF forgery protection (baked into the frozen :ractor graph) --------
  # The ractor-rails-shim-test-app does not call `protect_from_forgery` by default, so
  # `protect_against_forgery?` is false and worker Ractors never issue a CSRF
  # token (no hidden field, no <meta name="csrf-token">). We turn it on here,
  # AFTER initialize! but BEFORE prepare_for_ractors!/make_app_shareable!, so
  # the `true` value is frozen into the shared graph the workers read. This
  # mirrors test/integration/ractor_server_test.rb:48,82-83 and lets the
  # benchmark exercise the real authenticated write path. Forms stay remote
  # (Turbo), so the token is emitted as a <meta name="csrf-token"> tag.
  Rails.application.config.action_controller.allow_forgery_protection = true
  ActionController::Base.allow_forgery_protection = true
  ApplicationController.before_action :verify_authenticity_token

  # The CachingKeyGenerator (Rails.application.key_generator) keeps a per-secret
  # memoization cache (@key_generators). During boot/eager-load it may be primed
  # with keys derived from a not-yet-final secret_key_base, and that stale cache
  # is then frozen into the shared :ractor graph. Worker Ractors then encrypt
  # session cookies with a key that no longer matches what they decrypt with ->
  # empty sessions. Reset the cache so it is re-derived after the app is fully
  # initialized (with the real secret_key_base).
  Rails.application.instance_variable_set(:@key_generators, {})

  # Pre-compute env_config in the MAIN Ractor so its memoized @app_env_config
  # (holding secret_key_base / key_generator / cookie salts) is frozen into the
  # shared graph. Without this, worker Ractors recompute env_config on first
  # request and hit `Rails::Railtie::Configuration#@@options` (a class variable
  # forbidden outside the main Ractor) -> Ractor::IsolationError swallowed by
  # ActionDispatch as an empty session.
  Rails.application.env_config
  # (holding secret_key_base / key_generator / cookie salts) is frozen into the
  # shared graph. Without this, worker Ractors recompute env_config on first
  # request and hit `Rails::Railtie::Configuration#@@options` (a class variable
  # forbidden outside the main Ractor) -> Ractor::IsolationError swallowed by
  # ActionDispatch as an empty session.
  Rails.application.env_config

  # The shim deep-freezes the logger (incl. its SimpleFormatter), so the
  # logging/exception middlewares raise FrozenError while trying to log a worker
  # exception — masking the real error (and crashing the first request in prod).
  # Drop them so worker exceptions propagate to kino's error handling. The
  # shim's WorkerApp already surfaces a 555 + backtrace for unhandled worker
  # errors; kino logs those itself.
  Rails.application.config.middleware.delete(ActionDispatch::ShowExceptions) rescue nil
  Rails.application.config.middleware.delete(ActionDispatch::DebugExceptions) rescue nil
  Rails.application.config.middleware.delete(Rails::Rack::Logger) rescue nil
  Rails.application.config.middleware.delete(Rails::Rack::SilenceRequest) rescue nil

  # Eager-load ALL app subdirectories so every controller/model is defined (and
  # thus present in AbstractController::Base.descendants) BEFORE the shim builds
  # its view_context_class registry in prepare_for_ractors!. This dummy app's
  # eager_load_paths only contains lib, so without this the app controllers are
  # never loaded until lazily autoloaded (which workers cannot do) and the
  # registry would miss them — leaving their views without route url_helpers.
  if Rails.env.development?
    Rails.application.config.eager_load = true
    app_dirs = Dir["#{Rails.root}/app/*"].select { |d| File.directory?(d) }
    # Also eager-load engine controllers (e.g. Devise) so they're present in
    # AbstractController::Base.descendants and thus in the shim's
    # view_context_class registry. Engine app/controllers aren't under the app's
    # own eager_load_paths.
    engine_dirs = Rails::Engine.subclasses.reject { |e| e == Rails::Application }.map do |engine|
      candidate = engine.root.join("app/controllers")
      candidate.to_s if candidate.exist?
    end.compact
    Rails.application.config.eager_load_paths |= (app_dirs + engine_dirs)
    Rails.application.eager_load!
  end
  # Guard against route-collapse: poll until the RouteSet actually holds the app
  # routes (not just the railtie). Without this the frozen shared graph can be
  # left with only rails/info and all app routes 404.
  if Rails.env.development?
    (1..120).each do |i|
      break if Rails.application.routes.routes.anchored_routes.size > 1
      sleep 0.5
    end
  end
  app = Rails.application

  if RactorRailsShim.respond_to?(:prepare_for_ractors!)
    RactorRailsShim.prepare_for_ractors!
    # Capture the application's constant name -> object bindings BEFORE freezing
    # the app. `Ractor.make_shareable(app)` deep-freezes the Zeitwerk autoloaders,
    # after which their cpath enumeration returns nothing, so the capture must
    # happen on the still-warm app.
    app_constants = RactorRailsShim.capture_app_constants
    app = RactorRailsShim.make_app_shareable!(Rails.application)
    # Each kino worker Ractor runs with no shared DB connections and with its own
    # (empty) top-level constant namespace for the app's own model constants.
    # Wrap the app so the first request served by each worker (a) rebinds the
    # captured application constants (name -> shared object) into that worker's
    # namespace, and (b) establishes its own ActiveRecord connection handler.
    # The wrapper holds only shareable state, so it is Ractor.make_shareable.
    app = Ractor.make_shareable(RactorRailsShim::WorkerApp.new(app, app_constants))
    # ActionDispatch::ParamBuilder.default holds a ParamBuilder instance set via
    # cattr_accessor. The shim's shareable fallback can miss it (its worker
    # reader then returns nil), so `ParamBuilder.from_pairs` blows up with
    # `nil.from_pairs` inside worker Ractors. Freeze a shareable copy and override
    # the class reader so every Ractor gets the same instance.
    #
    # IMPORTANT: the override must be a plain `def` (string-eval), NOT a
    # `define_method` with a block — a block closure is compiled in the main
    # Ractor and calling it from a worker raises "defined with an un-shareable
    # Proc in a different Ractor". The frozen instance is stashed in a constant
    # (shareable) and read via constant lookup, which is Ractor-safe.
    if defined?(::ActionDispatch::ParamBuilder)
      pb = ::ActionDispatch::ParamBuilder
      fd = pb.make_default(100)
      fd.freeze
      Ractor.make_shareable(fd) rescue nil
      pb.const_set(:RACTOR_SHAREABLE_DEFAULT, fd) rescue nil
      pb.singleton_class.class_eval <<-RUBY
        def default
          ::ActionDispatch::ParamBuilder::RACTOR_SHAREABLE_DEFAULT
        end
      RUBY
    end

    # --- Benchmark hook (inert unless BENCHMARK_STATS=1) ---------------------
    # The frozen, Ractor-shareable app graph lives in the MAIN Ractor. A worker
    # Ractor's ObjectSpace.each_object only sees its own local heap, so the
    # graph-wide shareable fraction must be captured HERE (after the freeze),
    # in the main Ractor, and stashed in a frozen, shareable constant that the
    # /stats endpoint reads. Also enables GC profiling for gc_time_ms.
    if ENV["BENCHMARK_STATS"]
      require "objspace"
      GC::Profiler.enable
      s_count = 0
      s_bytes = 0
      t_count = 0
      t_bytes = 0
      ObjectSpace.each_object do |o|
        b = ObjectSpace.memsize_of(o)
        t_count += 1
        t_bytes += b
        if Ractor.shareable?(o)
          s_count += 1
          s_bytes += b
        end
      end
      BENCH_SHAREABLE = {
        bytes: s_bytes,
        fraction: (t_bytes.zero? ? 0.0 : (s_bytes.to_f / t_bytes * 100)).round(2),
        total_bytes: t_bytes,
        total_count: t_count,
        shareable_count: s_count
      }.freeze
    end
  end

  run app
else
  # :threaded — development live reload. Plain Rails boot, NO shim freeze, NO
  # eager-load forcing, code reloading left ON (the dev default). The app runs
  # in kino's main-Ractor threads with full Rails reloading.
  require_relative "config/application"
  Rails.application.initialize!
  # Enable forgery protection when benchmarking so the authenticated POST
  # write path works the same as in :ractor mode (otherwise no CSRF token is
  # emitted and the harness's POST auth fails). Guarded so it never affects
  # normal :threaded dev usage.
  if ENV["BENCHMARK_STATS"]
    Rails.application.config.action_controller.allow_forgery_protection = true
    ActionController::Base.allow_forgery_protection = true
    ApplicationController.before_action :verify_authenticity_token
  end
  run Rails.application
end
