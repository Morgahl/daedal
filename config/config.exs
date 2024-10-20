# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :daedal,
  ecto_repos: [Daedal.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :daedal, :ash_domains, [Daedal.Beacon]

config :ash,
  include_embedded_source_by_default?: false,
  default_page_type: :keyset

config :ash, :policies, no_filter_static_forbidden_reads?: false

# Configures the endpoint
config :daedal, DaedalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DaedalWeb.ErrorHTML, json: DaedalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Daedal.PubSub,
  live_view: [signing_salt: "eVOk8GoA"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  daedal: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  daedal: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: :all

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
