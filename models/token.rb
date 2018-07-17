# frozen_string_literal: true

class Token < Sequel::Model
  many_to_one :users
end
