# frozen_string_literal: true
#
# Copyright Andreas Alin <andreas.alin@gmail.com>
# License: AGPL-3.0

require "async/clock"
require_relative "session"

module VDOM
  class Server
    class SessionStore
      class SessionNotFoundError < StandardError
      end

      TIMEOUT_SECONDS = 10

      def initialize
        @sessions = {}
      end

      def authenticate(id, token)
        session = @sessions.fetch(id) { raise SessionNotFound }
        Session::Token.equal?(session.token, token) && session
      end

      def store(session) = @sessions.store(session.id, session)

      def stop! = @sessions.each_value(&:stop)

      def clear_stale
        @sessions.delete_if do |session|
          if Async::Clock.now - session.last_update > TIMEOUT_SECONDS
            session.stop
            true
          end
        end
      end
    end
  end
end
