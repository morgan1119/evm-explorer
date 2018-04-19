# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

url = "https://sokol.poa.network"

config :explorer, :eth_client,
  http: [recv_timeout: 60_000, timeout: 60_000, hackney: [pool: :eth]],
  trace_url: "https://sokol-trace.poa.network",
  url: url

config :ethereumex,
  url: url,
  http_options: [recv_timeout: 60_000, timeout: 60_000, hackney: [pool: :eth]]

# General application configuration
config :explorer, ecto_repos: [Explorer.Repo]

config :explorer, :ethereum, backend: Explorer.Ethereum.Live

config :explorer, Explorer.Integrations.EctoLogger, query_time_ms_threshold: 2_000

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
