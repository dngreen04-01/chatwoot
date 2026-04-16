class CreateKinShopifyInstallations < ActiveRecord::Migration[7.1]
  def change
    create_table :kin_shopify_installations do |t|
      t.references :account, null: false, foreign_key: true
      t.string :shopify_domain, null: false
      t.text :shopify_access_token_ciphertext
      t.string :shopify_store_name
      t.string :shopify_plan
      t.string :billing_charge_id
      t.string :billing_status, default: 'pending'
      t.datetime :installed_at
      t.datetime :uninstalled_at

      t.timestamps
    end

    add_index :kin_shopify_installations, :shopify_domain, unique: true
    add_index :kin_shopify_installations, :billing_status
  end
end
