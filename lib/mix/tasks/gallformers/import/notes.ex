defmodule Mix.Tasks.Gallformers.Import.Notes do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Writes Gallformers notes as producer packages (`20e5`,
  `Gallformers.Import.NotePackage`): one directory per Gall, `note-<id>`,
  holding `document.json` (the note) and `note.json` (its Gall and date).

      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.import.notes \\
        --dir services/import-producer/output/notes-2026-10-30 --undescribed --limit 20

  Then, in `services/import-producer`, `uv run produce note <dirs>` readies
  them for phase 3, and phases 3 to 6 run as for any Source.

  ## Options

    * `--dir DIR` — where to write the directories (required).
    * `--stated-on YYYY-MM-DD` — the date the statements take (default:
      today). A legacy note has none of its own.
    * `--undescribed` / `--described` — only the notes of undescribed (no
      species-rank Inducer) or described Galls.
    * `--limit N` — at most N notes, in Gall ID order.

  Gall IDs given as arguments pick those notes instead.
  """
  use Mix.Task

  alias Gallformers.Import.NotePackage

  @shortdoc "Writes Gallformers notes as producer packages"

  @impl Mix.Task
  def run(args) do
    {opts, ids} =
      OptionParser.parse!(args,
        strict: [
          dir: :string,
          stated_on: :string,
          undescribed: :boolean,
          described: :boolean,
          limit: :integer
        ]
      )

    dir = opts[:dir] || Mix.raise("Usage: mix gallformers.import.notes --dir DIR [options]")
    stated_on = stated_on(opts[:stated_on])

    Mix.Task.run("app.start")
    # Dev logs every query at debug; the report is what matters here.
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: Logger.configure(level: :info)

    written =
      ids
      |> gall_ids(opts)
      |> then(&if opts[:limit], do: Enum.take(&1, opts[:limit]), else: &1)
      |> Enum.filter(&write(dir, &1, stated_on))

    Mix.shell().info("#{length(written)} note packages in #{dir}, stated on #{stated_on}")
  end

  defp stated_on(nil), do: Date.utc_today()

  defp stated_on(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> date
      {:error, _} -> Mix.raise("--stated-on must be YYYY-MM-DD, got #{date}")
    end
  end

  defp gall_ids([], opts) do
    cond do
      opts[:undescribed] -> NotePackage.gall_ids(:undescribed)
      opts[:described] -> NotePackage.gall_ids(:described)
      true -> NotePackage.gall_ids(:all)
    end
  end

  defp gall_ids(ids, _opts) do
    ids
    |> Enum.map(fn id ->
      case Integer.parse(id) do
        {n, ""} -> n
        _ -> Mix.raise("not a Gall ID: #{id}")
      end
    end)
    |> Enum.sort()
  end

  defp write(dir, gall_id, stated_on) do
    case NotePackage.files(gall_id, stated_on) do
      {:ok, files} ->
        package = Path.join(dir, "note-#{gall_id}")
        File.mkdir_p!(package)
        for {name, bytes} <- files, do: File.write!(Path.join(package, name), bytes)
        true

      {:error, :no_note} ->
        Mix.shell().info("Gall #{gall_id} has no note")
        false
    end
  end
end
