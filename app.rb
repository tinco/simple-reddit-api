require 'bundler/setup'
require 'sinatra'
require 'redd/middleware'
require 'fileutils'
require 'json'
require 'pry'

FileUtils.mkdir_p 'tmp'
SESSION_FILE = "tmp/reddit_session"

def get_env(name)
  ENV[name] || raise("Environment variable #{name} not set.")
end

class PersistRedditSession
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    unless request.session[:redd_session] 
      begin
        request.session[:redd_session] = JSON.parse(File.read(SESSION_FILE), symbolize_names: true)
      rescue => e
        puts "Could not load reddit session file: #{e.message}"
      end
    end

    result = @app.call(env)

    if env['redd.session']
      File.open(SESSION_FILE, 'w') do |f|
	f.write(JSON.dump(request.session[:redd_session]))
      end
    end   
 
    result
  end
end

use Rack::Session::Cookie
use PersistRedditSession
use Redd::Middleware,
    user_agent:   'Generic Redd Client (by u/tinco)',
    client_id:    get_env('REDDIT_CLIENT_ID'),
    secret:       get_env('REDDIT_SECRET'),
    redirect_uri: get_env('REDDIT_REDIRECT_URI'),
    scope:        %w(identity read),
    via:          '/auth/reddit'

helpers do
  def reddit
    request.env['redd.session']
  end
end

get '/' do
  if reddit
    "Hello /u/#{reddit.me.name}! <a href='/logout'>Logout</a>"
  else
    "<a href='/auth/reddit'>Sign in with reddit</a>"
  end
end

get '/auth/reddit/callback' do
  redirect to('/') unless request.env['redd.error']
  "Error: #{request.env['redd.error'].message} (<a href='/'>Back</a>)"
end

get '/r/:subreddit/new' do
  opts = {}
  opts[:count] = params[:count].to_i if params[:count]
  opts[:after] = params[:after].to_s if params[:after]
  opts[:limit] = params[:limit].to_s if params[:limit]
  subreddit = params[:subreddit].to_s
  response = reddit.subreddit(params[:subreddit]).new(opts)
  response.map do |r|
    {
      title: r.title,
      subreddit: r.subreddit_name_prefixed,
#      preview: r.preview,
      permalink: r.permalink,
      url: r.url,
      created: r.created,
      fullname: r.name,
      downvotes: r.downs,
      upvotes: r.ups,
      score: r.score,
      gildings: r.gildings,
      over_18: r.over_18
    }.to_json
  end
end

get '/logout' do
  request.env['redd.session'] = nil
  redirect to('/')
end
