import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/gallformers start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :gallformers, GallformersWeb.Endpoint, server: true
end

# Enable server for E2E tests (evaluated at runtime, not compile-time)
if System.get_env("GALLFORMERS_E2E") == "1" do
  config :gallformers, GallformersWeb.Endpoint, server: true
end

# Only override port/bind if env vars are explicitly set (don't interfere with test config)
if port = System.get_env("PORT") do
  config :gallformers, GallformersWeb.Endpoint, http: [port: String.to_integer(port)]
end

if System.get_env("PHX_BIND") == "0.0.0.0" do
  config :gallformers, GallformersWeb.Endpoint, http: [ip: {0, 0, 0, 0}]
end

# Auth0 configuration
# In development, these can be set in .env or config/dev.secret.exs
# In production, these must be set as environment variables
# Note: callback_url is set in prod.exs (compile-time) because Ueberauth.init runs at compile time
if auth0_domain = System.get_env("AUTH0_DOMAIN") do
  config :ueberauth, Ueberauth.Strategy.Auth0.OAuth,
    domain: auth0_domain,
    client_id: System.get_env("AUTH0_CLIENT_ID"),
    client_secret: System.get_env("AUTH0_CLIENT_SECRET")
end

# AWS S3 configuration for image uploads
# Uses separate PUT-only credentials for upload security
if s3_access_key = System.get_env("S3_PUT_AWS_ACCESS_KEY_ID") do
  config :ex_aws,
    access_key_id: s3_access_key,
    secret_access_key: System.get_env("S3_PUT_AWS_SECRET_ACCESS_KEY")
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/gallformers/gallformers.db
      """

  config :gallformers, Gallformers.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    busy_timeout: 10_000

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :gallformers, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :gallformers, GallformersWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: secret_key_base,
    # Allow WebSocket connections from CloudFront and production domains.
    # CloudFront proxies requests with Origin header set to the viewer's domain,
    # which differs from PHX_HOST (gallformers.fly.dev).
    check_origin: [
      "//gallformers.org",
      "//www.gallformers.org",
      "//gallformers.com",
      "//www.gallformers.com",
      "//gallformers.fly.dev",
      "//*.cloudfront.net"
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :gallformers, GallformersWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :gallformers, GallformersWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :gallformers, Gallformers.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
