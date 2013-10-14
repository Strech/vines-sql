# coding: utf-8

module Vines
  class Storage
    class Sql

      # Create the tables and indexes used by this storage engine.
      def create_schema(args={})
        args[:force] ||= false

        ActiveRecord::Schema.define do
          create_table :users, force: args[:force] do |t|
            t.string :jid,      limit: 512, null: false
            t.string :name,     limit: 256, null: true
            t.string :password, limit: 256, null: true
            t.text   :vcard,    null: true
          end
          add_index :users, :jid, unique: true

          create_table :contacts, force: args[:force] do |t|
            t.integer :user_id,      null: false
            t.string  :jid,          limit: 512, null: false
            t.string  :name,         limit: 256, null: true
            t.string  :ask,          limit: 128, null: true
            t.string  :subscription, limit: 128, null: false
          end
          add_index :contacts, [:user_id, :jid], unique: true

          create_table :groups, force: args[:force] do |t|
            t.string :name, limit: 256, null: false
          end
          add_index :groups, :name, unique: true

          create_table :contacts_groups, id: false, force: args[:force] do |t|
            t.integer :contact_id, null: false
            t.integer :group_id,   null: false
          end
          add_index :contacts_groups, [:contact_id, :group_id], unique: true

          create_table :fragments, force: args[:force] do |t|
            t.integer :user_id,   null: false
            t.string  :root,      limit: 256, null: false
            t.string  :namespace, limit: 256, null: false
            t.text    :xml,       null: false
          end
          add_index :fragments, [:user_id, :root, :namespace], unique: true

          # Archive
          create_table :collections, force: args[:force] do |t|
            t.string :jid_from,     limit: 256, null: false
            t.string :jid_with,     limit: 256, null: false
            t.string :jids_hash,    limit: 40, null: false
            t.datetime :created_at, null: false
          end
          add_index :collections, [:jid_from, :jid_with], unique: true
          add_index :collections, :jids_hash, unique: true

          create_table :messages, force: args[:force] do |t|
            t.integer :collection_id, null: false
            t.string :jid,            null: false, limit: 256
            t.text :body,             null: false
            t.boolean :renew_needed,  null: false, default: true
            t.datetime :created_at,   null: false
          end
          add_index :messages, [:collection_id, :jid]
          add_index :messages, :created_at

          execute <<-SQL
            CREATE INDEX index_messages_on_renew_needed_is_true
            ON messages USING btree(renew_needed)
            WHERE renew_needed = TRUE;
          SQL

          create_table :pending_stanzas, force: args[:force] do |t|
            t.integer  :user_id,    null: false
            t.text     :xml,        null: false
            t.datetime :created_at, null: false
          end
          add_index :pending_stanzas, :user_id
        end

        ActiveRecord::Migrator.migrations(migrations_path).each do |migration|
          m = ActiveRecord::Migrator.new(:up, migrations_path, 30000000000000)
          m.send(:record_version_state_after_migrating, migration.version)
        end
      end

      def migrate
        ActiveRecord::Migrator.migrate(migrations_path, ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
      end

      with_connection :create_schema, defer: false
      with_connection :migrate, defer: false

      private
      def migrations_path
        File.expand_path(File.join('..', '..', 'db', 'migrations'), __FILE__)
      end

    end # class Sql
  end # class Storage
end # module Vines
