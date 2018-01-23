# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :explorer,
  ecto_repos: [Explorer.Repo]

# Configures gettext
config :explorer, ExplorerWeb.Gettext, locales: ~w(en), default_locale: "en"

# Configures the endpoint
config :explorer, ExplorerWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: ExplorerWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Explorer.PubSub, adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :ethereumex,
  scheme: "http",
  host: "localhost",
  port: 8545

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
