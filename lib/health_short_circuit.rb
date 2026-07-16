# frozen_string_literal: true

# Health/readiness probes short-circuited at the Rack layer.
#
# WHY (ractor mode only): GET /up touches neither the DB nor the app graph,
# yet under `kino -m ractor` every request runs inside a worker Ractor and the
# first request of each worker pays WorkerApp#setup_once! (constant rebind +
# ActiveRecord connection establishment) — a ~38 ms cold spike on every health
# probe after a respawn. Returning the JSON directly skips setup_once!, Rails
# routing, and the per-request IsolatedExecutionState / SHAREABLE_FALLBACK
# indirection, dropping /up to sub-ms.
#
# Real routes fall through to @app untouched. The instance is plain Ruby with
# `def call` (no captured block), so it is Ractor-shareable. The response
# mirrors Rails::HealthController#show (200 + {"status":"up"}).
#
# Configure the matched paths per app; defaults to ["/up"].
class HealthShortCircuit
  DEFAULT_PATHS = [ "/up" ].freeze
  DEFAULT_BODY = '{"status":"up"}'.freeze

  def initialize(app, paths: DEFAULT_PATHS, body: DEFAULT_BODY)
    @app = app
    @paths = paths.freeze
    @body = body.freeze
    # Stateless middleware: freeze so the instance is Ractor-shareable
    # (kino :ractor requires the whole app graph to be shareable).
    freeze
  end

  def call(env)
    if @paths.include?(env["PATH_INFO"])
      [ 200, { "Content-Type" => "application/json", "Cache-Control" => "no-cache" }, [ @body ] ]
    else
      @app.call(env)
    end
  end
end
