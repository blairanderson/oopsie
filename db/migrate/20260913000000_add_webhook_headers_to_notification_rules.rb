class AddWebhookHeadersToNotificationRules < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_rules, :webhook_headers, :json unless column_exists?(:notification_rules, :webhook_headers)
  end
end
