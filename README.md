# wikiscraper

Example input
```
{
    "url": "https://en.wikipedia.org/wiki/Pet_door"
}
```
OR
```
{
    "article": "Pet door"
}
```

Output
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

## Installation
```
shard install
```

## Usage
```
crystal build src/wikiscraper.cr --release
```

## Development
```
crystal run src/wikiscraper.cr
```

## Contributing

1. Fork it (<https://github.com/your-github-user/wikiscraper/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

