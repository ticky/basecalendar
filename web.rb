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
  erb :index
end

get '/auth/:provider/callback' do
  auth = request.env['omniauth.auth']

  pp auth
end

get '/auth/failure' do
  erb :auth_failure
end

get '/calendar/:uuid/:config' do
end
