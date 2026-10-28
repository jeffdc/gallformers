defmodule Mix.Tasks.Gallformers.Import.Vocab do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Writes the import contract's vocabulary files (`priv/import/vocab/`) from
  the database and code (`Gallformers.Import.Vocab`): the Trait values,
  definitions and term mappings, the generation groups with their values
  and taxa, the places, licenses, ranks and Relationship types. Only the
  files whose content changed are written.

  The committed files come from the rehearsal database (its generation
  groups are mapped to their taxa, and it holds every place). The task only
  reads the database, and starts nothing but the repo:

      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.import.vocab
      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.import.vocab --check

  ## Version

  `traits.json` and `places.json` carry the `vocabulary_version` all the
  files share, a date (`YYYY-MM-DD`). While the content stays the same the
  files keep the date they carry; when it changes they are dated today (the
  local date). `--version` sets the date instead.

  ## Options

    * `--check` — write nothing; list the files that differ from what the
      task would write (with the date they carry) and fail if any do.
    * `--version DATE` — the `vocabulary_version` to write.
    * `--dir PATH` — the vocabulary directory (default `priv/import/vocab`).
  """
  use Mix.Task

  alias Gallformers.Import.Vocab

  @shortdoc "Writes priv/import/vocab/ from the database (--check to compare)"

  @default_dir "priv/import/vocab"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args, strict: [check: :boolean, version: :string, dir: :string])

    dir = Keyword.get(opts, :dir, @default_dir)
    start_repo()

    if opts[:check], do: check(dir), else: write(dir, opts[:version])
  end

  defp check(dir) do
    case Vocab.check(dir) do
      :ok ->
        Mix.shell().info(
          "#{dir} is up to date (vocabulary_version #{Vocab.committed_version(dir)})."
        )

      {:error, names} ->
        Mix.raise(
          "#{dir} differs from the database in: #{Enum.join(names, ", ")}. " <>
            "Run mix gallformers.import.vocab to write them."
        )
    end
  end

  defp write(dir, version) do
    case Vocab.write(dir, version: version) do
      {:ok, %{written: [], version: version}} ->
        Mix.shell().info("#{dir} is up to date (vocabulary_version #{version}).")

      {:ok, %{written: names, version: version}} ->
        for name <- names, do: Mix.shell().info("Wrote #{Path.join(dir, name)}")
        Mix.shell().info("vocabulary_version #{version}")

      {:error, {:invalid_version, given}} ->
        Mix.raise("--version must be a date, YYYY-MM-DD (got #{inspect(given)}).")
    end
  end

  # The repo only: this task reads, and must not start Oban's queues on the
  # database it reads.
  defp start_repo do
    Mix.Task.run("app.config")
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: Logger.configure(level: :info)
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

    case Gallformers.Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
