# RAILS_FEATURES.md #107: discard_on — ArgumentError discards the job
# without retrying (and without bubbling up).
class DiscardJob < ApplicationJob
  discard_on ArgumentError

  def perform
    $discard_job_attempts += 1
    raise ArgumentError, "argument error discards"
  end
end
