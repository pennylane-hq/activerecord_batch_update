# frozen_string_literal: true

class Cat < ActiveRecord::Base
  encrypts :bitcoin_address
end

class Dog < ActiveRecord::Base
end
