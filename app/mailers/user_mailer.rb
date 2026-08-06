class UserMailer < ApplicationMailer
  default from: "notifications@example.com"

  def welcome_email(user)
    @user = user
    @login_url = new_user_session_url(host: "localhost")

    mail(
      to: @user.email,
      subject: "Welcome to the Ractor Test App!"
    )
  end

  def comment_notification(comment)
    @comment = comment
    @post = comment.post
    @user = @post.user

    mail(
      to: @user.email,
      subject: "New comment on your post: #{@post.title}"
    )
  end
end
