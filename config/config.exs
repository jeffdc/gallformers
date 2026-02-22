# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :gallformers,
  ecto_repos: [Gallformers.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :gallformers, GallformersWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GallformersWeb.ErrorHTML, json: GallformersWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Gallformers.PubSub,
  live_view: [signing_salt: "NrFzJJrt", hibernate_after: 5_000]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :gallformers, Gallformers.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  gallformers: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  gallformers: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Disable Tesla deprecation warning (transitive dependency)
config :tesla, disable_deprecated_builder_warning: true

# Configure Hammer rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Configure ex_aws for S3 image uploads
# Credentials are set in runtime.exs from environment variables
config :ex_aws,
  region: "us-east-1",
  json_codec: Jason

config :ex_aws, :hackney_opts,
  follow_redirect: true,
  recv_timeout: 30_000

# Image storage configuration
config :gallformers, :images,
  bucket: "gallformers-images-us-east-1",
  cdn_url: "https://dhz6u1p7t6okk.cloudfront.net",
  # Presigned URL expiry (5 minutes)
  presign_expiry: 300

# Configure Ueberauth for Auth0 authentication
# Client ID and secret are set in runtime.exs from environment variables
config :ueberauth, Ueberauth,
  providers: [
    auth0: {Ueberauth.Strategy.Auth0, []}
  ]

# WCVP lookup database (read-only, no migrations)
config :gallformers, Gallformers.Repo.WCVP, pool_size: 2

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
