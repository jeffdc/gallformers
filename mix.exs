defmodule Gallformers.MixProject do
  use Mix.Project

  def project do
    [
      app: :gallformers,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: dialyzer()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Gallformers.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:earmark, "~> 1.4"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # API Documentation
      {:open_api_spex, "~> 3.18"},
      # Rate Limiting
      {:hammer, "~> 6.1"},
      # Authentication
      {:ueberauth, "~> 0.10"},
      {:ueberauth_auth0, "~> 2.1"},
      # AWS S3 for image uploads
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      {:hackney, "~> 1.20"},
      # Image processing
      {:image, "~> 0.54"},
      # User agent parsing for analytics
      {:browser, "~> 0.5.5"},
      # Dev/Test tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # E2E browser testing (separate from regular test suite)
      {:wallaby, "~> 0.30", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "test.check_exclusions": ["ecto.create --quiet", "ecto.migrate --quiet", "test.check_exclusions_run"],
      "test.check_exclusions_run": &check_test_exclusions/1,
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind gallformers", "esbuild gallformers"],
      "assets.deploy": [
        "tailwind gallformers --minify",
        "esbuild gallformers --minify",
        "phx.digest"
      ],
      precommit: [
        "format_check",
        "compile --warnings-as-errors",
        "credo --strict",
        "migrations.lint",
        "deps.unlock --unused",
        "test",
        "test.check_exclusions"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts/core.plt",
      plt_local_path: "priv/plts/project.plt",
      plt_add_apps: [:mix, :ex_unit],
      flags: [
        :error_handling,
        :unknown
      ]
    ]
  end

  defp releases do
    [
      gallformers: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  # Check for unexpected test exclusions (Option A solution)
  # Runs all tests including E2E to detect if any non-E2E tests are excluded
  # (e.g., accidentally tagged with @tag :skip, @tag :pending, etc.)
  #
  # Usage: mix test.check_exclusions
  #
  # Expected output: "726 tests, 0 failures" (705 unit + 21 E2E)
  # If you see "X excluded" where X > 0, there are hidden exclusions to investigate
  defp check_test_exclusions(_args) do
    IO.puts("\n" <> IO.ANSI.yellow() <> "==> Checking for unexpected test exclusions..." <> IO.ANSI.reset())
    IO.puts("==> Running ALL tests (including E2E) to detect hidden exclusions\n")

    # Set env to start Wallaby for E2E tests
    System.put_env("GALLFORMERS_E2E", "1")

    # Run with --include e2e to override default exclusion
    # If any tests are still excluded, they have other tags like :skip or :pending
    Mix.Task.run("test", ["--include", "e2e"])

    IO.puts("\n" <> IO.ANSI.green() <> "==> Check complete!" <> IO.ANSI.reset())
    IO.puts("==> Expected: 726 tests total (705 unit + 21 E2E), 0 excluded")
    IO.puts("==> If you see 'X excluded' above, investigate those tests")
    IO.puts("==> Common causes: @tag :skip, @tag :pending, @moduletag :skip\n")
  end
end
