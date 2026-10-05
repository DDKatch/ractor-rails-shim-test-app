require "test_helper"
require "rake"

# Rake tasks audit (RAILS_FEATURES.md #57).
class PostsTaskTest < ActiveSupport::TestCase
  setup do
    unless Rake::Task.task_defined?("posts:stats")
      Rails.application.load_tasks
    end
    @user = User.create!(email: "task-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @post = Post.create!(title: "Task Post", body: "Body for the rake task test.", user: @user)
  end

  teardown do
    @user&.destroy rescue nil
  end

  test "posts:stats prints the row counts" do
    Rake::Task["posts:stats"].reenable
    out, _err = capture_io { Rake::Task["posts:stats"].invoke }
    assert_match(/Posts: \d+/, out)
    assert_match(/Users: \d+/, out)
  end

  test "posts:recount_comments repairs the denormalized counter" do
    @post.update_columns(comments_count: 99)
    Rake::Task["posts:recount_comments"].reenable
    capture_io { Rake::Task["posts:recount_comments"].invoke }
    assert_equal 0, @post.reload.comments_count
  end
end
