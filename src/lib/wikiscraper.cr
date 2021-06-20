require "crest"
require "myhtml"

require "json"

enum ContentType
  ParsedHTML
  ParsedWikiText
  HTML
  WikiText
end

# Returns the article name as a String from the url.
def get_article_name_from_url(url : String)
  last_slash = url.rindex("/")
  id = url.index("#")
  if last_slash
    # "/" has a length of 1
    return id ? url[last_slash+1..id-1] : url[last_slash+1..]
  else
    return nil
  end
end

# Returns the article name as a String from the html parser.
def get_article_name_from_parser(parser : Myhtml::Parser)
  parser
    .css(%q{h1[id="firstHeading"]})
    .each do |node|
      return node.inner_text
    end
end

# Returns the base url from the passed url.
def get_base_url(url : String)
  return url.match(/([a-z]+:\/\/[^\/]+)/).try &.[0]
end

# Returns the article contents as an Array of NamedTuples from the article.
def get_article_contents(
  url : String | Nil = nil,
  type : ContentType | Nil = ContentType::ParsedHTML,
)
  # url must be passed into this function.
  if !url
    return nil
  end

  # Get Wikipedia contents.
  if type == ContentType::WikiText
    # Special wikimedia endpoints
    special_wikimedia = ""
    if (
      url.includes?(".mediawiki.org") ||
      url.includes?(".wikimedia.org") ||
      url.includes?(".wikipedia.org")
    )
      special_wikimedia = "w/"
    end

    begin
      wikitext = JSON.parse(Crest.get(
        "#{get_base_url(url)}/#{special_wikimedia}api.php?action=parse&" +
        "page=#{get_article_name_from_url(url)}&prop=wikitext&" +
        "formatversion=2&format=json"
      ).body)
    rescue ex : Crest::NotFound
      return "Could not find wikitext for article."
    rescue ex : Crest::InternalServerError
      return "Received a wiki internal server error."
    end

    if (
      !wikitext["parse"].nil? &&
      !wikitext["parse"]["wikitext"].nil?
    )
      return [wikitext["parse"]["wikitext"]]
    else
      return "Could not get wikitext."
    end
  end

  begin
    raw_html = Crest.get(url).body
  rescue ex : Crest::NotFound
    return "The page you specified doesn't exist."
  rescue ex : Crest::InternalServerError
    return "Received a wiki internal server error."
  end

  if type == ContentType::HTML
    return [raw_html]
  end

  # if type == ContentType::ParsedHtml
  parser = Myhtml::Parser.new(raw_html)

  if !is_mediawiki?(parser)
    return "Cannot parse page since it is not a wiki article."
  end

  article = get_article_name_from_parser(parser.not_nil!)
  if !article
    article = get_article_name_from_url(url)
    if !article
      return nil
    end
  end

  # Add summary section.
  table_of_contents = [
    {
      "id": ".mw-parser-output",
      "tocnumber": "0",
      "toctext": article.not_nil!
    }
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
        # Sometimes there are two elements with the same id, one nested in the
        # other.
        if node.parent!.next
          node = node.parent!.next!
        else
          node = node.parent!.parent!.next!
        end
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
            content += " #{remove_references(node.inner_text)} "
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

# Returns true if the body tag of the HTML contains the mediawiki class.
def is_mediawiki?(parser : Myhtml::Parser)
  parser
    .css(%q{body})
    .each do |node|
      if (
        node.attribute_by("class") &&
        node.attribute_by("class").not_nil!.includes?("mediawiki")
      )
        return true
      end
    end
  return false
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
    toctext_downcase == "external" ||
    toctext_downcase == "external links" ||
    toctext_downcase == "bibliography" ||
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
        node.attribute_by("class").not_nil!.includes?("mod-gallery") ||
        node.attribute_by("class").not_nil!.includes?("quotebox")
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
    # math element.
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
