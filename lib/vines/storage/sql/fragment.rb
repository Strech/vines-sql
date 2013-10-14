# coding: utf-8

module Vines
  class Storage
    class Sql

      def find_fragment(jid, node)
        jid = stringify_jid(jid)
        return if jid.empty?
        if fragment = fragment_by_jid(jid, node)
          Nokogiri::XML(fragment.xml).root rescue nil
        end
      end

      def save_fragment(jid, node)
        jid = stringify_jid(jid)
        fragment = fragment_by_jid(jid, node) ||
          Sql::Fragment.new(
            user: user_by_jid(jid),
            root: node.name,
            namespace: node.namespace.href)
        fragment.xml = node.to_xml
        fragment.save
      end

      with_connection :find_fragment
      with_connection :save_fragment

      private
      def fragment_by_jid(jid, node)
        jid = stringify_jid(jid)
        clause = 'user_id=(select id from users where jid=?) and root=? and namespace=?'
        Sql::Fragment.where(clause, jid, node.name, node.namespace.href).first
      end

    end # class Sql
  end # class Storage
end # module Vines
