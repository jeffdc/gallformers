defmodule Gallformers.Import.SourceEdits do
  @moduledoc """
  The Source editor's edits (matter a856, Task 10), made through
  `Gallformers.Sources` and recorded in the replay log as `:source_edit`
  entries, so an edit made during the backscan on preview is made again
  after the cutover data migration (`Gallformers.Import.Replay`).

  Each edit runs in one transaction audited as the editor: the Source is
  changed, the standings of the Facts it attributes are recomputed
  (`Gallformers.Facts.recompute_for_source/2` — a retraction cancels all of
  its stances, undoing one restores them) and the entry is appended. The
  entry's key names the Source by its title before the edit
  (`Gallformers.Import.StableRef.source/1`):

    * `{:update_details, source, attrs}` — `%{"op" => "update_details"}`,
      payload `%{"attrs" => changed}`: the fields the edit changed, as
      `Gallformers.Sources.Source.changeset/2` takes them (the authored date
      as its partial date; the license value and canonical link follow).
    * `{:retract, source, notice, date}` — `%{"op" => "retract"}`, payload
      the notice's stable reference and the ISO date.
    * `{:unretract, source}` — `%{"op" => "unretract"}`.

  Creating a Source from a citation entered on the spot (`record_create/2`,
  matter `f923` Task 8) is `%{"op" => "create"}`, keyed by the new title,
  payload `%{"attrs" => %{"title", "authors", "authored", "doi"}}`; replay
  creates it again unless a Source has that title.
  """

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.StableRef
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Sources.Source

  @typedoc "A Source, or its ID."
  @type source_ref :: Source.t() | integer()

  @typedoc "An edit of the Source editor."
  @type edit ::
          {:update_details, source_ref(), map()}
          | {:retract, source_ref(), source_ref(), Date.t()}
          | {:unretract, source_ref()}

  # Fields set from others, left out of the logged changes.
  @derived [:authored_date, :authored_precision, :license_value]

  @doc """
  Makes `edit` and records it in the replay log, in one transaction
  (`{:create, attrs}` is `record_create/2`).
  """
  @spec record(Actor.t(), edit() | {:create, map()}) ::
          {:ok, Source.t()} | {:error, Ecto.Changeset.t() | term()}
  def record(%Actor{} = actor, {:create, attrs}), do: record_create(actor, attrs)

  def record(%Actor{} = actor, edit) do
    Audit.transaction(actor, "import.record_source_edit", fn ->
      source = fetch(elem(edit, 1))
      {key, payload} = entry(edit, source)

      case run(actor, edit, source) do
        {:ok, updated} ->
          {:ok, _conflicts} = Facts.recompute_for_source(actor, updated.id)
          ReplayLog.append!(:source_edit, key, payload)
          updated

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @citation_fields ~w(title authors authored doi)

  @doc """
  Creates a Source from a citation (`Gallformers.Sources.create_citation/2`:
  title, authors, date, optional DOI) and records it in the replay log, in
  one transaction audited as `actor`.
  """
  @spec record_create(Actor.t(), map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def record_create(%Actor{} = actor, attrs) when is_map(attrs) do
    Audit.transaction(actor, "import.record_source_created", fn ->
      case Sources.create_citation(actor, attrs) do
        {:ok, source} ->
          payload = %{
            "attrs" => %{
              "title" => source.title,
              "authors" => source.authors,
              "authored" => Source.authored(source),
              "doi" => source.doi
            }
          }

          ReplayLog.append!(:source_edit, key("create", source), payload)
          source

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  The edit a replay log entry records, its Sources found by their stable
  references; `:done` when the entry is already made (its Source renamed by
  it, or no longer retracted).
  """
  @spec from_entry(map(), map()) :: {:ok, edit()} | :done | {:error, term()}
  def from_entry(%{"op" => "update_details", "source" => ref}, %{"attrs" => attrs}) do
    case StableRef.resolve_source(ref) do
      {:ok, id} -> {:ok, {:update_details, id, attrs}}
      {:error, reason} -> if renamed_already?(attrs), do: :done, else: {:error, reason}
    end
  end

  def from_entry(%{"op" => "retract", "source" => ref}, %{"notice" => notice, "on" => on}) do
    with {:ok, id} <- StableRef.resolve_source(ref),
         {:ok, notice_id} <- StableRef.resolve_source(notice),
         {:ok, date} <- Date.from_iso8601(on) do
      {:ok, {:retract, id, notice_id, date}}
    end
  end

  def from_entry(%{"op" => "unretract", "source" => ref}, _payload) do
    with {:ok, id} <- StableRef.resolve_source(ref) do
      case Sources.get_source!(id) do
        %Source{retracted_by_id: nil} -> :done
        %Source{} -> {:ok, {:unretract, id}}
      end
    end
  end

  def from_entry(%{"op" => "create", "source" => %{"title" => title}}, %{"attrs" => attrs}) do
    if Sources.get_source_by_title(title),
      do: :done,
      else: {:ok, {:create, Map.take(attrs, @citation_fields)}}
  end

  def from_entry(key, _payload), do: {:error, {:unknown_source_edit, key}}

  defp renamed_already?(%{"title" => title}) when is_binary(title),
    do: Sources.get_source_by_title(title) != nil

  defp renamed_already?(_attrs), do: false

  defp fetch(%Source{id: id}), do: Sources.get_source!(id)
  defp fetch(id) when is_integer(id), do: Sources.get_source!(id)

  defp entry({:update_details, _source, attrs}, source) do
    changed =
      source
      |> Sources.change_source(attrs)
      |> Map.fetch!(:changes)
      |> Map.drop(@derived)
      |> Map.new(fn {field, value} -> {to_string(field), loggable(value)} end)

    {key("update_details", source), %{"attrs" => changed}}
  end

  defp entry({:retract, _source, notice, %Date{} = date}, source) do
    {key("retract", source),
     %{"notice" => StableRef.source(fetch(notice).id), "on" => Date.to_iso8601(date)}}
  end

  defp entry({:unretract, _source}, source), do: {key("unretract", source), %{}}

  defp key(op, source), do: %{"op" => op, "source" => StableRef.source(source.id)}

  defp loggable(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp loggable(value), do: value

  defp run(actor, {:update_details, _source, attrs}, source),
    do: Sources.update_source_details(actor, source, attrs)

  defp run(actor, {:retract, _source, notice, date}, source),
    do: Sources.retract_source(actor, source, fetch(notice), date)

  defp run(actor, {:unretract, _source}, source), do: Sources.unretract_source(actor, source)
end
