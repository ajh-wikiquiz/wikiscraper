require "crest"
require "kemal"
require "myhtml"

require "json"

# Used when just the article name is passed in.
ENGLISH_WIKIPEDIA_API_ENDPOINT = "https://en.wikipedia.org/w/api.php"


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
    if (
      env.params.query.has_key?("url") &&
      !env.params.query["url"].nil? &&
      env.params.query["url"] != ""
    )
      p! env.params.query["url"]
      url = env.params.query["url"].as(String)
    elsif env.params.query.has_key?("article") && !env.params.query["article"].nil?
      article = env.params.query["article"].as(String)
    end

    if (
      env.params.query.has_key?("raw") &&
      !env.params.query["raw"].nil? &&
      env.params.query["raw"].as(String).downcase == "true"
    )
      is_raw = true
    end
  end

  # Get article contents.
  if url
    article_contents = get_article_contents(url: url, raw?: is_raw)
    article = get_article_name_from(url: url)
  elsif article
    article_contents = get_article_contents(article: article, raw?: is_raw)
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
    params = env.params.json
  elsif env.params.body.size != 0
    params = env.params.body
  end

  if params
    if (
      params.has_key?("url") &&
      !params["url"].nil? &&
      params["url"] != ""
    )
      url = params["url"].as(String)
    elsif params.has_key?("article") && !params["article"].nil?
      article = params["article"].as(String)
    end

    if (
      params.has_key?("raw") &&
      !params["raw"].nil? &&
      params["raw"].as(String).downcase == "true"
    )
      is_raw = true
    end
  end

  # Get article contents.
  if url
    article_contents = get_article_contents(url: url, raw?: is_raw)
    article = get_article_name_from(url)
  elsif article
    article_contents = get_article_contents(article: article, raw?: is_raw)
  else
    next {"error": {
      "message": "An article name or valid Wikipedia URL must be passed.",
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
def get_article_name_from(url : String)
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
  raw? : Bool | Nil = false,
)
  # Either article or url must be passed into this function.
  if !article && !url
    return nil
  end

  # Get Wikipedia contents.
  if url
    article = get_article_name_from(url)
    if !article
      return nil
    end

    begin
      wikitext = Crest.get(url).body
    rescue ex : Crest::NotFound
      return "The page you specified doesn't exist."
    rescue ex : Crest::InternalServerError
      return "Wikipedia Internal Server Error"
    end

    if raw?
      return wikitext
    end

    parser = Myhtml::Parser.new(wikitext)

  elsif article
    response = JSON.parse(Crest.get(
      ENGLISH_WIKIPEDIA_API_ENDPOINT,
      params: {
        :action => "parse",
        :page => article,
        :prop => "text",
        :formatversion => 2,
        :format => "json",
      }
    ).body)
    if response["parse"]? && response["parse"]["text"]?
      wikitext = response["parse"]["text"].as_s
    elsif response["error"]? && response["error"]["info"]?
      return response["error"]["info"].as_s
    else
      return nil
    end

    if raw?
      return wikitext
    end

    parser = Myhtml::Parser.new(wikitext)

  else
    return nil
  end

  # Add summary section.
  table_of_contents = [
    {"id": ".mw-parser-output", "tocnumber": "0", "toctext": article.not_nil!}
  ]
  # Read table of contents.
  parser.not_nil!
    .css(%q{div[id="toc"] li[class*="toclevel"]})
    .each do |node|
      id = node.child!.attribute_by("href").not_nil!
      node = node.child!
      tocnumber, toctext = node.inner_text.split(2)  # Need to split on 2 here.
      table_of_contents.push(
        {"id": id, "tocnumber": tocnumber, "toctext": toctext})
    end

  # Example: [{"number": 1, "title": "Purpose", "content": "A pet door..."},]
  sections = Array(
    NamedTuple(number: String, title: String, content: String)).new

  # Get sections of content.
  table_of_contents.each do |toc|
    if skip_section?(toc["toctext"])
      next
    else
      append_section(sections, toc, parser.not_nil!, article)
    end

  end

  return sections
end

# Pushes a section of content onto the sections array.
# Helper function for `get_article_contents`.
# Jumps to a section noted from the table of contents to begin parsing.
def append_section(
  sections : Array(NamedTuple(number: String, title: String, content: String)),
  toc : NamedTuple(id: String, tocnumber: String, toctext: String),
  parser : Myhtml::Parser,
  article : String
)
  # TODO: Find a better way to special case the summary section.
  if toc["toctext"] != article
    css_selector = %(span[id="#{toc["id"].sub("#", "")}"])
  else
    css_selector = %(div[class="#{toc["id"].sub(".", "")}"])
  end

  # Create content string for each section except for References.
  content = ""
  parser
    .css(css_selector)
    .each do |node|
      if toc["toctext"] != article
        node = node.parent!.next!
      else
        node = node.child!
      end

      while node
        # Stop appending text once the start of another section is found.
        if breakpoint?(node)
          break
        end
        # Ignore captions, sidebars, and random style tags.
        if ignore?(node)
          # Don't append to content if it's a node to be ignored.
        else
          if math_element = math_element?(node)
            content += " #{math_element} "
          else
            content += remove_references(node.inner_text)
          end
        end

        node = node.next
      end

    end

  sections.push(
    {
      "number": toc["tocnumber"],
      "title": toc["toctext"],
      "content": replace_whitespaces(content).strip()
    }
  )
end

# Returns true if the string matches a section to be skipped, else false.
def skip_section?(toctext : String)
  toctext_downcase = toctext.downcase
  if (
    toctext_downcase == "see also" ||
    toctext_downcase == "notes" ||
    toctext_downcase == "references" ||
    toctext_downcase == "further reading" ||
    toctext_downcase == "popular reading" ||
    toctext_downcase == "university textbooks and monographs" ||
    toctext_downcase == "review papers" ||
    toctext_downcase == "external links" ||
    toctext_downcase == "videos"
  )
    return true
  end
  return false
end

# Returns true if it looks like the current section has ended or the next
# section has been reached.
def breakpoint?(node : Myhtml::Node)
  current = node
  while current
    if (
      (
        current.attribute_by("class") &&
        current.attribute_by("class").not_nil!.includes?("mw-headline")
      ) ||
      current.attribute_by("class") == "reflist" ||
      (
        current.tag_name == "div" &&
        (
          (
            current.attribute_by("id") &&
            current.attribute_by("id").not_nil! == ("toc")
          ) ||
          (
            current.attribute_by("class") &&
            (
              current.attribute_by("class").not_nil!.includes?("toclimit-4")
            )
          )
        )
      )
    )
      # Next section or end of section has been reached.
      return true
    end

    if (
      /h[0-9]/i.match(current.tag_name) &&
      current.child
    )
      # Search children recursively.
      if (is_breakpoint = breakpoint?(current.child!))
        return is_breakpoint
      end
    end

    # From what I've seen, we only need to check siblings if it's a span tag.
    if current.next && current.next!.tag_name == "span"
      current = current.next
    else
      break
    end
  end

  return false
end

# Returns true if the node should be ignored for text appending.
def ignore?(node : Myhtml::Node)
  if (
    (
      node.tag_name == "div" &&
      node.attribute_by("class") &&
      (
        node.attribute_by("class").not_nil!.includes?("thumb") ||
        node.attribute_by("class").not_nil!.includes?("hatnote") ||
        node.attribute_by("class").not_nil!.includes?("shortdescription") ||
        node.attribute_by("class").not_nil!.includes?("mod-gallery")
      )
    ) ||
    (
      node.tag_name == "table"
    ) ||
    (
      node.tag_name == "style"
    )
  )
    return true
  end
  return false
end

# Returns the math element if found in the node, else nil.
def math_element?(node : Myhtml::Node | Nil)
  current = node
  while current
    # Confirmed math element
    if current.tag_name == "math"
      if current.attribute_by("alt")
        return current.attribute_by("alt")
      end
      if current.attribute_by("alttext")
        return current.attribute_by("alttext")
      end
    elsif (
      current.tag_name == "annotation" &&
      current.attribute_by("encoding") &&
      current.attribute_by("encoding").not_nil!.includes?("application/x-tex")
    )
      return current.inner_text
    elsif (
      current.tag_name == "img" &&
      current.attribute_by("class") &&
      current.attribute_by("class").not_nil!.includes?(
        "mwe-math-fallback-image-inline")
    )
      if current.attribute_by("alt")
        return current.attribute_by("alt")
      end
      if current.attribute_by("alttext")
        return current.attribute_by("alttext")
      end
      # Else do nothing.

    # If it looks like it could be a math element...
    elsif (
      current.tag_name == "span" ||
      current.tag_name == "dl" ||
      current.tag_name == "dd" ||
      current.tag_name == "semantics" ||
      current.tag_name == "dd" ||
      (
        current.attribute_by("class") &&
        current.attribute_by("class").not_nil!.includes?("mwe-math-element")
      )
    )
      # Search deeper recursively.
      if (child = math_element?(current.child))
        return child
      end

    else  # Not likely to be a math element.
      break
    end

    # If the next element has the same tag name, it's likely to be a different
    # math element if it is one.
    if current.next && current.tag_name == current.next!.tag_name
      break
    end

    current = current.next
  end

  return nil
end

# Removes all the wikipedia source references within text.
def remove_references(inner_text : String)
  return inner_text.gsub(/\[[0-9]+\]|\[[a-z]+\]|\[edit\]|\[Note [0-9]+\]/, "")
end

# Replaces some of the whitespace with a single space.
def replace_whitespaces(inner_text : String)
  return inner_text.gsub(/\t|\s\s+/, " ")
end


# Main

Kemal.config.env = "production"
Kemal.run
