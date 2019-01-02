# frozen_string_literal: true

require 'sequel'

DATABASE = Sequel.connect(ENV.fetch('DATABASE_URL'))

Sequel::Model.plugin :update_or_create

Dir[File.join(__dir__, 'models', '*.rb')].each { |file| require file }
