require "test_helper"

class WelcomeJobTest < ActiveSupport::TestCase
  test "WelcomeJob exists and can be instantiated" do
    assert defined?(WelcomeJob), "WelcomeJob should be defined"
    job = WelcomeJob.new
    assert job.is_a?(ApplicationJob)
  end
end
