require "test_helper"

# Active Job resilience + enqueue options audit
# (RAILS_FEATURES.md rows 107-108).
class JobResilienceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    $flaky_job_attempts = 0
    $discard_job_attempts = 0
  end

  test "retry_on retries the configured attempts then re-raises" do
    FlakyJob.perform_later
    # The test adapter performs one pass per call; the retried copy (with
    # its serialized executions counter) is drained by the next call.
    perform_enqueued_jobs
    assert_equal 1, $flaky_job_attempts
    # Budget (attempts: 2) exhausted: retry_on re-raises (swallowing needs
    # discard_on or a block form of retry_on).
    assert_raises(StandardError) do
      perform_enqueued_jobs
    end
    assert_equal 2, $flaky_job_attempts
    assert_empty queue_adapter.enqueued_jobs
  end

  test "discard_on discards without retrying" do
    DiscardJob.perform_later
    assert_nothing_raised do
      perform_enqueued_jobs
    end
    assert_equal 1, $discard_job_attempts
  end

  test "enqueue options: queue name and wait are honored" do
    assert_enqueued_with(job: WelcomeJob, queue: "low") do
      WelcomeJob.set(queue: "low", wait: 5.seconds).perform_later(users(:one))
    end

    enqueued = queue_adapter.enqueued_jobs.first
    assert_equal "low", enqueued[:queue]
    assert enqueued[:at].present?, "wait: should schedule a future run time"
  end
end
