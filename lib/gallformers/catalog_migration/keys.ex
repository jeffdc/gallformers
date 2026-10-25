defmodule Gallformers.CatalogMigration.Keys do
  @moduledoc """
  The identification keys' couplets, re-targeted (`9449` §1 and Task 17;
  `b5bd` M2).

  A key's couplets (`keys.couplets`, JSON) end in taxon destinations whose
  `species_id` (one ID or a list) the key pages link as `/gall/:id`. Galls
  keep their species IDs, so a link to a migrated Gall stays as it is. Only
  the other links need a decision: a link to a plant (its `/gall/` page
  never existed), to an excluded non-gall, or to no species at all.

  `priv/catalog_migration/keys.csv`: `key, couplet, lead, species_id,
  decision, target_gall_id, note`, one row per such link — `key` is the
  key's slug, `couplet` its number, `lead` the lead's position in it from
  1. `drop` removes the link (the destination keeps its name, shown as
  plain text — as a genus or family is); `retarget` replaces it with the
  migrated Gall `target_gall_id`.

  The table is kept, so the couplets are rewritten in place. Applying a
  decision twice changes nothing: a link already dropped or re-targeted is
  no longer there to decide.
  """

  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Repo

  @input "keys.csv"
  @columns ~w(key couplet lead destination species_id species_name why decision target_gall_id note applied)

  @type decision :: %{decision: :drop | :retarget, target: integer() | nil, note: String.t()}
  @type key :: {String.t(), String.t(), pos_integer(), integer()}

  @doc "Reads the decisions, by `{key slug, couplet, lead, species_id}`."
  @spec load(String.t()) :: {:ok, %{key() => decision()}} | {:error, String.t()}
  def load(path) do
    with {:ok, rows} <-
           Curated.read(path, ~w(key couplet lead species_id decision), ~w(target_gall_id note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse/1),
         {:ok, indexed} <- Curated.index(path, parsed, &elem(&1, 0)) do
      {:ok, Map.new(indexed, fn {key, {_key, decision}} -> {key, decision} end)}
    end
  end

  defp parse(row) do
    with {:ok, lead} <- Curated.integer(row["lead"], "lead"),
         {:ok, species_id} <- Curated.integer(row["species_id"], "species_id"),
         {:ok, decision} <- decision(row["decision"], row["target_gall_id"]) do
      {:ok,
       {{row["key"], row["couplet"], lead, species_id}, Map.put(decision, :note, row["note"])}}
    end
  end

  defp decision("drop", _target), do: {:ok, %{decision: :drop, target: nil}}

  defp decision("retarget", target) do
    case Curated.integer(target, "target_gall_id") do
      {:ok, id} -> {:ok, %{decision: :retarget, target: id}}
      {:error, message} -> {:error, "retarget needs a target_gall_id: #{message}"}
    end
  end

  defp decision(other, _target),
    do: {:error, "decision must be drop or retarget, got #{inspect(other)}"}

  @doc """
  Reports every key link that is not to a migrated Gall (`gall_ids`) and
  applies the decisions, rewriting the couplets that change.
  """
  @spec run(%{key() => decision()}, %{integer() => true}, Report.t()) :: Report.t()
  def run(decisions, gall_ids, report) do
    keys = Old.rows("SELECT id, slug, couplets FROM keys ORDER BY id")
    decoded = for key <- keys, do: Map.put(key, :couplets, decode(key.couplets))
    species = species(decoded)

    {rows, rewritten} =
      Enum.flat_map_reduce(decoded, 0, fn key, rewritten ->
        {couplets, rows} = retarget(key, decisions, gall_ids, species)

        if couplets != key.couplets do
          Repo.query!("UPDATE keys SET couplets = $1 WHERE id = $2", [
            Jason.encode!(couplets),
            key.id
          ])

          {rows, rewritten + 1}
        else
          {rows, rewritten}
        end
      end)

    report
    |> Report.curation("keys", @columns, Enum.map(rows, &worksheet_row/1))
    |> Report.pending(@input, for(%{applied: "pending" <> _} = r <- rows, do: pending(r)))
    |> Report.problems(
      "key couplets that are not JSON",
      for(%{couplets: :error, slug: slug} <- decoded, do: slug)
    )
    |> Report.count("Key links not to a Gall", length(rows))
    |> Report.count("Key links dropped", Enum.count(rows, &(&1.applied == "dropped")))
    |> Report.count("Key links re-targeted", Enum.count(rows, &(&1.applied =~ "re-targeted")))
    |> Report.count("Keys rewritten", rewritten)
  end

  defp decode(json) do
    case Jason.decode(json || "") do
      {:ok, couplets} when is_map(couplets) -> couplets
      _ -> :error
    end
  end

  defp species(decoded) do
    ids =
      for %{couplets: couplets} <- decoded,
          is_map(couplets),
          {_number, couplet} <- couplets,
          lead <- couplet["leads"] || [],
          id <- ids(lead["destination"]),
          uniq: true,
          do: id

    "SELECT id, name, taxoncode FROM species WHERE id = ANY($1::bigint[])"
    |> Old.rows([ids])
    |> Map.new(&{&1.id, &1})
  end

  defp ids(%{"type" => "taxon", "species_id" => id}) when is_integer(id), do: [id]
  defp ids(%{"type" => "taxon", "species_id" => ids}) when is_list(ids), do: ids
  defp ids(_destination), do: []

  # The key's couplets with the decided links changed, and a row for each
  # link that is not to a migrated Gall.
  defp retarget(%{couplets: :error} = key, _decisions, _gall_ids, _species),
    do: {key.couplets, []}

  defp retarget(key, decisions, gall_ids, species) do
    key.couplets
    |> Enum.sort_by(fn {number, _} -> number |> Integer.parse() |> elem(0) end)
    |> Enum.map_reduce([], fn {number, couplet}, rows ->
      {leads, lead_rows} =
        (couplet["leads"] || [])
        |> Enum.with_index(1)
        |> Enum.map_reduce([], fn {lead, index}, acc ->
          {lead, new_rows} =
            lead_links(lead, {key.slug, number, index}, decisions, gall_ids, species)

          {lead, acc ++ new_rows}
        end)

      {{number, Map.put(couplet, "leads", leads)}, rows ++ lead_rows}
    end)
    |> then(fn {couplets, rows} -> {Map.new(couplets), rows} end)
  end

  defp lead_links(lead, {slug, number, index}, decisions, gall_ids, species) do
    destination = lead["destination"]

    {kept, rows} =
      destination
      |> ids()
      |> Enum.map_reduce([], fn id, rows ->
        if Map.has_key?(gall_ids, id) do
          {[id], rows}
        else
          key = {slug, number, index, id}
          {ids, applied} = decide(decisions[key], id, gall_ids)

          row = %{
            key: key,
            destination: destination["name"],
            species: species[id],
            decision: decisions[key],
            applied: applied
          }

          {ids, rows ++ [row]}
        end
      end)

    case rows do
      [] -> {lead, []}
      _ -> {Map.put(lead, "destination", put_ids(destination, kept)), rows}
    end
  end

  defp decide(nil, id, _gall_ids), do: {[id], "pending: needs a decision"}
  defp decide(%{decision: :drop}, _id, _gall_ids), do: {[], "dropped"}

  defp decide(%{decision: :retarget, target: target}, id, gall_ids) do
    if Map.has_key?(gall_ids, target),
      do: {[target], "re-targeted to #{target}"},
      else: {[id], "pending: #{target} is not a migrated Gall"}
  end

  defp put_ids(destination, ids) do
    case ids |> List.flatten() |> Enum.uniq() do
      [] -> Map.put(destination, "species_id", nil)
      [one] -> Map.put(destination, "species_id", one)
      several -> Map.put(destination, "species_id", several)
    end
  end

  defp why(nil), do: "no such species"
  defp why(%{taxoncode: "gall"}), do: "non-gall (excluded)"
  defp why(%{taxoncode: "plant"}), do: "plant"
  defp why(%{taxoncode: code}), do: "#{code} species"

  defp pending(%{key: {slug, number, index, id} = key} = row) do
    {key,
     "#{slug} couplet #{number} lead #{index} → #{row.destination}: species #{id} " <>
       "(#{why(row.species)}): #{String.replace_prefix(row.applied, "pending: ", "")}"}
  end

  defp worksheet_row(%{key: {slug, number, index, id}} = row) do
    decision = row.decision || %{}

    %{
      "key" => slug,
      "couplet" => number,
      "lead" => index,
      "destination" => row.destination,
      "species_id" => id,
      "species_name" => row.species && row.species.name,
      "why" => why(row.species),
      "decision" => decision[:decision],
      "target_gall_id" => decision[:target],
      "note" => decision[:note],
      "applied" => row.applied
    }
  end
end
