defmodule Gallformers.Import.TaxonomyEdits do
  @moduledoc """
  The taxonomy admin's edits beyond the editorial tree (`a856` Task 8),
  recorded in the replay log as `:taxonomy_edit` entries so an edit made on
  preview is made again after the cutover data migration
  (`Gallformers.Import.Replay`). Each names its taxon by its stable
  reference (`Gallformers.Import.StableRef.taxon/1`), taken before the
  edit.

  Through `Gallformers.Import.record_taxonomy_edit/2` (one edit, one
  entry, logged after it succeeds):

    * `{:update_editorial, taxon, attrs}` — `"update_editorial"`, payload
      the flags given (`"datacomplete"`, `"abundance_id"`; abundance IDs are
      kept by the data migration)
    * `{:remove_synonym, name}` — `"remove_synonym"`, keyed by the taxon and
      the synonym's name, payload its `"sensu"`
    * `{:remove_common_name, name}` — `"remove_common_name"`, keyed by the
      taxon and the name
    * `{:delete_taxon, taxon}` — `"delete_taxon"`
    * `{:set_host_range, taxon, entries}` — `"set_host_range"`, payload
      `"places"`: each place's code, precision and distribution (place
      codes are kept by the data migration)
    * `{:set_wcvp, taxon, attrs}` — `"set_wcvp"`, payload the WCVP link's
      fields as set

  Through `Gallformers.Import.record_wcvp_edit/2`, the WCVP actions, whose
  outcome depends on WCVP's data at the time: each is logged as the state
  it left, so replaying it does not ask WCVP again — a `"set_wcvp"` entry
  per plant whose link it touched, and for a sync first a
  `"set_host_range"` entry with the range it wrote:

    * `{:match, taxon}` — `Gallformers.Ranges.Wcvp.match/2`
    * `{:sync, taxon}`, `{:sync, taxon, ref_data}` — `Gallformers.Ranges.Wcvp.sync/3`
    * `{:ignore, taxon_ids}`, `{:clear_match_status, taxon_ids}`,
      `{:confirm_ranges, taxon_ids}` — the bulk review's actions
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.StableRef
  alias Gallformers.Ranges
  alias Gallformers.Ranges.TaxonWcvp
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.TaxonName

  @typedoc "An edit `Gallformers.Import.record_taxonomy_edit/2` takes here."
  @type edit ::
          {:update_editorial, Taxa.taxon_ref(), map()}
          | {:remove_synonym, TaxonName.t() | integer()}
          | {:remove_common_name, CommonName.t() | integer()}
          | {:delete_taxon, Taxa.taxon_ref()}
          | {:set_host_range, Taxa.taxon_ref(), [Ranges.taxon_place()]}
          | {:set_wcvp, Taxa.taxon_ref(), map()}

  @typedoc "A WCVP action (`Gallformers.Import.record_wcvp_edit/2`)."
  @type wcvp_edit ::
          {:match, Taxa.taxon_ref()}
          | {:sync, Taxa.taxon_ref()}
          | {:sync, Taxa.taxon_ref(), Wcvp.ref_data()}
          | {:ignore, [integer()]}
          | {:clear_match_status, [integer()]}
          | {:confirm_ranges, [integer()]}

  @ops ~w(update_editorial remove_synonym remove_common_name delete_taxon set_host_range set_wcvp)
  @link_fields [:wcvp_id, :powo_id, :wcvp_match_status, :range_confirmed, :wcvp_synced_at]

  @doc "Whether `Gallformers.Import.record_taxonomy_edit/2` takes `edit` here."
  @spec handles?(term()) :: boolean()
  def handles?(edit) when is_tuple(edit), do: Atom.to_string(elem(edit, 0)) in @ops
  def handles?(_edit), do: false

  @doc """
  The entry's stable key and payload, taken before the edit. A name to
  remove that does not exist rolls the transaction back with
  `:not_found`.
  """
  @spec entry(edit()) :: {map(), map()}
  def entry({:update_editorial, taxon, attrs}) do
    payload =
      for field <- [:datacomplete, :abundance_id],
          Map.has_key?(attrs, field),
          into: %{},
          do: {Atom.to_string(field), attrs[field]}

    {key("update_editorial", taxon), payload}
  end

  def entry({:remove_synonym, name}) do
    %TaxonName{} = found = Repo.get(TaxonName, row_id(name)) || Repo.rollback(:not_found)

    {Map.put(key("remove_synonym", found.taxon_id), "name", found.name),
     %{"sensu" => found.sensu}}
  end

  def entry({:remove_common_name, name}) do
    %CommonName{} = found = Repo.get(CommonName, row_id(name)) || Repo.rollback(:not_found)
    {Map.put(key("remove_common_name", found.taxon_id), "name", found.name), %{}}
  end

  def entry({:delete_taxon, taxon}), do: {key("delete_taxon", taxon), %{}}

  def entry({:set_host_range, taxon, entries}),
    do: {key("set_host_range", taxon), %{"places" => places_payload(entries)}}

  def entry({:set_wcvp, taxon, attrs}), do: {key("set_wcvp", taxon), link_payload(attrs)}

  @doc "Makes the edit."
  @spec run(Actor.t(), edit()) :: {:ok, term()} | {:error, term()}
  def run(actor, {:update_editorial, taxon, attrs}),
    do: Taxa.update_editorial(actor, taxon, attrs)

  def run(actor, {:remove_synonym, name}), do: Taxa.remove_synonym(actor, name)
  def run(actor, {:remove_common_name, name}), do: Taxa.remove_common_name(actor, name)
  def run(actor, {:delete_taxon, taxon}), do: Taxa.delete_taxon(actor, taxon)

  def run(actor, {:set_host_range, taxon, entries}),
    do: Ranges.update_taxon_places(actor, taxon, entries)

  def run(actor, {:set_wcvp, taxon, attrs}), do: Wcvp.put_link(actor, taxon, attrs)

  @doc """
  The edit a logged entry stands for, its taxa and places found by their
  stable references; `:unknown` for an op not handled here.
  """
  @spec decode(map(), map()) :: {:ok, edit()} | {:error, term()} | :unknown
  def decode(%{"op" => "update_editorial", "taxon" => taxon}, payload) do
    with {:ok, id} <- StableRef.resolve_taxon(taxon) do
      attrs = for {field, value} <- payload, into: %{}, do: {editorial_field(field), value}
      {:ok, {:update_editorial, id, attrs}}
    end
  end

  def decode(%{"op" => "remove_synonym", "taxon" => taxon, "name" => name}, payload) do
    with {:ok, id} <- StableRef.resolve_taxon(taxon) do
      case Enum.find(Taxa.list_synonyms(id), &(&1.name == name and &1.sensu == payload["sensu"])) do
        nil -> {:error, {:synonym_not_found, name}}
        synonym -> {:ok, {:remove_synonym, synonym}}
      end
    end
  end

  def decode(%{"op" => "remove_common_name", "taxon" => taxon, "name" => name}, _payload) do
    with {:ok, id} <- StableRef.resolve_taxon(taxon) do
      case Enum.find(Taxa.list_common_names(id), &(&1.name == name)) do
        nil -> {:error, {:common_name_not_found, name}}
        common -> {:ok, {:remove_common_name, common}}
      end
    end
  end

  def decode(%{"op" => "delete_taxon", "taxon" => taxon}, _payload) do
    with {:ok, id} <- StableRef.resolve_taxon(taxon), do: {:ok, {:delete_taxon, id}}
  end

  def decode(%{"op" => "set_host_range", "taxon" => taxon}, %{"places" => places}) do
    with {:ok, id} <- StableRef.resolve_taxon(taxon),
         {:ok, entries} <- place_entries(places) do
      {:ok, {:set_host_range, id, entries}}
    end
  end

  def decode(%{"op" => "set_wcvp", "taxon" => taxon}, payload) do
    with {:ok, id} <- StableRef.resolve_taxon(taxon),
         {:ok, synced_at} <- synced_at(payload["wcvp_synced_at"]) do
      attrs =
        for field <- @link_fields, Map.has_key?(payload, Atom.to_string(field)), into: %{} do
          case field do
            :wcvp_synced_at -> {field, synced_at}
            field -> {field, payload[Atom.to_string(field)]}
          end
        end

      {:ok, {:set_wcvp, id, attrs}}
    end
  end

  def decode(_key, _payload), do: :unknown

  defp editorial_field("datacomplete"), do: :datacomplete
  defp editorial_field("abundance_id"), do: :abundance_id

  defp synced_at(nil), do: {:ok, nil}

  defp synced_at(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, reason} -> {:error, {:invalid_synced_at, text, reason}}
    end
  end

  # -- WCVP actions ------------------------------------------------------------

  @doc """
  Makes a WCVP action and logs the state it left (see the module doc), in
  one transaction audited as `actor`. A match or sync that finds nothing
  still keeps (and logs) the `no_match` status it set, and returns
  `{:error, message}`.
  """
  @spec record_wcvp(Actor.t(), wcvp_edit()) :: {:ok, term()} | {:error, term()}
  def record_wcvp(%Actor{} = actor, edit) do
    Audit.transaction(actor, "import.record_wcvp_edit", fn ->
      result = run_wcvp(actor, edit)

      case result do
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        _ -> :ok
      end

      if elem(edit, 0) == :sync and match?({:ok, _}, result),
        do: log_host_range(taxon_id(elem(edit, 1)))

      for id <- wcvp_taxa(edit), link = Wcvp.get_link(id), do: log_link(id, link)
      result
    end)
    |> case do
      {:ok, {:ok, _} = ok} -> ok
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_wcvp(actor, {:match, taxon}), do: Wcvp.match(actor, taxon)
  defp run_wcvp(actor, {:sync, taxon}), do: Wcvp.sync(actor, taxon)
  defp run_wcvp(actor, {:sync, taxon, ref_data}), do: Wcvp.sync(actor, taxon, ref_data)
  defp run_wcvp(actor, {:ignore, ids}), do: Wcvp.bulk_ignore(actor, ids)
  defp run_wcvp(actor, {:clear_match_status, ids}), do: Wcvp.bulk_clear_match_status(actor, ids)
  defp run_wcvp(actor, {:confirm_ranges, ids}), do: Wcvp.bulk_confirm_ranges(actor, ids)

  defp wcvp_taxa({:match, taxon}), do: [taxon_id(taxon)]
  defp wcvp_taxa({:sync, taxon}), do: [taxon_id(taxon)]
  defp wcvp_taxa({:sync, taxon, _ref_data}), do: [taxon_id(taxon)]
  defp wcvp_taxa({_bulk, ids}), do: Enum.uniq(ids)

  defp log_host_range(taxon_id) do
    entries =
      for p <- Ranges.get_places_for_taxon_with_precision(taxon_id),
          do: {p.place_id, p.precision, p.distribution_type}

    {key, payload} = entry({:set_host_range, taxon_id, entries})
    ReplayLog.append!(:taxonomy_edit, key, payload)
  end

  defp log_link(taxon_id, %TaxonWcvp{} = link) do
    {key, payload} = entry({:set_wcvp, taxon_id, Map.take(link, @link_fields)})
    ReplayLog.append!(:taxonomy_edit, key, payload)
  end

  # -- payloads ----------------------------------------------------------------

  defp key(op, taxon), do: %{"op" => op, "taxon" => StableRef.taxon(taxon_id(taxon))}

  defp places_payload(entries) do
    normalized = Ranges.normalize_taxon_places(entries)
    ids = Enum.map(normalized, &elem(&1, 0))

    codes =
      Repo.all(from(p in "place", where: p.id in ^ids, select: {p.id, p.code})) |> Map.new()

    for {place_id, precision, distribution} <- normalized do
      %{
        "code" => Map.fetch!(codes, place_id),
        "precision" => precision,
        "distribution_type" => distribution
      }
    end
  end

  defp place_entries(places) do
    codes = Enum.map(places, & &1["code"])

    ids =
      Repo.all(from(p in "place", where: p.code in ^codes, select: {p.code, p.id})) |> Map.new()

    case Enum.reject(codes, &Map.has_key?(ids, &1)) do
      [] ->
        {:ok, for(p <- places, do: {ids[p["code"]], p["precision"], p["distribution_type"]})}

      missing ->
        {:error, {:places_not_found, missing}}
    end
  end

  defp link_payload(attrs) do
    for field <- @link_fields, Map.has_key?(attrs, field), into: %{} do
      value =
        case attrs[field] do
          %DateTime{} = at -> DateTime.to_iso8601(at)
          value -> value
        end

      {Atom.to_string(field), value}
    end
  end

  defp taxon_id(%Taxa.Taxon{id: id}), do: id
  defp taxon_id(id) when is_integer(id), do: id

  defp row_id(%{id: id}), do: id
  defp row_id(id) when is_integer(id), do: id
end
