use Mix.Config

# Do not print debug messages in production

config :logger, :console, level: :info

config :logger, :ecto,
  level: :info,
  path: "logs/prod/ecto.log"

config :logger, :error, path: "logs/prod/error.log"
