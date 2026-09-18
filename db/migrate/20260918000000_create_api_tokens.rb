class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.references :user, foreign_key: true
      t.references :project, foreign_key: true
      t.datetime :last_used_at
      t.string :last_seen_client
      t.integer :requests_count, null: false, default: 0
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
    add_index :api_tokens, [ :user_id, :name ], unique: true, where: "revoked_at IS NULL AND user_id IS NOT NULL", name: "index_active_user_api_tokens_on_name"
    add_index :api_tokens, [ :project_id, :name ], unique: true, where: "revoked_at IS NULL AND project_id IS NOT NULL", name: "index_active_project_api_tokens_on_name"
  end
end
