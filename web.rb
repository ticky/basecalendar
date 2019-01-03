# frozen_string_literal: true

require 'date'
require 'dotenv/load'
require 'faraday'
require 'faraday_middleware'
require 'faraday-http-cache'
require 'http_link_header'
require 'icalendar'
require 'icalendar/tzinfo'
require 'msgpack'
require 'premailer/html_to_plain_text'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'omniauth-oauth2'
require 'omniauth-bcx'
require 'securerandom'
require 'tzinfo'

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

def faraday_for(token:)
  Faraday.new do |faraday|
    faraday.request :json
    faraday.response :json
    faraday.headers['User-Agent'] = 'Basecalendar/1.0 (jessstokes@fastmail.com)'
    faraday.use :http_cache
    faraday.adapter Faraday.default_adapter
    faraday.authorization :Bearer, token
  end
end

get '/' do
  if session[:user_id] &&
     (@user = User.find(id: session[:user_id])) &&
     (token = Token.order(:expires_at)
                   .where { expires_at > Time.now }
                   .last(user_id: @user.id))

    basecamp = faraday_for(token: token.token)

    @authorization = basecamp.get('https://launchpad.37signals.com/authorization.json')

    @account_calendars = []

    @authorization.body.dig('accounts').each do |account|
      projects_url = "#{account['href']}/projects.json" # ugh
      collated_projects = []

      loop do
        projects = basecamp.get(projects_url)

        # Only grab projects with "schedule" (calendar) activated
        collated_projects.concat(projects.body.select do |project|
          project['dock'].any? do |dock_item|
            dock_item['enabled'] && dock_item['name'] == 'schedule'
          end
        end)

        break if projects.headers['link'].nil?

        projects_url = HttpLinkHeader.new(projects.headers['link']).rel('next')

        break if projects_url.nil?
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

  Token.update_or_create(user_id: user.id) do |new_token|
    new_token.token = auth.credentials.token
    new_token.refresh_token = auth.credentials.refresh_token
    new_token.expires_at = Time.at(auth.credentials.expires_at)
  end

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
  # TODO: Generate calendar from config & tokens
  # TODO: Refresh access token if needed

  if (@user = User.find(access_token: params[:token])) &&
     (token = Token.order(:expires_at)
                   .where { expires_at > Time.now }
                   .last(user_id: @user.id)) &&
     (config = MessagePack.unpack Base64.decode64(params[:config]))

    basecamp = faraday_for(token: token.token)
    calendar = Icalendar::Calendar.new do |cal|
      cal.name = 'Basecamp Calendar'
      cal.organization = 'Basecamp'
    end

    @authorization = basecamp.get('https://launchpad.37signals.com/authorization.json')

    @authorization.body.dig('accounts').each do |account|
      break unless config.key? account['id'].to_s

      account_config = config[account['id'].to_s]

      user_profile = basecamp.get("#{account['href']}/my/profile.json")
      projects_url = "#{account['href']}/projects.json" # ugh
      collated_projects = []

      loop do
        projects = basecamp.get(projects_url)

        # Only grab projects we've requested and with "schedule" (calendar) activated
        collated_projects.concat(projects.body.select do |project|
          (
            account_config.key?('my') ||
            account_config.key?(project['id'].to_s)
          ) &&
          project['dock'].any? do |dock_item|
            dock_item['enabled'] && dock_item['name'] == 'schedule'
          end
        end)

        break if projects.headers['link'].nil?

        projects_url = HttpLinkHeader.new(projects.headers['link']).rel('next')

        break if projects_url.nil?
      end

      collated_projects.map do |project|
        schedule = project['dock'].find do |dock_item|
          dock_item['enabled'] && dock_item['name'] == 'schedule'
        end

        schedule_data = basecamp.get(schedule['url'])

        next unless schedule_data.body['entries_count'].positive?

        entries_url = schedule_data.body['entries_url']

        collated_entries = []

        loop do
          entries = basecamp.get(entries_url)

          entries.body.each do |entry|
            dtstart, dtend = if entry['all_day'] == true
                               [
                                 Icalendar::Values::Date.new(
                                   Date.iso8601(entry['starts_at'])
                                       .strftime(Icalendar::Values::Date::FORMAT)
                                 ),
                                 Icalendar::Values::Date.new(
                                   Date.iso8601(entry['ends_at'])
                                       .strftime(Icalendar::Values::Date::FORMAT)
                                 )
                               ]
                             else
                               utc_tzid = 'Etc/UTC'
                               start_time = DateTime.iso8601(entry['starts_at'])

                               unless calendar.timezones.any? { |tz| tz.tzid == utc_tzid }
                                 utc = TZInfo::Timezone.get utc_tzid
                                 timezone = utc.ical_timezone start_time
                                 calendar.add_timezone timezone
                               end

                               [
                                 Icalendar::Values::DateTime.new(
                                   start_time.strftime(Icalendar::Values::DateTime::FORMAT),
                                   tzid: utc_tzid
                                 ),
                                 Icalendar::Values::DateTime.new(
                                   DateTime.iso8601(entry['ends_at'])
                                           .strftime(Icalendar::Values::DateTime::FORMAT),
                                   tzid: utc_tzid
                                 )
                               ]
                             end

            calendar.event do |event|
              event.uid = entry['id'].to_s
              event.summary = entry['title']
              extend HtmlToPlainText
              event.description = convert_to_text(entry['description'],
                                                  Float::INFINITY)
              event.dtstart = dtstart
              event.dtend = dtend
              event.url = entry['app_url']
            end
          end

          collated_entries.concat(entries.body)

          break if entries.headers['link'].nil?

          entries_url = HttpLinkHeader.new(entries.headers['link']).rel('next')

          break if entries_url.nil?
        end

        schedule['collated_entries'] = collated_entries
      end

      # @account_calendars << [account, user_profile.body, collated_projects]
    end

    [200, { 'Content-Type' => 'text/calendar' }, calendar.to_ical]
  else
    return status 403
  end
end

not_found do
  erb :'error/404'
end
