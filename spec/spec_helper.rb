# frozen_string_literal: true

require 'active_record'
require 'pathname'

Pathname.new(__dir__).glob('support/**/*.rb').each { |f| require f }

RSpec.configure do |_config|
  ActiveRecord::Encryption.configure(
    primary_key: SecureRandom.alphanumeric(32),
    deterministic_key: SecureRandom.alphanumeric(32),
    key_derivation_salt: SecureRandom.alphanumeric(32)
  )

  ActiveRecord::Base.establish_connection adapter: 'sqlite3',
                                          database: ':memory:',
                                          role: :writing

  ActiveRecord::Schema.define do
    self.verbose = false

    create_table :cats, force: true do |t|
      t.column :name, :string
      t.column :birthday, :date
      t.column :bitcoin_address, :string
      t.column :updated_at, :timestamp
      t.column :created_at, :timestamp
    end
  end
end
