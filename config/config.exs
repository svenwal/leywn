import Config

config :leywn,
  port: 4000,
  tls_port: 4443,
  echo_max_body_bytes: 65_536

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
config :tzdata, :autoupdate, :disabled

