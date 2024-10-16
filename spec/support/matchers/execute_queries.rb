# frozen_string_literal: true

class MatchExecutedQueries < RSpec::Matchers::BuiltIn::Match
  def initialize(expected)
    expected = expected.map do |query|
      if query.is_a?(String)
        RSpec::Matchers::BuiltIn::Include.new(query)
      else
        query
      end
    end
    super
  end

  def matches?(event_proc)
    @actual = []
    callback = ->(event) { @actual << event.payload[:sql] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &event_proc)

    match(expected, @actual)
  end

  def supports_block_expectations?
    true
  end

  def supports_value_expectations?
    false
  end
end

module RSpec
  module Matchers
    def execute_queries(*query_matchers)
      raise 'Use execute_no_queries to assert no query is executed' if query_matchers.empty?

      MatchExecutedQueries.new(query_matchers)
    end

    def execute_no_queries
      MatchExecutedQueries.new([])
    end
  end
end
