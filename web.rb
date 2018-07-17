# frozen_string_literal: true

require 'dotenv/load'
require 'faraday'
require 'faraday_middleware'
require 'http_link_header'
require 'msgpack'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'omniauth-oauth2'
require 'omniauth-bcx'
require 'securerandom'

require './database'

PROJECT_PURPOSE_ORDER = {
  'company_hq' => '10',
  'team' => '20',
  'topic' => '30'
}.freeze

use Rack::Session::Cookie, secret: ENV.fetch('SESSION_COOKIE_SECRET')
use OmniAuth::Builder do
  provider :basecamp,
           ENV.fetch('BASECAMP_CLIENT_ID'),
           ENV.fetch('BASECAMP_CLIENT_SECRET')
end

set :erb, layout: :layout

def faraday_for(url:, token:)
  Faraday.new(url: url) do |faraday|
    faraday.request :json
    faraday.response :json
    faraday.headers['User-Agent'] = 'Basecalendar/1.0 (jessstokes@fastmail.com)'
    faraday.adapter Faraday.default_adapter
    faraday.authorization :Bearer, token
  end
end

get '/' do
  if session[:user_id]
    @user = User.find(id: session[:user_id])
    token = Token.find(user_id: @user.id)

    @authorization = faraday_for(url: 'https://launchpad.37signals.com',
                                 token: token.token)
                     .get('authorization.json')

    @account_calendars = []

    @authorization.body.dig('accounts').each do |account|
      basecamp = faraday_for(url: account['href'], token: token.token)
      project_url = 'projects.json'
      collated_projects = []

      loop do
        projects = basecamp.get(project_url)

        # Only grab projects with "schedule" (calendar) activated
        collated_projects.concat(projects.body.select do |project|
          project['dock'].any? do |dock_item|
            dock_item['enabled'] && dock_item['name'] == 'schedule'
          end
        end)

        break if projects.headers['link'].nil?

        project_url = HttpLinkHeader.new(projects.headers['link']).rel('next')

        break if project_url.nil?
      end

      collated_projects.sort_by! do |project|
        [
          PROJECT_PURPOSE_ORDER[project['purpose']],
          project['bookmarked'] ? '0' : '1',
          project['name']
        ].join ' '
      end

      @account_calendars << [account, collated_projects]
    end

    return erb :index_authenticated
  end

  erb :index
end

get '/auth/:provider/callback' do
  auth = request.env['omniauth.auth']

  user = User.find_or_create('37signals_id': auth.uid.to_s) do |new_user|
    new_user.access_token = SecureRandom.hex
  end

  Token.find_or_create(user_id: user.id) do |new_token|
    new_token.token = auth.credentials.token
    new_token.refresh_token = auth.credentials.refresh_token
    new_token.expires_at = Time.at(auth.credentials.expires_at)
  end

  # TODO: Check for needing refresh token - are these tokens always "fresh" at this point?

  session[:user_id] = user.id

  redirect to('/')
end

get '/auth/failure' do
  session[:user_id] = nil

  erb :auth_failure
end

get '/sign-out' do
  session[:user_id] = nil

  redirect to('/')
end

get '/calendar/:token/:config.ics' do
  user = User.find(access_token: params[:token])
  config = MessagePack.unpack Base64.decode64(params[:config])

  # TODO: Generate calendar from config & tokens
  # TODO: Refresh access token if needed
end

not_found do
  erb :'error/404'
end
