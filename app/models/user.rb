class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :api_key, presence: true, uniqueness: true

  before_validation :generate_api_key, on: :create

  def regenerate_api_key!
    update!(api_key: SecureRandom.hex(32))
  end

  private

  def generate_api_key
    self.api_key = SecureRandom.hex(32) if api_key.blank?
  end
end
