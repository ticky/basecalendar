# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:users) do
      primary_key :id
      String :'37signals_id', null: false, index: true, unique: true
      String :access_token, null: false, index: true, unique: true
    end

    create_table(:tokens) do
      primary_key :id
      foreign_key :user_id, :users
      String :token, null: false
      String :refresh_token, null: false
      DateTime :expires_at, null: false
    end
  end
end
