class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_one_attached :avatar
  validates :email, presence: true, uniqueness: true

  after_create_commit :enqueue_welcome_email

  scope :recent, -> { order(created_at: :desc) }
  scope :with_posts, -> { includes(:posts) }

  private

  def enqueue_welcome_email
    WelcomeJob.perform_later(self)
  rescue => e
    Rails.logger.warn "[User] Could not enqueue welcome email: #{e.message}"
  end
end
