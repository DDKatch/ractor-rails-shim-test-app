require "test_helper"

# Solid Queue audit (RAILS_FEATURES.md row 110): the Rails 8 default
# database-backed job queue, pointed at the primary DB. Performing is the
# dispatcher process's job (bin/jobs) and is not asserted here — the
# enqueue path is what ships inside a request/job transaction.
#
# Two test-environment notes (both upstream Rails 8.1 semantics, not shim
# concerns):
# - The solid_queue adapter defers enqueues until ALL transactions commit
#   (enqueue_after_transaction_commit?), which never happens under
#   transactional tests — the audit opts the job class out via the
#   documented per-job switch.
# - ActiveJob::TestHelper only applies queue_adapter_for_test to classes
#   with an explicitly SET adapter (queue_adapter_changed_jobs), so the
#   adapter is set explicitly per-test.
class SolidQueueAuditTest < ActiveSupport::TestCase
  setup do
    @original_adapter = WelcomeJob.queue_adapter
    @original_enqueue_after_transaction_commit = WelcomeJob.enqueue_after_transaction_commit
    WelcomeJob.queue_adapter = :solid_queue
    WelcomeJob.enqueue_after_transaction_commit = false
  end

  teardown do
    WelcomeJob.queue_adapter = @original_adapter
    WelcomeJob.enqueue_after_transaction_commit = @original_enqueue_after_transaction_commit
  end

  test "enqueueing through the solid_queue adapter writes a ready execution" do
    user = User.create!(email: "sq-#{SecureRandom.hex(4)}@example.com", password: "password123")
    post = Post.create!(title: "SQ Post", body: "Body for the solid queue audit, long enough.", user: user)

    assert_difference "SolidQueue::Job.count", 1 do
      assert_difference "SolidQueue::ReadyExecution.count", 1 do
        WelcomeJob.perform_later(post)
      end
    end

    job = SolidQueue::Job.order(:id).last
    assert_equal "default", job.queue_name
    assert_equal "WelcomeJob", job.class_name
    # SolidQueue::Job#arguments holds the full ActiveJob serialization.
    gid = job.arguments["arguments"].first
    assert_equal post.id.to_s, GlobalID.parse(gid.is_a?(Hash) ? gid["_aj_globalid"] : gid).model_id

    # A scheduled enqueue lands in the future-scheduled state instead.
    assert_difference "SolidQueue::ScheduledExecution.count", 1 do
      WelcomeJob.set(wait: 1.minute).perform_later(post)
    end
  end
end
