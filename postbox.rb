require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'yaml'

configure do
  set :erb, :escape_html => true
  enable :sessions
  set :session_secret, "secret"
end

helpers do

end

before do

end

# Helper methods

def data_path
  File.expand_path('../data', __FILE__)
end

def encode_email(email)
  email.downcase.gsub(/[\W]/, '_')
end

def valid_email?(email)
  !!email.match(/[\w|\.]{3,}@[a-z]{2,}\.[a-z]{2,}/i)
end

def valid_name?(name)
  name.match(/\w/) && name.size >= 3
end

def valid_user?(email)
  encoded_email = encode_email(email)
  user_path = File.join(data_path, encoded_email)
  File.directory?(user_path)
end

def logged_in?
  session[:token]
end

# Application Routes

get '/' do
  if logged_in?
    redirect '/inbox'
  else
    redirect '/login'
  end
end

get '/inbox' do

end

get '/login' do
  erb :login, layout: :layout
end

post '/login' do
  email = params[:email]

  if valid_email?(email)
    if valid_user?(email)
      session[:token] = true
      redirect '/inbox'
    else
      redirect "/join?email=#{email}"
    end
  else
    session[:error] = "Please enter a valid email address."
    erb :login, layout: :layout
  end
end

get '/join' do
  @email = params[:email]

  redirect '/login' unless @email
  erb :join, layout: :layout
end

post '/join' do
  @email = params[:email]
  @name = params[:name]

  if valid_name?(@name) && valid_email?(@email)
    encoded_email = encode_email(@email)
    new_user_dir = File.join(data_path, encoded_email)
    Dir.mkdir(new_user_dir)
    session[:token] = true
    session[:success] = "Account successfully create!"
    redirect '/inbox'
  else
    session[:error] = "Please enter a valid name."
    erb :join, layout: :layout
  end
end
