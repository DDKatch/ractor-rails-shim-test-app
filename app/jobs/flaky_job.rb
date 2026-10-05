# RAILS_FEATURES.md #107: retry_on — FlakyJob always raises StandardError:
# retried `attempts` times total, then the error RE-RAISES (retry_on does
# not swallow on exhaustion — that needs discard_on or the block form).
class FlakyJob < ApplicationJob
  retry_on StandardError, wait: 0, attempts: 2

  def perform
    $flaky_job_attempts += 1
    raise StandardError, "always fails"
  end
end
