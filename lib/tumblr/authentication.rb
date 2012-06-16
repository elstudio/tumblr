require 'sinatra/base'
require 'weary/request'
require 'weary/middleware'

module Tumblr
  # http://www.tumblr.com/oauth/apps
  class Authentication < Sinatra::Base
    HOST = "http://www.tumblr.com/oauth"

    enable :sessions

    def request_token(key, secret, callback)
      Weary::Request.new "#{HOST}/request_token", :POST do |req|
        req.params :oauth_callback => callback
        req.use Weary::Middleware::OAuth, :consumer_key => key,
                                          :consumer_secret => secret
      end
    end

    def access_token(token, token_secret, verifier, consumer_key, consumer_secret)
      Weary::Request.new "#{HOST}/access_token", :POST do |req|
        req.use Weary::Middleware::OAuth, :token => token,
                                          :token_secret => token_secret,
                                          :verifier => verifier,
                                          :consumer_key => consumer_key,
                                          :consumer_secret => consumer_secret
      end
    end

    get "/" do
      halt 400, "OAuth consumer key and consumer secret required." unless params["key"] && params["secret"]
      session[:consumer_key] = params["key"]
      session[:consumer_secret] = params["secret"]
      response = request_token(session[:consumer_key], session[:consumer_secret], url("/auth")).perform
      if response.success?
        result = Rack::Utils.parse_query(response.body)
        logger.info(request.host)
        session[:request_token_secret] = result["oauth_token_secret"]
        redirect to("#{HOST}/authorize?oauth_token=#{result['oauth_token']}")
      else
        status response.status
        body response.body
      end
    end

    get "/auth" do
      halt 401, "The user denied access." if params.empty?
      token = params["oauth_token"]
      verifier = params["oauth_verifier"]
      response = access_token(token, session[:request_token_secret], verifier,
        session[:consumer_key], session[:consumer_secret]).perform
      if response.success?
        require 'tumblr/credentials'
        result = Rack::Utils.parse_query(response.body)
        Tumblr::Credentials.new.write(session[:consumer_key], session[:consumer_secret], result["oauth_token"], result["oauth_token_secret"])
        status response.status
        body result.inspect
      else
        status response.status
        body response.body
      end
    end
  end
end