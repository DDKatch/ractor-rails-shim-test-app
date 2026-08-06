class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post, counter_cache: true

  validates :body, presence: true, length: { minimum: 2, maximum: 1000 }

  after_create :notify_post_author

  scope :recent, -> { order(created_at: :desc) }
  scope :by_user, ->(user) { where(user: user) }

  private

  def notify_post_author
    # Placeholder for notification logic
    Rails.logger.info "[Comment] #{user&.email} commented on post #{post_id}"
  end
end
