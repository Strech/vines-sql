# coding: utf-8
require 'digest/sha1'

module Vines
  class Storage
    class Sql

      RENEWED_MESSAGES_BATCH_SIZE = 50

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

      def find_collections(jid, options)
        jid = stringify_jid(jid)

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

      def find_messages(jid, with, options)
        jid   = stringify_jid(jid)
        with  = stringify_jid(with)

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

      def fetch_renewed!(jid, limit = RENEWED_MESSAGES_BATCH_SIZE, &block)
        jid = stringify_jid(jid)

        jid_from = Sql::Collection.arel_table[:jid_from].eq(jid)
        jid_with = Sql::Collection.arel_table[:jid_with].eq(jid)
        not_self = Sql::Message.arel_table[:jid].not_eq(jid)

        messages = Sql::Message.where(renew_needed: true)
                               .where(jid_from.or jid_with)
                               .where(not_self)
                               .joins(:collection)
                               .includes(:collection)

        messages.find_each(batch_size: limit) do |message|
          from = message.collection.jid_with == jid ? message.collection.jid_from
                                                    : message.collection.jid_with

          block.call RenewedMessage.new(from, jid, message.body)
        end
      end

      # Em-safe & EM-blocking
      with_connection :save_message
      with_connection :find_collections
      with_connection :find_messages

      # Em-blocking only
      with_connection :fetch_renewed!, defer: false

    end # class Sql
  end # class Storage
end # module Vines
