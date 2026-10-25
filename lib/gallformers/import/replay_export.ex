defmodule Gallformers.Import.ReplayExport do
  @moduledoc """
  The replay log as a file (`9449` Task 17; `b5bd` M6), to carry the
  backscan from preview to production.

  On preview, `export/0` writes every `replay_log` entry, in order, to
  `replay/replay_log-<UTC time>.json` in the private bucket (shared by
  preview and production). After the cutover data migration, production
  reads that file back (`read/1`) and replays it
  (`Gallformers.Import.Replay`), which writes production's own log as it
  goes.

  Nothing else needs carrying: the packages replay reads stay in the
  private bucket under `import/<key>/`, and the migration never deletes
  them, nor Sources or their stored documents (`Gallformers.CatalogMigration`).

  The file is JSON: `%{"format", "exported_at", "entries" => [%{"kind",
  "key", "payload", "inserted_at"}]}`, entries in log order.
  """
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Storage.Private

  @format "gallformers-replay-log/1"

  @type entry :: %{
          kind: ReplayEntry.kind(),
          key: map(),
          payload: map(),
          inserted_at: String.t() | nil
        }

  @doc "Writes the whole log to the private bucket: its key and how many entries."
  @spec export() :: {:ok, %{key: String.t(), count: non_neg_integer()}} | {:error, term()}
  def export do
    entries = ReplayLog.list()
    now = DateTime.utc_now()
    key = "replay/replay_log-#{DateTime.to_iso8601(now, :basic)}.json"

    json =
      Jason.encode!(%{
        "format" => @format,
        "exported_at" => DateTime.to_iso8601(now),
        "entries" =>
          for e <- entries do
            %{
              "kind" => to_string(e.kind),
              "key" => e.key,
              "payload" => e.payload,
              "inserted_at" => e.inserted_at && DateTime.to_iso8601(e.inserted_at)
            }
          end
      })

    with :ok <- Private.put(key, json, content_type: "application/json") do
      {:ok, %{key: key, count: length(entries)}}
    end
  end

  @doc "Reads an export back: its entries in log order."
  @spec read(String.t()) :: {:ok, [entry()]} | {:error, term()}
  def read(key) do
    with {:ok, json} <- Private.get(key) do
      case Jason.decode(json) do
        {:ok, %{"format" => @format, "entries" => entries}} when is_list(entries) ->
          entries(entries, key)

        _ ->
          {:error, {:not_a_replay_export, key}}
      end
    end
  end

  defp entries(entries, key) do
    kinds = Map.new(ReplayEntry.kinds(), &{to_string(&1), &1})

    Enum.reduce_while(entries, {:ok, []}, fn
      %{"kind" => kind, "key" => k} = entry, {:ok, acc}
      when is_map_key(kinds, kind) and is_map(k) ->
        parsed = %{
          kind: kinds[kind],
          key: k,
          payload: entry["payload"] || %{},
          inserted_at: entry["inserted_at"]
        }

        {:cont, {:ok, [parsed | acc]}}

      _entry, _acc ->
        {:halt, {:error, {:not_a_replay_export, key}}}
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end
end
