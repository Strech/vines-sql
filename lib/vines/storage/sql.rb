$LOAD_PATH.unshift File.expand_path('../sql', __FILE__)

require 'active_record'

module Vines
  class Storage
    class Sql < Storage
      register :sql

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

      RenewedMessage = Struct.new(:from, :to, :body)

      # Wrap the method with ActiveRecord connection pool logic, so we properly
      # return connections to the pool when we're finished with them. This also
      # defers the original method by pushing it onto the EM thread pool because
      # ActiveRecord uses blocking IO.
      def self.with_connection(method, args={})
        deferrable = args.key?(:defer) ? args[:defer] : true
        old = instance_method(method)

        # Define EM-safe method
        define_method method do |*args, &block|
          ActiveRecord::Base.connection_pool.with_connection do
            old.bind(self).call(*args, &block)
          end
        end
        defer(method) if deferrable

        # And define EM-blocking method with bang! name
        if deferrable
          define_method "#{method}!" do |*args, &block|
            ActiveRecord::Base.connection_pool.with_connection do
              old.bind(self).call(*args, &block)
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
        @config = Hash.new
        instance_eval(&block)
        required = [:adapter, :database]
        required << [:host, :port] unless @config[:adapter] == 'sqlite3'
        required.flatten.each { |key| raise "Must provide #{key}" unless @config[key] }
        [:username, :password].each { |key| @config.delete(key) if empty?(@config[key]) }
        establish_connection
      end

      private
      def establish_connection
        ActiveRecord::Base.logger = Logger.new('/dev/null')
        ActiveRecord::Base.establish_connection(@config)
        # has_and_belongs_to_many requires a connection so configure the
        # associations here rather than in the class definitions above.
        Sql::Contact.has_and_belongs_to_many :groups
        Sql::Group.has_and_belongs_to_many :contacts
      end

      def stringify_jid(jid)
        jid.is_a?(JID) ? jid.bare.to_s : JID.new(jid).bare.to_s
      end

    end
  end
end

%w[
  user
  message
  pending_stanza
  vcard
  fragment
  schema
].each { |file| require file }
