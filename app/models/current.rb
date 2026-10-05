# RAILS_FEATURES.md #129: CurrentAttributes — per-request execution state.
# Set by ApplicationController's before_action (request_id), reset by the
# executor between requests.
class Current < ActiveSupport::CurrentAttributes
  attribute :request_id
  attribute :user

  # Convenience delegate used by worker-rendered views.
  def user_email
    user&.email
  end
end
