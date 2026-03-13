defmodule Mix.Tasks.ConvertSqlite do
  @moduledoc """
  Convert data from the SQLite production copy to the Postgres dev database.

  Reads from `priv/gallformers.sqlite` (or a custom path) and writes to the
  configured Postgres repo. Schema must already exist — run `mix ecto.migrate`
  first. All Postgres tables are truncated before loading.

  ## Usage

      mix convert_sqlite
      mix convert_sqlite --sqlite-path path/to/gallformers.sqlite
  """

  use Mix.Task

  @shortdoc "Convert data from SQLite prod copy to Postgres"

  @requirements ["app.config"]

  @default_sqlite_path "priv/gallformers.sqlite"

  # Dialyzer has trouble tracing Mix task invocations
  @dialyzer [:no_unused, :no_return, :no_match]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [sqlite_path: :string])
    sqlite_path = Keyword.get(opts, :sqlite_path, @default_sqlite_path)

    unless File.exists?(sqlite_path) do
      Mix.Shell.IO.error("SQLite file not found: #{sqlite_path}")
      Mix.Shell.IO.error("Run `make download-db` to get the production copy.")
      exit({:shutdown, 1})
    end

    Mix.Task.run("app.start")

    Gallformers.Convert.convert(sqlite_path)
  end
end
