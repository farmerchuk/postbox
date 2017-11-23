require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'bcrypt'
require 'yaml'
require 'date'

configure do
  set :erb, :escape_html => true
  enable :sessions
  set :session_secret, "secret"
end

helpers do

end

before do
  @user_name = get_name_by(session[:user]) if logged_in?
end

# Helper methods

def data_path
  File.expand_path('../data', __FILE__)
end

def user_path(user_id)
  File.expand_path("../data/#{user_id}", __FILE__)
end

def user_data_path(user_id)
  user_path(user_id)
end

def user_name_path(user_id)
  path = user_data_path(user_id)
  File.join(path, 'name.yml')
end

def user_contacts_path(user_id)
  path = user_data_path(user_id)
  File.join(path, 'contacts.yml')
end

def user_password_path(user_id)
  path = user_data_path(user_id)
  File.join(path, 'password.yml')
end

def user_messages_path(user_id)
  File.expand_path("../data/#{user_id}/messages", __FILE__)
end

def new_message_file_name(recipient_id, sender_id)
  recipient_id + '-' + sender_id + '-' + DateTime.now(Date::ITALY).strftime('%Y%m%d%H%M%S')
end

def encode_email(email)
  return nil if email.empty?
  email.downcase.gsub(/[\W]/, '_')
end

def valid_email?(email)
  !!email.match(/[\w|\.]{3,}@[a-z]{2,}\.[a-z]{2,}/i)
end

def valid_name?(name)
  name.match(/\w/) && name.size >= 3
end

def valid_user?(email)
  user_id = encode_email(email)
  user_path = File.join(data_path, user_id)
  File.directory?(user_path)
end

def correct_password?(user_id, password)
  password_file_path = user_password_path(user_id)
  password_on_file = File.read(password_file_path)
  bcrypt_password = BCrypt::Password.new(password_on_file)
  bcrypt_password == password
end

def get_user_id_by(email)
  encode_email(email)
end

def get_name_by(user_id)
  user_data_path = user_path(user_id)
  name_data_path = File.join(user_data_path, 'name.yml')
  YAML.load_file(name_data_path)
end

def get_contacts_by(user_id)
  path = user_contacts_path(user_id)
  YAML.load_file(path)
end

def get_messages_by(user_id)
  messages = []
  path = user_messages_path(user_id)
  file_names = Dir.glob(path + '/*')
  file_names.sort_by! { |f| File.birthtime(f) }.reverse!

  file_names.each do |file_path_name|
    file_name = File.basename(file_path_name)
    recipient_id, sender_id = file_name.split('-')

    message = File.read(file_path_name)
    messages << [recipient_id, sender_id, message, file_name]
  end

  return nil if messages.empty?
  messages
end

def existing_contact?(user_id, target_id)
  existing_contacts = get_contacts_by(user_id)
  return false unless existing_contacts
  existing_contacts.has_key?(target_id)
end

def logged_in?
  session[:user]
end

# Application Routes

get '/' do
  if logged_in?
    redirect '/inbox'
  else
    redirect '/login'
  end
end

get '/compose' do
  user_id = session[:user]
  @contacts = get_contacts_by(user_id)
  @reply_to = params[:sender_id] if params[:sender_id]

  messages = get_messages_by(user_id)
  if messages
    @inbox = messages.size
  else
    @inbox = 0
  end

  erb :compose, layout: :layout
end

get '/logout' do
  session[:user] = nil
  session[:success] = 'You successfully logged out.'
  redirect '/login'
end

get '/login' do
  erb :login, layout: :layout
end

post '/login' do
  @email = params[:email]
  password = params[:password]
  bcrypt_password = BCrypt::Password.create(password)
  user_id = encode_email(@email)

  if valid_email?(@email) && !password.empty?
    if valid_user?(@email) && correct_password?(user_id, password)
      session[:user] = user_id
      redirect '/inbox'
    elsif valid_user?(@email)
      session[:error] = 'Incorrect email or password'
      erb :login, layout: :layout
    else
      redirect "/join?email=#{@email}&password=#{bcrypt_password}"
    end
  else
    session[:error] = 'Please enter a valid email address and password.'
    erb :login, layout: :layout
  end
end

get '/join' do
  @email = params[:email]
  @password = params[:password]

  redirect '/login' unless @email && @password
  erb :join, layout: :layout
end

post '/join' do
  @email = params[:email]
  @password = params[:password]
  @name = params[:name]

  if valid_name?(@name) && valid_email?(@email)
    user_id = encode_email(@email)
    new_user_dir = File.join(data_path, user_id)
    Dir.mkdir(new_user_dir)
    Dir.mkdir(new_user_dir + "/messages")
    name_file = user_name_path(user_id)
    contacts_file = user_contacts_path(user_id)
    password_file = user_password_path(user_id)
    File.write(name_file, @name)
    File.write(password_file, @password)
    File.write(contacts_file, '')

    session[:user] = user_id
    session[:success] = 'Account successfully created!'
    redirect '/compose'
  else
    session[:error] = 'Please enter a valid name.'
    erb :join, layout: :layout
  end
end

get '/search' do
  @user_id = session[:user]
  @contacts = get_contacts_by(@user_id)
  target_email = params[:email]
  target_user_id = get_user_id_by(target_email)

  if target_user_id.nil?
    session[:error] = "Search field cannot be blank."
    erb :compose, layout: :layout
  elsif target_user_id == session[:user]
    session[:error] = "You can't add yourself, smarty."
    erb :compose, layout: :layout
  elsif existing_contact?(@user_id, target_user_id)
    session[:error] = "That person is already a contact."
    erb :compose, layout: :layout
  elsif valid_user?(target_email)
    target_name = get_name_by(target_user_id)
    contacts_path = user_contacts_path(@user_id)

    File.open(contacts_path, 'a') do |f|
      f.puts "#{target_user_id}: #{target_name}"
    end

    session[:success] = "#{target_name} added to contacts!"
    redirect '/compose'
  else
    session[:error] = 'Sorry, could not find that person.'
    erb :compose, layout: :layout
  end
end

post '/compose' do
  recipients = params.select { |param, _| param.include?('user') }.values

  if !recipients.empty?
    sender_id = session[:user]
    message = params[:message]

    recipients.each do |recipient_id|
      recipient_messages_path = user_messages_path(recipient_id)
      recipient_messages_file_path = File.join(recipient_messages_path, new_message_file_name(recipient_id, sender_id))
      recipient_file = recipient_messages_file_path + '.txt'
      File.write(recipient_file, message)

      sender_messages_path = user_messages_path(sender_id)
      sender_messages_file_path = File.join(sender_messages_path, new_message_file_name(recipient_id, sender_id))
      sender_file = sender_messages_file_path + '.txt'
      File.write(sender_file, message)
    end

    session[:success] = 'Message delivered!'
    redirect '/compose'
  else
    @user_id = session[:user]
    @contacts = get_contacts_by(@user_id)
    session[:error] = 'Please select at least one receipient.'
    erb :compose, layout: :layout
  end
end

get '/inbox' do
  @user_id = session[:user]
  @messages = get_messages_by(@user_id)
  erb :inbox, layout: :layout
end

post '/delete' do
  @user_id = session[:user]
  file_name = params[:file_name]
  messages_path = user_messages_path(@user_id)
  file_path = File.join(messages_path, file_name)

  if File.exist?(file_path)
    File.delete(file_path)
    session[:success] = 'Message deleted.'
    redirect '/inbox'
  else
    session[:error] = 'Oops, something went wrong.'
    erb :inbox, layout: :layout
  end
end
