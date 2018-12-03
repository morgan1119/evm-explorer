use Mix.Config

# Configures the database
config :explorer, Explorer.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: String.equivalent?(System.get_env("ECTO_USE_SSL") || "true", "true"),
  prepare: :unnamed,
  timeout: 60_000

config :explorer, Explorer.Tracer, env: "production", disabled?: true

config :logger, :explorer,
  level: :info,
  path: Path.absname("logs/prod/explorer.log"),
  rotate: %{max_bytes: 52_428_800, keep: 19}

config :logger, :reading_token_functions,
  level: :debug,
  path: Path.absname("logs/prod/explorer/tokens/reading_functions.log"),
  metadata_filter: [fetcher: :token_functions],
  rotate: %{max_bytes: 52_428_800, keep: 19}

variant =
  if is_nil(System.get_env("ETHEREUM_JSONRPC_VARIANT")) do
    "parity"
  else
    System.get_env("ETHEREUM_JSONRPC_VARIANT")
    |> String.split(".")
    |> List.last()
    |> String.downcase()
  end

# Import variant specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "prod/#{variant}.exs"
