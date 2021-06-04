require "./lib/wikiscraper.cr"

require "kemal"
require "redis"


# Cache

CACHE_TTL = 60 * 60  # in seconds

cache = nil
env_var = nil
if ENV.has_key?("REDIS_URL")
  env_var = "REDIS_URL"
elsif ENV.has_key?("FLY_REDIS_CACHE_URL")
  env_var = "FLY_REDIS_CACHE_URL"
end
if env_var
  cache = Redis::PooledClient.new(
    url: ENV[env_var],
    database: 0,
    command_timeout: 1.seconds,
    connect_timeout: 1.seconds,
    pool_size: 19,
    pool_timeout: 1.0,
  )
end


# CORS

options "/*" do |env|
  env.response.headers["Allow"] = "HEAD,GET,PUT,POST,DELETE,OPTIONS"
  env.response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept"
  env.response.headers["Access-Control-Allow-Origin"] = "*"

  halt env, status_code: 200
end

before_get "/" do |env|
  env.response.headers["Access-Control-Allow-Origin"] = "*"
  env.response.content_type = "application/json"
end

before_post "/" do |env|
  env.response.headers["Access-Control-Allow-Origin"] = "*"
  env.response.content_type = "application/json"
end


# Routes

get "/" do |env|
  # Get parameters.
  if env.params.query.size != 0
    url, type = get_query_parameters(env.params.query)
  end

  # Get article contents.
  if url
    article_contents = get_article_contents_cache(
      url: url, type: type, cache: cache)
  end

  # Error handling
  if !article_contents
    error_message = "A valid Wikipedia url must be passed."
  elsif article_contents.is_a?(String)
    error_message = article_contents
  end

  if error_message
    next {
      "error": {"message": error_message,},
    }.to_json
  end

  # Return article contents.
  next {
    "data": {"contents": article_contents,},
  }.to_json
end

post "/" do |env|
  # Check parameters.
  if env.params.json.size != 0
    params = env.params.json
  elsif env.params.body.size != 0
    params = env.params.body
  end

  if params
    url, type = get_query_parameters(params)
  end

  # Get article contents.
  if url
    article_contents = get_article_contents_cache(
      url: url, type: type, cache: cache)
  end

  # Error handling
  if !article_contents
    error_message = "A valid Wikipedia url must be passed."
  elsif article_contents.is_a?(String)
    error_message = article_contents
  end

  if error_message
    next {
      "error": {"message": error_message,},
    }.to_json
  end

  # Return article contents.
  next {
    "data": {"contents": article_contents,},
  }.to_json
end


# Error pages

error 404 do
  {"error": {
      "message": "Page not found.",
    },}.to_json
end

error 403 do
  {"error": {
      "message": "Access forbidden!",
    },}.to_json
end

error 500 do
  {"error": {
      "message": "Server error",
    },}.to_json
end


# Helper functions

# Returns the query parameter values.
def get_query_parameters(params)
  # Check parameters.
  if (
    params.has_key?("url") &&
    !params["url"].nil? &&
    params["url"] != ""
  )
    url = params["url"].as(String)
  end

  if (
    params.has_key?("type") &&
    !params["type"].nil?
  )
    params_type = params["type"].as(String).downcase
    if params_type == "parsedhtml" || params_type == "parsed_html"
      type = ContentType::ParsedHTML
    elsif (
      params_type == "parsedwikitext" ||
      params_type == "parsed_wikitext" ||
      params_type == "parsed_wiki_text"
    )
      type = ContentType::ParsedWikiText
    elsif params_type == "html"
      type = ContentType::HTML
    elsif params_type == "wikitext"
      type = ContentType::WikiText
    end
  end

  return url, type
end

# Returns article contents from cache first if available.
def get_article_contents_cache(
  url : String | Nil = nil,
  type : ContentType | Nil = ContentType::ParsedHTML,
  cache : Redis::PooledClient | Nil = nil,
)
  # url must be passed into this function.
  if !url
    return nil
  end

  type_str = ""
  if type
    type_str = type
  end

  if cache
    cache_key = %(#{ENV.fetch("CURRENT_RELEASE_ID", "")}\nget_article_contents_cache\n#{url}\n#{type_str})
    begin
      cached_value = cache.get(cache_key)
      if cached_value
          results = JSON.parse(cached_value)
      else
        results = get_article_contents(url: url, type: type)
        cache.set(cache_key, results.to_json, ex: CACHE_TTL)
      end
    rescue ex : Redis::Error | Redis::PoolTimeoutError | Redis::CommandTimeoutError | JSON::ParseException
      results = get_article_contents(url: url, type: type)
    end
  else
    results = get_article_contents(url: url, type: type)
  end

  return results
end


# Main

Kemal.config do |config|
  config.port = ENV.fetch("PORT", "3000").to_i
  config.env = "production"
  config.serve_static = false
  config.logging = false
end
Kemal.run do |config|
  server = config.server.not_nil!
  server.bind_tcp "0.0.0.0", config.port, reuse_port: true
end
