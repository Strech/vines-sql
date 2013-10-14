# coding: utf-8

module Vines
  class Storage
    class Sql

      def user_exists?(jid)
        jid = stringify_jid(jid)
        return false if jid.empty?

        Sql::User.where(jid: jid).exists?
      end

      def find_user(jid)
        jid = stringify_jid(jid)
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

      with_connection :user_exists?
      with_connection :find_user
      with_connection :save_user

      private
      def user_by_jid(jid)
        Sql::User.where(jid: stringify_jid(jid)).includes(contacts: :groups).first
      end

      def groups(contact)
        contact.groups.map {|name| Sql::Group.find_or_create_by_name(name.strip) }
      end

    end # class Sql
  end # class Storage
end # module Vines
