require "test_helper"

class WelcomeJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "WelcomeJob exists and can be instantiated" do
    assert defined?(WelcomeJob), "WelcomeJob should be defined"
    job = WelcomeJob.new
    assert job.is_a?(ApplicationJob)
  end

  test "perform_later enqueues with the test adapter" do
    user = users(:one)
    assert_enqueued_with(job: WelcomeJob) do
      WelcomeJob.perform_later(user)
    end
  end
end
