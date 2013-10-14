# coding: utf-8

module Vines
  class Storage
    class Sql

      def find_vcard(jid)
        jid = jidify(jid)
        return if jid.empty?
        if xuser = user_by_jid(jid)
          Nokogiri::XML(xuser.vcard).root rescue nil
        end
      end

      def save_vcard(jid, card)
        xuser = user_by_jid(jid)
        if xuser
          xuser.vcard = card.to_xml
          xuser.save
        end
      end

      with_connection :find_vcard
      with_connection :save_vcard

    end # class Sql
  end # class Storage
end # module Vines
