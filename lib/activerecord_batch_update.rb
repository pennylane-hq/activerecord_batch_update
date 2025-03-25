# frozen_string_literal: true

require 'active_support'

module ActiveRecordBatchUpdate
  extend ::ActiveSupport::Concern

  # Given an array of records with changes,
  # perform the minimal amount of queries to update
  # all the records without including unchanged attributes
  # in the UPDATE statement.
  #
  # Do this without INSERT ... ON DUPLICATE KEY UPDATE
  # which will re-insert the objects if they were deleted in another thread

  module ClassMethods
    def batch_update(entries, columns:, batch_size: 100, validate: true)
      columns = column_names if columns == :all
      columns = (Array.wrap(columns).map(&:to_s) + %w[updated_at]).uniq

      entries = entries.select { columns.intersect?(_1.changed) }
      entries.each { _1.updated_at = Time.current } if has_attribute?('updated_at')
      entries.each(&:validate!) if validate

      primary_keys = Array.wrap(primary_key).map(&:to_s)

      updated_count = batch_update_statements(
        entries.map do |entry|
          (primary_keys + (entry.changed & columns)).to_h { [_1, entry.read_attribute(_1)] }
        end,
        update_on: primary_keys,
        batch_size: batch_size
      ).sum do |sql|
        connection.exec_update(sql)
      end

      connection.clear_query_cache if connection.query_cache_enabled

      updated_count
    end

    def batch_update_statements(entries, update_on: :id, batch_size: 100)
      update_on = Array.wrap(update_on).map(&:to_s)

      entries.map(&:stringify_keys).group_by { _1.keys.sort! }.sort.flat_map do |(keys, items)|
        next [] if keys.empty?

        where_clause = batch_update_where_statement(update_on)
        update_clause = batch_update_statement(keys - update_on)

        items.each_slice(batch_size).map do |slice|
          [
            "WITH \"#{batch_update_table.name}\" (#{keys.join(', ')})",
            "AS ( #{batch_update_values_statement(slice, keys)} )",
            update_clause,
            "FROM \"#{batch_update_table.name}\"",
            "WHERE #{where_clause}"
          ].join(' ')
        end
      end
    end

    private

    def batch_update_table
      @batch_update_table ||= Arel::Table.new('batch_updates')
    end

    def batch_update_values_statement(items, cols)
      first, *rest = items

      rows = [
        batch_update_casted_item(first, cols),
        *rest.map { batch_update_quoted_item(_1, cols) }
      ]

      "VALUES #{rows.map { "(#{_1.map(&:to_sql).join(', ')})" }.join(', ')}"
    end

    def batch_update_casted_item(item, cols)
      cols.map do |col|
        Arel::Nodes::NamedFunction.new(
          'CAST',
          [
            Arel::Nodes.build_quoted(item[col], arel_table[col]).as(columns_hash[col].sql_type_metadata.sql_type)
          ]
        )
      end
    end

    def batch_update_quoted_item(item, cols)
      cols.map do |col|
        Arel::Nodes.build_quoted(item[col], arel_table[col])
      end
    end

    def batch_update_statement(cols)
      Arel::UpdateManager.new(arel_table).tap do |um|
        um.set(
          cols.map do |col|
            [
              arel_table[col],
              batch_update_table[col]
            ]
          end
        )
      end.to_sql
    end

    def batch_update_where_statement(primary_keys)
      primary_keys.map { arel_table[_1].eq(batch_update_table[_1]) }.reduce(:and).to_sql
    end
  end
end

ActiveSupport.on_load(:active_record) do
  include(ActiveRecordBatchUpdate)
end
