# frozen_string_literal: true

require 'sequel'

DATABASE = Sequel.connect(ENV.fetch('DATABASE_URL'))

Dir[File.join(__dir__, 'models', '*.rb')].each { |file| require file }
