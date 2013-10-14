# coding: utf-8
require 'digest/sha1'

module Vines
  class Storage
    class Sql

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

      with_connection :save_message
      with_connection :find_collections
      with_connection :find_messages

    end # class Sql
  end # class Storage
end # module Vines
