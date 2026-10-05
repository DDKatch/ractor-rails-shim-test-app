require "test_helper"

class EmailDeliveryTest < ActionMailer::TestCase
  setup do
    @user = User.create!(
      email: "email-test-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  teardown do
    @user&.avatar&.purge_later rescue nil
    @user&.destroy rescue nil
  end

  test "welcome_email is delivered to the user" do
    email = UserMailer.welcome_email(@user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ @user.email ], email.to
    assert_equal "Welcome to the Ractor Test App!", email.subject
    assert_match "Welcome", email.body.encoded
  end

  test "welcome_email has correct from address" do
    email = UserMailer.welcome_email(@user)
    assert_equal [ "notifications@example.com" ], email.from
  end

  test "welcome_email body contains user email" do
    email = UserMailer.welcome_email(@user)
    email.deliver_now
    assert_match @user.email, email.body.encoded
  end

  test "welcome_email body contains login url" do
    email = UserMailer.welcome_email(@user)
    email.deliver_now
    assert_match "localhost", email.body.encoded
  end

  test "comment_notification email is delivered" do
    post = Post.create!(title: "Comment Notification Test", body: "Body for comment notification test.", user: @user)
    comment = Comment.create!(body: "Great post!", post: post, user: @user)
    email = UserMailer.comment_notification(comment)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal "New comment on your post: Comment Notification Test", email.subject
  end

  test "user create enqueues welcome job" do
    assert_enqueued_with(job: WelcomeJob) do
      User.create!(
        email: "welcome-job-#{SecureRandom.hex(4)}@example.com",
        password: "password",
        password_confirmation: "password"
      )
    end
  end

  test "welcome job delivers email" do
    # Clear any jobs enqueued during setup (the setup user also enqueues a
    # WelcomeJob via after_create_commit).
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    welcome_user = nil
    assert_enqueued_with(job: WelcomeJob) do
      welcome_user = User.create!(
        email: "welcome-job-deliver-#{SecureRandom.hex(4)}@example.com",
        password: "password",
        password_confirmation: "password"
      )
    end

    assert_emails 1 do
      perform_enqueued_jobs(only: WelcomeJob)
    end

    delivered = ActionMailer::Base.deliveries.last
    assert_equal "Welcome to the Ractor Test App!", delivered.subject
    assert_equal [ welcome_user.email ], delivered.to
  end

  # Attachments + CC/BCC audit (RAILS_FEATURES.md #33, #34)
  test "report_email attaches a CSV and copies the audit addresses" do
    post = Post.create!(title: "Report Post", body: "Body for the report email test.", user: @user)
    email = UserMailer.report_email(@user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ @user.email ], email.to
    assert_equal [ "report-audit@example.com" ], email.cc
    assert_equal [ "report-archive@example.com" ], email.bcc
    assert email.attachments.any?, "report_email must carry an attachment"
    attachment = email.attachments.first
    assert_equal "posts-report-#{@user.id}.csv", attachment.filename
    assert_equal "text/csv", attachment.mime_type
    assert_includes attachment.read, "id,title,comments_count"
    assert_includes attachment.read, post.title
  end
end
