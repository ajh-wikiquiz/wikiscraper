# wikiscraper
Parses and returns text of the given Wikipedia article broken up into sections.

This is intended to be deployed as a web service. A live example can be found at https://ajh-wikiscraper.herokuapp.com/.
The wikiscraper accepts HTTP GET and POST requests. The POST requests must be in JSON format.


### Example inputs
```
{"url": "https://en.wikipedia.org/wiki/Pet_door"}
```

```
{"article": "Pet door"}
```

article is ignored if url is set. In other words, url is prioritized over article.
```
{"article": "gibberish", "url": "https://en.wikipedia.org/wiki/Pet_door"}
```

As long as /wiki/ is in the URL, the scraper can attempt to parse the article.
```
{"url": "https://www.mediawiki.org/wiki/Hackathons"}
```

If the parsed text isn't to your liking, setting raw to true will return the unparsed text.
```
{"url": "https://www.mediawiki.org/wiki/Hackathons", "raw": true}
```


### Example outputs
```
{
    "data": {
        "article": "Pet door",
        "contents": [
            {"number": 0, "title": "Pet door", "content": "A pet door or pet..."},
            {"number": 1, "title": "Purpose", "content": "A pet door is found..."},
            ...
        ]
    }
}
```

With raw set to true
```
{
    "data": {
        "article": "Pet door",
        "contents": "<div class=\"mw-parser-output\">..."
    }
}
```

When both the article name and url are missing, or when the url doesn't contain /wiki/
```
{
    "error":
    {
      "message": "An article name or valid Wikipedia URL must be passed."
    }
}
```

When the article doesn't exist
```
{
    "data": {
        "article": "Pet_dooro",
        "contents": "The page you specified doesn't exist."
    }
}
```


## Development
```
shard install
crystal run src/wikiscraper.cr
```


## Contributing
1. Fork it (<https://github.com/your-github-user/wikiscraper/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
