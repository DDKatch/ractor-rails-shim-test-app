# frozen_string_literal: true

# RAILS_FEATURES.md #144: the isolated engine's base controller. Isolated
# engines inherit from their OWN ApplicationController (under the engine
# namespace), not the host app's — the shim's frozen-graph walk must cover
# this class too (it reaches engine classes through Rails.application's
# eager-load graph).
module AuditEngine
  class ApplicationController < ::ActionController::Base
  end
end
