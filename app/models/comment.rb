class Comment < ApplicationRecord
  belongs_to :user
  # `touch: true` invalidates cached fragments that embed this post
  # (RAILS_FEATURES.md #48): comment changes bump post.updated_at, which is
  # part of the post's cache_key (show-page fragment) and of the index
  # fragment key. (Rails 8 removed ActionController sweepers; touch-based
  # cache-key invalidation is the replacement — see RAILS_FEATURES.md.)
  belongs_to :post, counter_cache: true, touch: true

  # RAILS_FEATURES.md #68: has_one :through (comment -> post -> category).
  has_one :category, through: :post

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
