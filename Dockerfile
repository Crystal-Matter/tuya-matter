FROM 84codes/crystal:1.22.3-alpine AS build
WORKDIR /app

RUN apk add --no-cache ca-certificates git gmp-dev openssl-dev yaml-dev zlib-dev
COPY shard.yml shard.lock ./
RUN shards install --production --frozen --skip-postinstall --skip-executables
COPY src/ src/
RUN mkdir -p bin \
    && crystal build src/tuya-matter.cr --release --no-debug --threads=2 -o bin/tuya-matter

FROM alpine:3.24
WORKDIR /app

RUN apk add --no-cache ca-certificates gmp libgcc libssl3 pcre2 yaml zlib \
    && addgroup -g 10001 matter \
    && adduser -D -H -u 10001 -G matter matter \
    && install -d -m 0700 -o matter -g matter /data
COPY --from=build /app/bin/tuya-matter /usr/local/bin/tuya-matter
RUN /usr/local/bin/tuya-matter --help > /dev/null

ENV MATTER_STORAGE_FILE=/data/tuya-matter.yml
USER 10001:10001
EXPOSE 5540/udp
ENTRYPOINT ["/usr/local/bin/tuya-matter"]
