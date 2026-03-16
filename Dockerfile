FROM hexpm/elixir:1.18.4-erlang-27.3.4.7-debian-bullseye-20260223-slim

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

# Install Hex and Rebar locally in the image
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix configuration and fetch dependencies
COPY mix.exs mix.lock ./
COPY .formatter.exs ./
COPY config ./config
COPY priv ./priv

RUN mix deps.get --only ${MIX_ENV}

# Copy application code
COPY lib ./lib

# Compile in prod
RUN mix compile

# The app listens on PORT (default 4000, overridable via env)
EXPOSE 4000
EXPOSE 4443
ENV PORT=4000 \
    TLS_PORT=4443

# Run the Plug/Cowboy app
CMD ["mix", "run", "--no-halt"]

