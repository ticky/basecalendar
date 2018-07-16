# frozen_string_literal: true

require 'dotenv/load'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'omniauth-oauth2'
require 'omniauth-bcx'

use Rack::Session::Cookie, secret: ENV['SESSION_COOKIE_SECRET']
use OmniAuth::Builder do
  provider :basecamp,
           ENV['BASECAMP_CLIENT_ID'],
           ENV['BASECAMP_CLIENT_SECRET']
end

get '/' do
  # TODO: If logged in, show calendar selection
  erb :index
end

get '/auth/:provider/callback' do
  auth = request.env['omniauth.auth']

  # TODO: Look up user in DB, if not extant, create them and store our token
  # TODO: Set user in session, redirect to calendar configuration page (homepage when logged in)

  erb :auth_success
end

get '/auth/failure' do
  erb :auth_failure
end

get '/calendar/:token/:config.ics' do
  # TODO: Look up user by token, config encodes list of calendar IDs to merge
  # TODO: Messagepack?
end

not_found do
  erb :'error/404'
end
