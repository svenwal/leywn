# ---- Test Stage ----
FROM hexpm/elixir:1.18.3-erlang-27.3.3-alpine-3.21.3 AS test

ENV MIX_ENV=test \
    LANG=C.UTF-8

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock .formatter.exs ./
COPY config ./config

RUN mix deps.get

COPY priv ./priv
COPY lib ./lib
COPY test ./test

RUN mix format --check-formatted

CMD ["mix", "test"]

# ---- Build Stage ----
FROM hexpm/elixir:1.18.3-erlang-27.3.3-alpine-3.21.3 AS builder

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

RUN apk add --no-cache libwebp-tools

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config

RUN mix deps.get --only prod

COPY priv ./priv
COPY lib ./lib

RUN cwebp -quiet priv/images/leywn.png -o priv/images/leywn.webp

RUN mix release && \
    chmod -R g=u /app/_build/prod/rel/leywn

# ---- Runtime Stage ----
FROM alpine:3.21.3

RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc && \
    adduser -D -u 1001 leywn

ENV LANG=C.UTF-8 \
    LEYWN_PORT=4000 \
    LEYWN_TLS_PORT=4443 \
    HOME=/tmp

WORKDIR /app

# OpenShift runs containers with an arbitrary UID but always GID 0.
# g=u permissions are set in the builder; --chown sets ownership without an extra layer.
COPY --chown=1001:0 --from=builder /app/_build/prod/rel/leywn ./

USER 1001

EXPOSE 4000
EXPOSE 4443

CMD ["/app/bin/leywn", "start"]
