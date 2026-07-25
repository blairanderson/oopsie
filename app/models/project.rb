class Project < ApplicationRecord
  has_many :error_groups, dependent: :destroy
  has_many :error_group_notes, through: :error_groups
  has_many :notification_rules, dependent: :destroy

  enum :status, { active: 0, disabled: 1 }

  validates :name, presence: true, uniqueness: true
  validates :api_key, presence: true, uniqueness: true
  validates :status, presence: true

  before_validation :set_default_status
  before_validation :generate_api_key, on: :create
  before_save :sync_disabled_at

  def regenerate_api_key!
    update!(api_key: SecureRandom.hex(32))
  end

  def disable!
    update!(status: :disabled)
  end

  def enable!
    update!(status: :active)
  end

  def accepts_ingest?
    active?
  end

  private

  def set_default_status
    self.status ||= :active
  end

  def generate_api_key
    self.api_key ||= SecureRandom.hex(32)
  end

  def sync_disabled_at
    if disabled?
      self.disabled_at ||= Time.current
    else
      self.disabled_at = nil
    end
  end
end
