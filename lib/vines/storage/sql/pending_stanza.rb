# coding: utf-8

module Vines
  class Storage
    class Sql

      MAX_PENDING_STANZAS_PER_USER = 1000
      PENDING_STANZAS_BATCH_SIZE   = 50

      def save_pending_stanza(jid, node)
        user = Sql::User.where(jid: jidify(jid)).first
        return if user.nil? || user.pending_stanzas.count >= MAX_PENDING_STANZAS_PER_USER

        Sql::PendingStanza.create(user: user, xml: node.to_xml)
      end

      def find_pending_stanzas(jid, limit = PENDING_STANZAS_BATCH_SIZE)
        user = Sql::User.where(jid: jidify(jid)).first
        return [] if user.nil?

        user.pending_stanzas.order(:created_at).limit(limit).all
      end

      def delete_pending_stanzas(jid_or_ids)
        if jid_or_ids.is_a?(Array)
          Sql::PendingStanza.where(id: jid_or_ids).delete_all
        else
          user = Sql::User.where(jid: jidify(jid)).first
          return if user.nil?

          user.pending_stanzas.delete_all
        end
      end

      with_connection :save_pending_stanza
      with_connection :find_pending_stanzas
      with_connection :delete_pending_stanzas

    end # class Sql
  end # class Storage
end # module Vines
