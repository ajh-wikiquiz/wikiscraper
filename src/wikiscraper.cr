require "crest"
require "kemal"
require "myhtml"

require "json"


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
  # Check parameters.
  if env.params.query.size != 0
    if env.params.query.has_key?("article") && !env.params.query["article"].nil?
      article = env.params.query["article"].as(String)
    elsif env.params.query.has_key?("url") && !env.params.query["url"].nil?
      url = env.params.query["url"].as(String)
      article = get_article_name(url)
    end
  end

  # Get article contents.
  if article
    article_contents = get_article_contents(article)
  else
    next {"error": {
      "message": "A valid Wikipedia url or article name must be passed.",
    },}.to_json
  end

  # Return article contents.
  next {
    "data":
      {
        "article": article,
        "contents": article_contents,
      },
  }.to_json
end

post "/" do |env|
  # Check parameters.
  if env.params.json.size != 0
    if env.params.json.has_key?("article") && !env.params.json["article"].nil?
      article = env.params.json["article"].as(String)
    elsif env.params.json.has_key?("url") && !env.params.json["url"].nil?
      url = env.params.json["url"].as(String)
      article = get_article_name(url)
    end
  elsif env.params.body.size != 0
    if env.params.body.has_key?("article") && !env.params.body["article"].nil?
      article = env.params.body["article"].as(String)
    elsif env.params.body.has_key?("url") && !env.params.body["url"].nil?
      url = env.params.body["url"].as(String)
      article = get_article_name(url)
    end
  end

  # Get article contents.
  if article
    article_contents = get_article_contents(article)
  else
    next {"error": {
      "message": "A valid Wikipedia url or article name must be passed.",
    },}.to_json
  end

  # Return article contents.
  next {
    "data":
      {
        "article": article,
        "contents": article_contents,
      },
  }.to_json
end


# Helper functions

# Returns the article name as a String from the url.
# TODO: Refactor.
def get_article_name(url : String)
  wiki = url.index("/wiki/")
  id = url.rindex("#")
  if wiki
    return id ? url[wiki+6..id-1] : url[wiki+6..]  # "/wiki/" has a length of 6
  else
    return nil
  end
end

# Returns the article contents as a Hash from the article.
def get_article_contents(
  article : String | Nil = nil,
  url : String | Nil = nil,
)
  # Either article or url must be passed into this function.
  if !article && !url
    return nil
  end

  # Get Wikipedia contents.
  if article
    parser = Myhtml::Parser.new(JSON.parse(Crest.get(
      "https://en.wikipedia.org/w/api.php",
      params: {
        :action => "parse",
        :page => article,
        :prop => "text",
        :formatversion => 2,
        :format => "json",
      }
    ).body)["parse"]["text"].as_s)
  elsif url
    article = get_article_name(url)
    parser = Myhtml::Parser.new(
      Crest.get(url).body)
  end

  # TODO: Check for nil on parser here.

  # Add summary text.
  table_of_contents = [{".mw-parser-output", "0", article}]
  # Read table of contents.
  parser.not_nil!
    .css(%q{div[id="toc"] li[class*="toclevel"]})
    .each do |node|
      id = node.child!.attribute_by("href").not_nil!
      node = node.child!
      tocnumber, toctext = node.inner_text.split(2)  # TODO: Don't hardcode.
      table_of_contents.push({id, tocnumber, toctext})
    end

  # [{"number": 1, "title": "Purpose", "content": "A pet door..."}]
  sections = Array(
    NamedTuple(number: String, title: String, content: String)).new

  table_of_contents.each do |toc|
    if (
      toc[2].includes?("See also") ||
      toc[2].includes?("References") ||
      toc[2].includes?("Further reading") ||
      toc[2].includes?("External links")
    )
      break
    else
      append_section(sections, toc, parser.not_nil!, article)
    end

  end

  return sections
end

# Helper function for `get_article_contents`.
# TODO: Refactor.
def append_section(
  sections : Array(NamedTuple(number: String, title: String, content: String)),
  toc : Tuple(String, String, String),
  parser : Myhtml::Parser,
  article : String
)
  if toc[2] != article
    css_selector = %(span[id="#{toc[0].sub("#", "")}"])
  else
    css_selector = %(div[class="#{toc[0].sub(".", "")}"])
  end

  # Create content string for each section except for References.
  content = ""
  parser
    .css(css_selector)
    .each do |node|
      if toc[2] != article
        node = node.parent!.next!
      else
        node = node.child!
      end

      while node
        # Stop appending for section once the next section has been reached.
        if (
          (
            (node.tag_name == "h2" || node.tag_name == "h3") &&
            node.child &&
            node.child!.attribute_by("class") == "mw-headline"
          ) ||
          node.attribute_by("class") == "reflist" ||
          (
            node.tag_name == "div" &&
            node.attribute_by("id") &&
            node.attribute_by("id").not_nil! == ("toc")
          )
        )
          break
        end
        # Ignore captions.
        if !(
          node.tag_name == "div" &&
          node.attribute_by("class") &&
          node.attribute_by("class").not_nil!.includes?("thumb")
        )
          # Strip all references and append.
          content += node.inner_text.gsub(/[[0-9]+]/, "")
        end
        node = node.next
      end
    end
  sections.push({"number": toc[1], "title": toc[2], "content": content})
end


# Main

Kemal.config.env = "production"
Kemal.run
