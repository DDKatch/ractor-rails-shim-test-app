# frozen_string_literal: true
require_relative "config/environment"
app = Rails.application

if ENV["RAILS_ENV"] == "production" && defined?(RactorRailsShim)
  RactorRailsShim.prepare_for_ractors!
  app = RactorRailsShim.make_app_shareable!(Rails.application)
  # Each kino worker Ractor runs in its own Ractor with no shared DB
  # connections. Wrap the app so the first request served by each worker
  # establishes its own ActiveRecord connection handler (Blocker 1). The
  # wrapper must be made shareable for kino's Ractor.shareable? check.
  app = Ractor.make_shareable(RactorRailsShim.worker_ar_init(app))
end

if ENV["KINO_DEBUG"]
  # Class-based wrapper (not a lambda): def methods don't capture bindings,
  # so the wrapper is shareable as long as @app is. A lambda's `self` is the
  # main object (not shareable), so it would fail in :ractor mode.
  class KinoDebugWrapper
    LOG = "/tmp/kino_debug.log"
    def initialize(app)
      @app = app
    end
    def call(env)
      File.write(LOG,
        "[REQ] #{env['REQUEST_METHOD']} #{env['PATH_INFO']} " \
        "ACCEPT=#{env['HTTP_ACCEPT'].inspect} " \
        "CONTENT_TYPE=#{env['CONTENT_TYPE'].inspect} " \
        "ENV_KEYS=#{env.keys.sort.inspect}\n", mode: "a")
      status, headers, body = @app.call(env)
      File.write(LOG, "[RES] #{status} #{headers['content-type'].inspect}\n", mode: "a")
      [status, headers, body]
    rescue Exception => e
      root = e
      root = root.cause while root.respond_to?(:cause) && root.cause
      bt = (root.backtrace || []).join("\n  ")
      File.write(LOG,
        "[EXC] #{e.class}: #{e.message}\n  #{(e.backtrace || []).first(15).join("\n  ")}\n" \
        "[ROOT] #{root.class}: #{root.message}\n  #{bt.first(2000)}\n",
        mode: "a")
      # Return the error in the body so it is visible via curl and the
      # worker Ractor survives (do NOT re-raise Exception-level errors,
      # which would kill the kino worker).
      [500, { "content-type" => "text/plain; charset=utf-8" },
        ["#{root.class}: #{root.message}\n#{bt}"]]
    end
  end
  wrapper = KinoDebugWrapper.new(app)
  app = Ractor.make_shareable(wrapper)
  File.write(KinoDebugWrapper::LOG, "=== KINO_DEBUG session #{Time.now.iso8601} ===\n")
end

run app
