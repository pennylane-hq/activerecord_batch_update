# frozen_string_literal: true

require 'activerecord_batch_update'

describe ActiveRecordBatchUpdate do # rubocop:disable RSpec/SpecFilePathFormat
  describe '#batch_update_statements' do
    subject(:sql_queries) { Cat.batch_update_statements(cats, **kwargs) }

    let(:cats) { [] }
    let(:kwargs) { {} }

    context 'when all object keys are the same' do
      let(:cats) do
        [
          { id: 1, name: 'foo' },
          { id: 2, name: 'bar' }
        ]
      end

      it 'creates a single query' do
        query = <<~SQL.squish
          WITH "batch_updates" (id, name) AS (
            VALUES (CAST(1 AS INTEGER), CAST('foo' AS varchar)), (2, 'bar')
          )
          UPDATE "cats"
          SET
            "name" = "batch_updates"."name"
          FROM "batch_updates"
          WHERE
            "cats"."id" = "batch_updates"."id"
        SQL

        expect(sql_queries).to contain_exactly(query)
      end
    end

    context 'when objects have different keys' do
      let(:cats) do
        [
          { id: 1, name: 'foo' },
          { id: 2, name: 'bar', birthday: Date.new(2010, 1, 1) }
        ]
      end

      it 'creates multiple queries' do
        query1 = <<~SQL.squish
          WITH "batch_updates" (id, name) AS (
            VALUES (CAST(1 AS INTEGER), CAST('foo' AS varchar))
          )
          UPDATE "cats"
          SET
            "name" = "batch_updates"."name"
          FROM "batch_updates"
          WHERE
            "cats"."id" = "batch_updates"."id"
        SQL

        query2 = <<~SQL.squish
          WITH "batch_updates" (birthday, id, name) AS (
            VALUES (CAST('2010-01-01' AS date), CAST(2 AS INTEGER), CAST('bar' AS varchar))
          )
          UPDATE "cats"
          SET
            "birthday" = "batch_updates"."birthday",
            "name" = "batch_updates"."name"
          FROM "batch_updates"
          WHERE
            "cats"."id" = "batch_updates"."id"
        SQL

        expect(sql_queries).to contain_exactly(query1, query2)
      end
    end

    context 'with several update_on columns' do
      let(:kwargs) do
        { update_on: %i[id name] }
      end
      let(:cats) do
        [
          { id: 1, name: 'Felix', birthday: Date.new(2019, 4, 4) }
        ]
      end

      it 'builds the proper queries' do
        query = <<~SQL.squish
          WITH "batch_updates" (birthday, id, name) AS (
            VALUES (CAST('2019-04-04' AS date), CAST(1 AS INTEGER), CAST('Felix' AS varchar))
          )
          UPDATE "cats"
          SET
            "birthday" = "batch_updates"."birthday"
          FROM "batch_updates"
          WHERE
              "cats"."id" = "batch_updates"."id"
          AND "cats"."name" = "batch_updates"."name"
        SQL

        expect(sql_queries).to contain_exactly(query)
      end
    end

    context 'with a custom batch_size' do
      let(:cats) do
        [
          { id: 1, name: 'foo' },
          { id: 2, name: 'bar' }
        ]
      end

      let(:kwargs) do
        { batch_size: 1 }
      end

      it 'batches queries accordingly' do
        query1 = <<~SQL.squish
          WITH "batch_updates" (id, name) AS (
            VALUES (CAST(1 AS INTEGER), CAST('foo' AS varchar))
          )
          UPDATE "cats"
          SET
            "name" = "batch_updates"."name"
          FROM "batch_updates"
          WHERE
            "cats"."id" = "batch_updates"."id"
        SQL

        query2 = <<~SQL.squish
          WITH "batch_updates" (id, name) AS (
            VALUES (CAST(2 AS INTEGER), CAST('bar' AS varchar))
          )
          UPDATE "cats"
          SET
            "name" = "batch_updates"."name"
          FROM "batch_updates"
          WHERE
            "cats"."id" = "batch_updates"."id"
        SQL

        expect(sql_queries).to contain_exactly(query1, query2)
      end
    end
  end

  describe '#batch_update' do
    describe "when the record doesn't exist" do
      let!(:cat) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }

      let!(:non_existing_record) do
        Cat.new(
          id: Cat.maximum(:id) + 1,
          name: 'ghost'
        )
      end

      it 'does not insert a new record' do
        expect do
          Cat.batch_update([non_existing_record], columns: :all)
        end.to execute_queries(/UPDATE/)
          .and not_change(Cat, :count)
          .and(not_change { Cat.exists?(id: non_existing_record.id) })
      end
    end

    describe 'when some fields changed' do
      let!(:cat1) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }
      let!(:cat2) { Cat.create!(name: 'Garfield', birthday: Date.new(2011, 2, 2)) }

      it 'issues the right number of update statements and changes the data' do
        expect do
          cat1.name = 'can I haz cheeseburger pls'
          cat2.name = 'O\'Sullivans cuba libre'
          cat2.birthday = '2024-01-01'
          Cat.batch_update([cat1, cat2], columns: :all)
        end.to execute_queries(
          /WITH "batch_updates" .* AS \( VALUES.* UPDATE "cats" SET "birthday" = "batch_updates"."birthday", "name" = "batch_updates"."name", "updated_at" = "batch_updates"."updated_at" FROM "batch_updates"/,
          /WITH "batch_updates" .* AS \( VALUES.* UPDATE "cats" SET "name" = "batch_updates"."name", "updated_at" = "batch_updates"."updated_at" FROM "batch_updates"/
        ).and change { cat1.reload.name }.to('can I haz cheeseburger pls')
                                         .and change { cat2.reload.name }.to('O\'Sullivans cuba libre')
                                                                         .and(change { cat2.reload.birthday })
      end

      context 'when some fields are encrypted' do
        let!(:cat1) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }

        it 'updates the encrypted fields properly' do
          expect do
            cat1.bitcoin_address = 'abc'

            Cat.batch_update([cat1], columns: %i[bitcoin_address])
          end.to execute_queries(
            /WITH "batch_updates" \(bitcoin_address, id, updated_at\) AS \( VALUES \(CAST\(.* AS varchar\), CAST\(\d* AS INTEGER\), CAST\(.* AS datetime\(6\)\)\) \) UPDATE "cats" SET "bitcoin_address" = "batch_updates"."bitcoin_address", "updated_at" = "batch_updates"."updated_at" FROM "batch_updates" WHERE "cats"."id" = "batch_updates"."id"/
          ).and change { cat1.reload.bitcoin_address }.to('abc')
        end
      end

      context 'when the text has consecutive whitespace' do
        let!(:cat1) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }

        it 'does not remove it' do
          expect do
            cat1.name = 'can   I    haz   cheeseburger    pls'
            Cat.batch_update([cat1], columns: :all)
          end.to change { cat1.reload.name }.to('can   I    haz   cheeseburger    pls')
        end
      end

      context 'when the text has backslashes' do
        let!(:cat1) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }

        it 'does not break the query' do
          expect do
            cat1.name = 'La Rose Blanche \\'
            Cat.batch_update([cat1], columns: :all)
          end.to change { cat1.reload.name }.to('La Rose Blanche \\')
        end
      end
    end

    context 'when the columns kwargs is specified' do
      describe 'when not all changes are included the columns kwarg' do
        let!(:cat1) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }
        let!(:cat2) { Cat.create!(name: 'Garfield', birthday: Date.new(2011, 2, 2)) }

        it 'does not change them' do
          expect do
            cat1.name = 'can I haz cheeseburger pls'
            cat2.name = 'O\'Sullivans cuba libre'
            cat2.birthday = Date.new(2024, 1, 1)
            Cat.batch_update([cat1, cat2], columns: %w[name])
          end.to execute_queries(
            /WITH "batch_updates" .* AS \( VALUES.* UPDATE "cats" SET "name" = "batch_updates"."name", "updated_at" = "batch_updates"."updated_at" FROM "batch_updates"/
          ).and(change { cat1.reload.name }.to('can I haz cheeseburger pls'))
            .and(change { cat2.reload.name }.to('O\'Sullivans cuba libre'))
            .and(not_change { cat2.reload.birthday })
        end
      end

      describe 'when no changes overlap with the columns kwarg' do
        let!(:cat) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }

        it 'does not run any query and make no changes' do
          expect do
            cat.name = 'can I haz cheeseburger pls'
            Cat.batch_update([cat], columns: %w[birthday])
          end.to execute_no_queries
             .and(not_change { cat.reload.name })
            .and(not_change { cat.reload.birthday })
        end
      end
    end

    describe 'when nothing has changed' do
      let!(:cat) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }

      context 'with validate: true' do
        it 'issues no queries' do
          expect { Cat.batch_update([cat], columns: :all, validate: true) }.to execute_no_queries
        end
      end

      context 'with validate: false' do
        it 'issues no queries' do
          expect { Cat.batch_update([cat], columns: :all, validate: false) }.to execute_no_queries
        end
      end
    end

    context 'when the query cache is enabled' do
      let!(:cat1) { Cat.create!(name: 'Felix', birthday: Date.new(2010, 1, 1)) }

      around do |example|
        ActiveRecord::Base.connection.cache do
          example.run
        end
      end

      it 'clears the query cache' do
        before_import_cat = cat1
        before_import_cat.name = 'Yoda'

        Cat.batch_update([before_import_cat], columns: %i[name])

        after_import_cat = Cat.find(before_import_cat.id)
        expect(before_import_cat.name).to eq('Yoda')
        expect(after_import_cat.name).to eq('Yoda')
      end
    end
  end
end
