# frozen_string_literal: true

# RAILS_FEATURES.md #144: the engine's controller. Isolated engines wrap
# their controllers in the engine namespace; the view lives in the engine's
# own app/views (the host app's layout is used unless the engine opts out).
module AuditEngine
  class AuditController < AuditEngine::ApplicationController
    # RAILS_FEATURES.md #144: the engine probe — renders from the engine's
    # own view directory and reports engine-specific diagnostics.
    def index
      @engine_name = self.class.module_parent.name
    end
  end
end
