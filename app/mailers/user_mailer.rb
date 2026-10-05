require "csv"

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

  # Mailer attachments + CC/BCC (RAILS_FEATURES.md #33, #34): builds a CSV
  # report of the user's posts, attaches it, and copies (cc) / blind-copies
  # (bcc) the audit addresses.
  def report_email(user)
    @user = user
    csv = CSV.generate(headers: true) do |out|
      out << %w[id title comments_count]
      user.posts.order(:id).find_each do |post|
        out << [ post.id, post.title, post.comments_count ]
      end
    end
    attachments["posts-report-#{user.id}.csv"] = { mime_type: "text/csv", content: csv }

    mail(
      to: @user.email,
      cc: "report-audit@example.com",
      bcc: "report-archive@example.com",
      subject: "Your posts report"
    )
  end
end
