# ---- Build Stage ----
FROM hexpm/elixir:1.18.4-erlang-27.3.4.7-debian-bullseye-20260223-slim AS builder

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config

RUN mix deps.get --only prod

COPY priv ./priv
COPY lib ./lib

RUN mix release

# ---- Runtime Stage ----
FROM debian:bullseye-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libssl1.1 libncurses5 webp && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    LEYWN_PORT=4000 \
    LEYWN_TLS_PORT=4443

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/leywn ./

EXPOSE 4000
EXPOSE 4443

CMD ["/app/bin/leywn", "start"]
