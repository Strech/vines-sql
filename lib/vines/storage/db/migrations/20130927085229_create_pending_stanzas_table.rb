class CreatePendingStanzasTable < ActiveRecord::Migration
  def change
    create_table :pending_stanzas do |t|
      t.integer  :user_id,    null: false
      t.text     :xml,        null: false
      t.datetime :created_at, null: false
    end

    add_index :pending_stanzas, :user_id
  end
end
