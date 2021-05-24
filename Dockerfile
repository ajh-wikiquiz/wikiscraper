FROM docker.io/crystallang/crystal:latest-alpine AS builder
WORKDIR /app
COPY . .
RUN shards install && \
    crystal build --release --static src/wikiscraper_web.cr

FROM gcr.io/distroless/static:latest
COPY --from=builder /app/wikiscraper_web .
ENTRYPOINT ["./wikiscraper_web"]
