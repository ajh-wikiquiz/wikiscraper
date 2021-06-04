# wikiscraper
Parses and returns text of the given Wikipedia article broken up into sections.

This is intended to be deployed as a web service. A live example can be found at https://ajh-wikiscraper.herokuapp.com/?url=https://en.wikipedia.org/wiki/Pet_door.
The wikiscraper accepts HTTP GET and POST requests.


### Example inputs
```
url=https://en.wikipedia.org/wiki/Pet_door
```

Set "type" to "html" to return the unparsed HTML text.
```
url=https://en.wikipedia.org/wiki/Pet_door
type=html
```

Set "type" to "wikitext" to return the unparsed wikitext.
```
url=https://en.wikipedia.org/wiki/Pet_door
type=wikitext
```


### Example outputs
```json
{
    "data": {
        "contents": [
            {"number": 0, "title": "Pet door", "content": "A pet door or pet..."},
            {"number": 1, "title": "Purpose", "content": "A pet door is found..."},
            ...
        ]
    },
}
```

With type set to "html"
```json
{
    "data": {"contents": ["<div class=\"mw-parser-output\">..."]},
}
```

With type set to "wikitext"
```json
{
    "data": {"contents": ["[[File:Doggy door exit.JPG|thumb|A dog..."]},
}
```

When the url is missing
```json
{
    "error": "A valid Wikipedia URL must be passed."
}
```

When the article doesn't exist
```json
{
    "error": "The page you specified doesn't exist."
}
```


## Development
```
shards install
crystal run src/wikiscraper_web.cr
```


## Contributing
1. Fork it (<https://github.com/your-github-user/wikiscraper/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
