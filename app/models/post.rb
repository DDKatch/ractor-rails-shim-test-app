class Post < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :category, optional: true
  has_many :comments, dependent: :destroy
  has_and_belongs_to_many :tags

  # RAILS_FEATURES.md #69: nested attributes (comments built/destroyed
  # through the posts params).
  accepts_nested_attributes_for :comments, allow_destroy: true

  validates :title, presence: true, length: { minimum: 3, maximum: 255 }
  validates :body, presence: true, length: { minimum: 10 }

  before_save :normalize_title
  after_create :log_creation

  scope :recent, -> { order(created_at: :desc) }
  scope :by_title, ->(q) { where("title ILIKE ?", "%#{q}%") }
  scope :with_comments, -> { includes(:comments) }
  scope :popular, -> { left_joins(:comments).group(:id).order("COUNT(comments.id) DESC") }

  # RAILS_FEATURES.md #65: enum (worker-safe constants asserted in
  # test/models/active_record_toolkit_test.rb + a :ractor probe).
  enum :state, { draft: 0, moderated: 1, archived: 2 }, default: :draft

  private

  def normalize_title
    self.title = title.to_s.strip.titleize
  end

  def log_creation
    Rails.logger.info "[Post] Created: #{id} - #{title}"
  end
end
