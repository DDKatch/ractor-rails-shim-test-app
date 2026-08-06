class WelcomeJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 5.seconds, attempts: 3

  before_perform :log_start
  after_perform :log_complete

  def perform(user)
    Rails.logger.info "[WelcomeJob] Sending welcome to #{user.email}"
    UserMailer.welcome_email(user).deliver_now
  end

  private

  def log_start
    Rails.logger.info "[WelcomeJob] Starting job for #{arguments.first&.email}"
  end

  def log_complete
    Rails.logger.info "[WelcomeJob] Completed"
  end
end
