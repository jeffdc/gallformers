defmodule Mix.Tasks.Gallformers.Import.Submit do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Delivers a producer's package directory to Gallformers
  (`Gallformers.Import.submit_package/3`): its `document.json`,
  `taxonomy.json`, `gall.json` and `review.json` go to the private bucket,
  and the package is registered, validated and resolved, ready for review
  on its Source's page (`/admin/review`). The directory's other files (prompts,
  notes, transcripts) stay behind.

      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.import.submit \\
        services/import-producer/output/golden-2026-10-27/98-ashmead-1896

  In development the private bucket is the local disk (`tmp/private_storage`,
  `Gallformers.Storage.Private.LocalAdapter`).

  ## Options

    * `--key KEY` — the package's key (default: the directory's name and the
      time, e.g. `98-ashmead-1896-20261028T091500`). A key is delivered once.
  """
  use Mix.Task

  alias Gallformers.Audit.Actor
  alias Gallformers.Import

  @shortdoc "Delivers a package directory for review"

  @files ["document.json", "taxonomy.json", "gall.json", "review.json"]

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [key: :string])

    dir =
      case rest do
        [dir] -> dir
        _ -> Mix.raise("Usage: mix gallformers.import.submit <package-dir> [--key KEY]")
      end

    files = read_files(dir)
    key = opts[:key] || default_key(dir)

    Mix.Task.run("app.start")
    # Dev logs every query at debug; the report is what matters here.
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: Logger.configure(level: :info)

    case Import.submit_package(Actor.system("import_submit"), key, files) do
      {:ok, package} -> report(package)
      {:error, reason} -> Mix.raise("Could not deliver #{dir}: #{inspect(reason)}")
    end
  end

  defp read_files(dir) do
    files =
      for name <- @files, path = Path.join(dir, name), File.regular?(path), into: %{} do
        {name, File.read!(path)}
      end

    if Map.has_key?(files, "taxonomy.json") or Map.has_key?(files, "gall.json"),
      do: files,
      else: Mix.raise("#{dir} has no taxonomy.json or gall.json")
  end

  defp default_key(dir) do
    stamp = NaiveDateTime.local_now() |> Calendar.strftime("%Y%m%dT%H%M%S")
    "#{Path.basename(Path.expand(dir))}-#{stamp}"
  end

  defp report(package) do
    Mix.shell().info("Package #{package.id} (#{package.key}): #{package.status}")

    for batch <- Import.list_batches(package),
        do: Mix.shell().info("  #{batch.batch_type} batch: #{batch.status}")

    items = Import.list_queue_items(package, status: :open)
    if items != [], do: Mix.shell().info("  open queue items: #{length(items)}")

    for problem <- package.problems,
        do: Mix.shell().info("  #{problem["level"]} (#{problem["file"]}): #{problem["message"]}")
  end
end
