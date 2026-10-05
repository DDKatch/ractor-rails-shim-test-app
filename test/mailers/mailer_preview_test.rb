require "test_helper"
require_relative "previews/user_mailer_preview"

# Mailer previews audit (RAILS_FEATURES.md #32): the preview class must be
# discoverable on the preview path and every preview must build a message.
class MailerPreviewTest < ActiveSupport::TestCase
  test "user mailer previews are registered on the preview path" do
    assert_includes ActionMailer::Preview.all.map(&:name), "UserMailerPreview"
  end

  test "welcome_email preview returns a message" do
    message = UserMailerPreview.new.welcome_email
    assert_kind_of ActionMailer::MessageDelivery, message
    assert_equal "Welcome to the Ractor Test App!", message.subject
  end

  test "comment_notification preview returns a message" do
    message = UserMailerPreview.new.comment_notification
    assert_kind_of ActionMailer::MessageDelivery, message
    assert_match "New comment", message.subject
  end

  test "report_email preview returns a message with an attachment" do
    message = UserMailerPreview.new.report_email
    assert_kind_of ActionMailer::MessageDelivery, message
    assert message.attachments.any?, "the report_email preview must build a message with an attachment"
  end
end
