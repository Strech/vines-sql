class AddRenewNeededToMessage < ActiveRecord::Migration
  def up
    change_table :messages do |t|
      t.boolean :renew_needed, null: false, default: true
    end

    execute <<-SQL
      CREATE INDEX index_messages_on_renew_needed_is_true
      ON messages USING btree(renew_needed)
      WHERE renew_needed = TRUE;
    SQL
  end

  def down
    change_table :messages do |t|
      t.remove :renew_needed
    end

    execute <<-SQL
      DROP INDEX IF EXISTS index_messages_on_renew_needed_is_true;
    SQL
  end
end
