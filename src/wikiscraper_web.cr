require "./lib/wikiscraper.cr"

require "kemal"


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
    article_contents = get_article_contents(url: url, type: type)
  end

  # Error handling
  if !article_contents
    error_message = "A valid Wikipedia url must be passed."
  elsif article_contents.is_a?(String)
    error_message = article_contents
  end

  if error_message
    next {
      "data": nil,
      "error": {"message": error_message,},
    }.to_json
  end

  # Return article contents.
  next {
    "data": {"contents": article_contents,},
    "error": nil,
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
    article_contents = get_article_contents(url: url, type: type)
  end

  # Error handling
  if !article_contents
    error_message = "A valid Wikipedia url must be passed."
  elsif article_contents.is_a?(String)
    error_message = article_contents
  end

  if error_message
    next {
      "data": nil,
      "error": {"message": error_message,},
    }.to_json
  end

  # Return article contents.
  next {
    "data": {"contents": article_contents,},
    "error": nil,
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


# Main

Kemal.config.env = "production"
Kemal.run
