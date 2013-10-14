require 'active_record'
require 'digest/sha1'

module Vines
  class Storage
    class Sql < Storage
      register :sql

      MAX_PENDING_STANZAS_PER_USER = 1000
      PENDING_STANZAS_BATCH_SIZE   = 50

      class Contact < ActiveRecord::Base
        belongs_to :user
      end

      class Fragment < ActiveRecord::Base
        belongs_to :user
      end

      class PendingStanza < ActiveRecord::Base
        belongs_to :user
      end

      class Group < ActiveRecord::Base; end

      class User < ActiveRecord::Base
        has_many :contacts,        dependent: :destroy
        has_many :fragments,       dependent: :delete_all
        has_many :pending_stanzas, dependent: :delete_all

        # TODO : Add collections association
      end

      class Collection < ActiveRecord::Base
        has_many :messages
      end

      class Message < ActiveRecord::Base
        belongs_to :collection
      end

      # Wrap the method with ActiveRecord connection pool logic, so we properly
      # return connections to the pool when we're finished with them. This also
      # defers the original method by pushing it onto the EM thread pool because
      # ActiveRecord uses blocking IO.
      def self.with_connection(method, args={})
        deferrable = args.key?(:defer) ? args[:defer] : true
        old = instance_method(method)

        # Define EM-safe method
        define_method method do |*args|
          ActiveRecord::Base.connection_pool.with_connection do
            old.bind(self).call(*args)
          end
        end
        defer(method) if deferrable

        # And define EM-blocking method with bang! name
        if deferrable
          define_method "#{method}!" do |*args|
            ActiveRecord::Base.connection_pool.with_connection do
              old.bind(self).call(*args)
            end
          end
        end
      end

      %w[adapter host port database username password pool].each do |name|
        define_method(name) do |*args|
          if args.first
            @config[name.to_sym] = args.first
          else
            @config[name.to_sym]
          end
        end
      end

      def initialize(&block)
        @config = {}
        instance_eval(&block)
        required = [:adapter, :database]
        required << [:host, :port] unless @config[:adapter] == 'sqlite3'
        required.flatten.each {|key| raise "Must provide #{key}" unless @config[key] }
        [:username, :password].each {|key| @config.delete(key) if empty?(@config[key]) }
        establish_connection
      end

      def user_exists?(jid)
        jid = jidify(jid)
        return false if jid.empty?

        Sql::User.where(jid: jid).exists?
      end
      with_connection :user_exists?

      def find_user(jid)
        jid = jidify(jid)
        return if jid.empty?

        xuser = user_by_jid(jid)
        return Vines::User.new(jid: jid).tap do |user|
          user.name, user.password = xuser.name, xuser.password
          xuser.contacts.each do |contact|
            groups = contact.groups.map {|group| group.name }
            user.roster << Vines::Contact.new(
              jid: contact.jid,
              name: contact.name,
              subscription: contact.subscription,
              ask: contact.ask,
              groups: groups)
          end
        end if xuser
      end
      with_connection :find_user

      def save_user(user)
        xuser = user_by_jid(user.jid) || Sql::User.new(jid: user.jid.bare.to_s)
        xuser.name = user.name
        xuser.password = user.password

        # remove deleted contacts from roster
        xuser.contacts.delete(xuser.contacts.select do |contact|
          !user.contact?(contact.jid)
        end)

        # update contacts
        xuser.contacts.each do |contact|
          fresh = user.contact(contact.jid)
          contact.update_attributes(
            name: fresh.name,
            ask: fresh.ask,
            subscription: fresh.subscription,
            groups: groups(fresh))
        end

        # add new contacts to roster
        jids = xuser.contacts.map {|c| c.jid }
        user.roster.select {|contact| !jids.include?(contact.jid.bare.to_s) }
          .each do |contact|
            xuser.contacts.build(
              user: xuser,
              jid: contact.jid.bare.to_s,
              name: contact.name,
              ask: contact.ask,
              subscription: contact.subscription,
              groups: groups(contact))
          end
        xuser.save
      end
      with_connection :save_user

      def find_vcard(jid)
        jid = jidify(jid)
        return if jid.empty?
        if xuser = user_by_jid(jid)
          Nokogiri::XML(xuser.vcard).root rescue nil
        end
      end
      with_connection :find_vcard

      def save_vcard(jid, card)
        xuser = user_by_jid(jid)
        if xuser
          xuser.vcard = card.to_xml
          xuser.save
        end
      end
      with_connection :save_vcard

      def find_fragment(jid, node)
        jid = jidify(jid)
        return if jid.empty?
        if fragment = fragment_by_jid(jid, node)
          Nokogiri::XML(fragment.xml).root rescue nil
        end
      end
      with_connection :find_fragment

      def save_fragment(jid, node)
        jid = jidify(jid)
        fragment = fragment_by_jid(jid, node) ||
          Sql::Fragment.new(
            user: user_by_jid(jid),
            root: node.name,
            namespace: node.namespace.href)
        fragment.xml = node.to_xml
        fragment.save
      end
      with_connection :save_fragment

      def save_message(message)
        from = message.from.bare.to_s
        with = message.to.bare.to_s

        hash = Digest::SHA1.hexdigest([from, with].sort * '|')

        collection = Sql::Collection.where(jids_hash: hash).first_or_create(
          jid_from: from,
          jid_with: with,
          created_at: Time.now.utc
        )

        collection.messages.create(
          jid: from,
          body: message.css('body').inner_text,
          created_at: Time.now.utc
        )
      end
      with_connection :save_message

      def find_collections(jid, options)
        jid = jidify(jid)

        if options[:with].nil?
          with_jid = Sql::Collection.arel_table[:jid_with].eq(jid)
          from_jid = Sql::Collection.arel_table[:jid_from].eq(jid)

          condition = with_jid.or(from_jid)
        else
          with = JID.new(options[:with]).bare.to_s
          hash = Digest::SHA1.hexdigest([jid, with].sort * '|')

          condition = Sql::Collection.arel_table[:jids_hash].eq(hash)
        end

        unless options[:start].nil?
          start = Sql::Collection.arel_table[:created_at].gteq(options[:start].utc)
          condition = condition.and(time_condition)
        end

        unless options[:end].nil?
          finish = Sql::Collection.arel_table[:created_at].lteq(options[:end].utc)
          condition = condition.and(finish)
        end

        [
          Sql::Collection.where(condition).order(:created_at).limit(options[:rsm].max).all,
          Sql::Collection.where(condition).count
        ]
      end
      with_connection :find_collections

      def find_messages(jid, with, options)
        jid   = jidify(jid)
        with  = jidify(with)

        hash = Digest::SHA1.hexdigest([jid, with].sort * '|')
        jids_condition = Sql::Collection.arel_table[:jids_hash].eq(hash)
        time_condition = Sql::Message.arel_table[:created_at].gteq(options[:start].utc)

        unless options[:end].nil?
          finish = Sql::Message.arel_table[:created_at].lteq(options[:end].utc)
          time_condition = time_condition.and(finish)
        end

        [
          Sql::Message.where(jids_condition)
                      .where(time_condition).joins(:collection).order(:created_at)
                      .limit(options[:rsm].max).all,
          Sql::Message.where(jids_condition)
                      .where(time_condition).joins(:collection).count
        ]
      end
      with_connection :find_messages

      def save_pending_stanza(jid, node)
        user = Sql::User.where(jid: jidify(jid)).first
        return if user.nil? || user.pending_stanzas.count >= MAX_PENDING_STANZAS_PER_USER

        Sql::PendingStanza.create(user: user, xml: node.to_xml)
      end
      with_connection :save_pending_stanza

      # TODO : ADD automatic bang method generation
      def find_pending_stanzas(jid, limit = PENDING_STANZAS_BATCH_SIZE)
        user = Sql::User.where(jid: jidify(jid)).first
        return [] if user.nil?

        user.pending_stanzas.order(:created_at).limit(limit).all
      end
      with_connection :find_pending_stanzas

      def delete_pending_stanzas(jid_or_ids)
        if jid_or_ids.is_a?(Array)
          Sql::PendingStanza.where(id: jid_or_ids).delete_all
        else
          user = Sql::User.where(jid: jidify(jid)).first
          return if user.nil?

          user.pending_stanzas.delete_all
        end
      end
      with_connection :delete_pending_stanzas

      

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
            t.string :jid,            limit: 256, null: false
            t.text :body,             null: false
            t.datetime :created_at,   null: false
          end
          add_index :messages, [:collection_id, :jid]
          add_index :messages, :created_at

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
      with_connection :create_schema, defer: false

      def migrate
        ActiveRecord::Migrator.migrate(migrations_path, ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
      end
      with_connection :migrate, defer: false

      private
      def migrations_path
        File.expand_path(File.join('..', 'db', 'migrations'), __FILE__)
      end

      def establish_connection
        ActiveRecord::Base.logger = Logger.new('/dev/null')
        ActiveRecord::Base.establish_connection(@config)
        # has_and_belongs_to_many requires a connection so configure the
        # associations here rather than in the class definitions above.
        Sql::Contact.has_and_belongs_to_many :groups
        Sql::Group.has_and_belongs_to_many :contacts
      end

      def user_by_jid(jid)
        Sql::User.where(jid: jidify(jid)).includes(:contacts => :groups).first
      end

      def jidify(jid)
        jid.is_a?(JID) ? jid.bare.to_s : JID.new(jid).bare.to_s
      end

      def fragment_by_jid(jid, node)
        jid = jidify(jid)
        clause = 'user_id=(select id from users where jid=?) and root=? and namespace=?'
        Sql::Fragment.where(clause, jid, node.name, node.namespace.href).first
      end

      def groups(contact)
        contact.groups.map {|name| Sql::Group.find_or_create_by_name(name.strip) }
      end
    end
  end
end

# TODO : Split file
