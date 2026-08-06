require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "welcome email" do
    user = users(:one)
    email = UserMailer.welcome_email(user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [user.email], email.to
    assert_equal "Welcome to the Ractor Test App!", email.subject
    assert_match "Welcome", email.body.encoded
  end
end
