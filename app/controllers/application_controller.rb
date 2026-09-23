class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authorize_mini_profiler

  private

  # MiniProfiler profiles every request via snapshots, but shows its badge
  # only to logged-in users. HTML only so API keys gain nothing.
  def authorize_mini_profiler
    return unless defined?(::Rack::MiniProfiler)
    return unless request.format.html?
    return unless Current.user

    Rack::MiniProfiler.authorize_request
    Rack::MiniProfiler.add_snapshot_custom_field("user", Current.user.email_address)
  end
end
