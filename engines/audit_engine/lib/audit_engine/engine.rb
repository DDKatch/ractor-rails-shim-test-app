# frozen_string_literal: true

# RAILS_FEATURES.md #144: a MINIMAL isolated engine — its own namespace,
# routes, controller, and view, mounted at /audit_engine. "Isolated" means
# the engine's constants live under AuditEngine (its controllers do not
# pollute the host app's namespace) and its routes are namespaced.
module AuditEngine
  class Engine < ::Rails::Engine
    isolate_namespace AuditEngine

    # The engine reuses the HOST app's database (no separate connects_to):
    # its controller renders static content, so no models are needed for
    # the audit probe. A namespaced model (AuditEngine::Record) would be the
    # next step if a probe needed engine-owned tables.
  end
end
