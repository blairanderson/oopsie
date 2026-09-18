# frozen_string_literal: true

class ApiToken < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :project, optional: true

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  normalizes :name, with: ->(value) { value.to_s.strip }

  validates :name, presence: true, length: { maximum: 40 }
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validates :name, uniqueness: {
    scope: :user_id,
    conditions: -> { where(revoked_at: nil) },
    case_sensitive: false
  }, if: -> { user_id.present? && revoked_at.nil? }
  validates :name, uniqueness: {
    scope: :project_id,
    conditions: -> { where(revoked_at: nil) },
    case_sensitive: false
  }, if: -> { project_id.present? && revoked_at.nil? }
  validate :exactly_one_owner

  def self.digest(secret)
    Digest::SHA256.hexdigest(secret.to_s)
  end

  def self.authenticate(secret)
    return if secret.blank?

    active.find_by(token_digest: digest(secret))
  end

  def self.issue(name:, user: nil, project: nil)
    secret = SecureRandom.hex(32)
    token = new(
      name: name,
      user: user,
      project: project,
      token_digest: digest(secret),
      token_prefix: secret.first(8)
    )
    [ token, token.save ? secret : nil ]
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  def revoked?
    revoked_at.present?
  end

  def record_use!(client:)
    label = client.to_s.truncate(120)
    update_columns(
      last_used_at: Time.current,
      last_seen_client: label.presence,
      requests_count: requests_count + 1
    )
  end

  def masked
    "#{token_prefix}…"
  end

  private

  def exactly_one_owner
    return if user_id.present? ^ project_id.present?

    errors.add(:base, "Token must belong to a user or a project")
  end
end
