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
      compilers: [:phoenix_live_view, :boundary] ++ Mix.compilers(),
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
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.20"},
      {:oban_web, "~> 2.11"},
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
      # JSON Schema validation
      {:ex_json_schema, "~> 0.11"},
      {:earmark, "~> 1.4"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # For HTML parsing of URLs in the ingestion pipeline
      {:floki, "~> 0.38"},
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
      # CSV parsing for WCVP reconciliation
      {:nimble_csv, "~> 1.2"},
      # User agent parsing for analytics
      {:browser, "~> 0.5.5"},
      # Structured JSON logging
      {:logger_json, "~> 7.0"},
      # Dev/Test tools
      {:boundary, "~> 0.10", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # Security scanning
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # E2E browser testing (Playwright, separate from regular test suite)
      {:phoenix_test, "~> 0.4", only: :test, runtime: false},
      {:phoenix_test_playwright, "~> 0.12", only: :test, runtime: false}
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
      "test.check_exclusions": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test.check_exclusions_run"
      ],
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
      plt_add_apps: [:mix, :ex_unit, :credo],
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

  # Check for unexpected test exclusions
  # Runs unit tests only (E2E tests require prod data and are excluded).
  # Detects if any non-E2E tests are accidentally excluded
  # (e.g., tagged with @tag :skip, @tag :pending, etc.)
  #
  # Usage: mix test.check_exclusions
  #
  # Expected output: "705 tests, 0 failures"
  # If you see "X excluded" where X > 0, there are hidden exclusions to investigate
  defp check_test_exclusions(_args) do
    IO.puts(
      "\n" <>
        IO.ANSI.yellow() <> "==> Checking for unexpected test exclusions..." <> IO.ANSI.reset()
    )

    IO.puts("==> Running unit tests to detect hidden exclusions\n")
    IO.puts("==> (E2E tests excluded — they require prod data. Run `make e2e` separately.)\n")

    # Run without E2E — those require prod data and are a separate preflight step
    Mix.Task.run("test", [])

    IO.puts("\n" <> IO.ANSI.green() <> "==> Check complete!" <> IO.ANSI.reset())
    IO.puts("==> Expected: 705 tests, 0 excluded")
    IO.puts("==> If you see 'X excluded' above, investigate those tests")
    IO.puts("==> Common causes: @tag :skip, @tag :pending, @moduletag :skip\n")
  end
end
