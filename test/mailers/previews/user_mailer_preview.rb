# Mailer previews (RAILS_FEATURES.md #32): served by the built-in
# /rails/mailers engine in development (preview path configured in
# config/application.rb). Falls back to unsaved records when the DB is empty,
# so previews always render.
class UserMailerPreview < ActionMailer::Preview
  def welcome_email
    UserMailer.welcome_email(User.first || preview_user)
  end

  def comment_notification
    comment = Comment.first
    comment = preview_comment if comment.nil? || comment.post&.user.nil?
    UserMailer.comment_notification(comment)
  end

  def report_email
    UserMailer.report_email(User.first || preview_user)
  end

  private

  def preview_user
    User.new(email: "preview@example.com")
  end

  def preview_comment
    user = preview_user
    post = Post.new(title: "Preview post", body: "Preview body for the comment notification preview.", user: user)
    Comment.new(body: "Preview comment body", post: post, user: user)
  end
end
