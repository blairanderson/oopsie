class NotificationRule < ApplicationRecord
  SUPPORTED_EVENTS = %w[new_error regression].freeze
  EVENT_ALIASES = {
    "error.created" => "new_error",
    "error.reopened" => "regression",
    "error.regressed" => "regression"
  }.freeze
  HTTP_HEADER_NAME = /\A[a-zA-Z0-9!#$%&'*+\-.^_`|~]+\z/

  belongs_to :project

  attr_accessor :webhook_header_name, :webhook_header_value

  enum :channel, { email: 0, webhook: 1 }

  validates :channel, presence: true
  validates :destination, presence: true
  validate :destination_is_valid_url, if: -> { webhook? && destination.present? }
  validate :webhook_headers_are_valid, if: :webhook?
  validate :events_are_supported

  before_validation :normalize_events
  before_validation :apply_webhook_header_fields

  def self.canonical_event(event)
    value = event.to_s.strip
    EVENT_ALIASES.fetch(value, value)
  end

  def events
    Array(self[:events]).presence || SUPPORTED_EVENTS
  end

  def events=(values)
    normalized = Array(values).flat_map { |value| value.to_s.split(",") }
                              .map { |value| self.class.canonical_event(value) }
                              .reject(&:blank?)
                              .uniq
    self[:events] = normalized
  end

  def notify_for_event?(event)
    events.include?(self.class.canonical_event(event))
  end

  def webhook_headers
    value = self[:webhook_headers]
    value.is_a?(Hash) ? value.stringify_keys : (value.presence || {})
  end

  def webhook_headers=(value)
    self[:webhook_headers] = if value.respond_to?(:to_h)
      value.to_h.each_with_object({}) do |(name, header_value), headers|
        headers[name.to_s.strip] = header_value.is_a?(String) ? header_value.strip : header_value
      end
    else
      value
    end
  end

  def webhook_header_name
    @webhook_header_name ||= webhook_headers.keys.first
  end

  def webhook_header_value
    @webhook_header_value ||= webhook_headers.values.first
  end

  def destination_masked
    webhook? ? mask_webhook_url : mask_email
  end

  private

  def mask_webhook_url
    uri = URI.parse(destination)
    return "[masked]" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    "#{uri.scheme}://#{uri.host}/..."
  rescue URI::InvalidURIError
    "[masked]"
  end

  def mask_email
    local, domain = destination.to_s.split("@", 2)
    return "[masked]" if local.blank? || domain.blank?

    "#{local.first}***@#{domain}"
  end

  def normalize_events
    self.events = events
  end

  def apply_webhook_header_fields
    return if @webhook_header_name.nil? && @webhook_header_value.nil?

    name = webhook_header_name.to_s.strip
    value = webhook_header_value.to_s.strip
    self.webhook_headers = if name.blank? && value.blank?
      {}
    else
      { name => value }
    end
  end

  def webhook_headers_are_valid
    headers = webhook_headers
    unless headers.is_a?(Hash)
      errors.add(:webhook_headers, "must be a map of valid HTTP headers")
      return
    end

    headers.each do |name, value|
      unless name.is_a?(String) && name.match?(HTTP_HEADER_NAME)
        errors.add(:webhook_headers, "must use valid HTTP header names")
      end

      unless value.is_a?(String) && value.present? && value !~ /[\r\n]/
        errors.add(:webhook_headers, "must use valid HTTP header values")
      end
    end
  end

  def events_are_supported
    values = Array(self[:events])

    if values.empty?
      errors.add(:events, "must include at least one event")
      return
    end

    unsupported = values - SUPPORTED_EVENTS
    if unsupported.any?
      errors.add(:events, "include unsupported event(s): #{unsupported.join(', ')}")
    end
  end

  def destination_is_valid_url
    uri = URI.parse(destination)
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      errors.add(:destination, "must be an HTTP or HTTPS URL")
    end
  rescue URI::InvalidURIError
    errors.add(:destination, "is not a valid URL")
  end
end
