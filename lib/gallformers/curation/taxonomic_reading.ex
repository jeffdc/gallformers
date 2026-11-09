defmodule Gallformers.Curation.TaxonomicReading do
  @moduledoc """
  A reading fix of a Source's taxonomic statement (matter `87a1`), as the
  taxonomy batch `Gallformers.Import.submit_reading_fix/2` takes
  (`priv/import/GALLFORMERS_STATEMENTS.md`, "Fixing a reading of a
  Source"): the misread act marked `unstated`, and what the Source does say
  in its place, `replaces` it, in the Source's words (its stance, quotes
  with their stored items, pages, links, status as written).

  The fixes: `:withdraw` (any act: the Source doesn't say it),
  `{:parent, taxon_id}` (a placement under another parent) and
  `{:accepted, taxon_id}` (a synonymy of another accepted taxon). Each taxon
  is declared by Gallformers' ID, with the name the act names it by.
  """
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @traits Path.expand("../../../priv/import/vocab/traits.json", __DIR__)
  @external_resource @traits
  @vocabulary_version @traits
                      |> File.read!()
                      |> JSON.decode!()
                      |> Map.fetch!("vocabulary_version")

  @typedoc "What the Source does say."
  @type fix :: :withdraw | {:parent, integer()} | {:accepted, integer()}

  @doc """
  The taxonomy batch fixing Source `source_id`'s reading of Fact `fact_id`
  with `fix`, `why` its reason (or nil), `accept?` whether the curator
  accepts what it states. `{:error, :not_stated}` when the Source doesn't
  state it, `:not_correctable` for a fix that doesn't fit the act,
  `:unchanged` for one that changes nothing.
  """
  @spec batch(integer(), integer(), fix(), String.t() | nil, boolean()) ::
          {:ok, map()} | {:error, :not_stated | :not_correctable | :unchanged}
  def batch(source_id, fact_id, fix, why, accept?) do
    with %Attribution{} = a <- Facts.get_attribution(fact_id, source_id) || {:error, :not_stated},
         {kind, key} <- Taxa.act_fact(fact_id) || {:error, :not_correctable},
         {:ok, to} <- to(kind, key, fix) do
      a = Repo.preload(a, [:evidence, :names])
      said = said(a)

      acts =
        [Map.merge(act(kind, key, a), Map.merge(said, %{"id" => "a1", "unstated" => true}))] ++
          for(
            to <- List.wrap(to),
            do: Map.merge(act(kind, to, a), Map.merge(said, %{"id" => "a2", "replaces" => "a1"}))
          )

      declared = taxa(acts)
      by_placeholder = Map.new(declared, &{&1.placeholder, &1["ref"]})

      {:ok,
       %{
         "format" => "gallformers-import",
         "format_version" => 4,
         "vocabulary_version" => @vocabulary_version,
         "batch_type" => "taxonomy",
         "mode" => "add",
         "batch_id" => Ecto.UUID.generate(),
         "produced_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601(),
         "producer" => %{"name" => "gallformers-curation", "version" => "1"},
         "source" => %{"reading_of" => reading_of(source_id, why, accept? and to != nil)},
         "taxa" => Enum.map(declared, &Map.delete(&1, :placeholder)),
         "acts" => Enum.map(acts, &fill(&1, by_placeholder))
       }}
    end
  end

  defp to(_kind, _key, :withdraw), do: {:ok, nil}

  defp to(:placement, %{parent_id: parent}, {:parent, parent}), do: {:error, :unchanged}
  defp to(:placement, key, {:parent, id}) when is_integer(id), do: {:ok, %{key | parent_id: id}}

  defp to(:synonymy, %{accepted_taxon_id: id}, {:accepted, id}), do: {:error, :unchanged}

  defp to(:synonymy, key, {:accepted, id}) when is_integer(id),
    do: {:ok, %{key | accepted_taxon_id: id}}

  defp to(_kind, _key, _fix), do: {:error, :not_correctable}

  defp reading_of(source_id, why, accept?) do
    %{"gallformers_source_id" => source_id}
    |> put_if("why", why)
    |> put_if("accept", accept? && true)
  end

  # The Source's stance and words, carried to every act of the fix.
  defp said(a) do
    evidence =
      for e <- a.evidence do
        if(e.whole_item, do: %{"whole_item" => true}, else: %{"quote" => e.quote})
        |> put_if("gallformers_document_item_id", e.document_item_id)
        |> put_if("page", e.page)
        |> put_if("url", e.url)
        |> put_if("cites", e.cites_as_written && %{"as_written" => e.cites_as_written})
      end

    %{"stance" => Atom.to_string(a.stance), "evidence" => evidence}
    |> put_if("status_as_written", a.status_as_written)
  end

  # An act with its taxa as placeholders: `{:taxon, id}` (declared by the
  # tree's accepted name) or `{:name, …}` (by the name the act gives it).
  defp act(:placement, key, _a),
    do: %{
      "kind" => "placement",
      "taxon" => {:taxon, key.taxon_id},
      "parent" => {:taxon, key.parent_id}
    }

  defp act(:synonymy, key, a),
    do: %{
      "kind" => "synonymy",
      "name" => {:name, key.name, name_taxon(a)},
      "accepted" => {:taxon, key.accepted_taxon_id}
    }

  defp act(:name, key, _a) do
    %{"kind" => "name", "taxon" => {:name, key.name, key.taxon_id, key.rank, key.sensu}}
    |> put_if("authorship", key.authorship && %{"as_written" => key.authorship})
  end

  defp act(:common_name, key, _a),
    do: %{
      "kind" => "common_name",
      "taxon" => {:taxon, key.taxon_id},
      "common_name" => key.common_name
    }

  defp act(:split, key, _a),
    do: %{
      "kind" => "split",
      "taxon" => {:taxon, key.taxon_id},
      "into" => Enum.map(key.into_taxon_ids, &{:taxon, &1})
    }

  # The taxon a synonym name resolved to when the Source was read.
  defp name_taxon(a), do: Enum.find_value(a.names, &(&1.role == "name" && &1.taxon_id))

  # Each taxon once, `t1`, `t2`, … in order of use.
  defp taxa(acts) do
    acts
    |> Enum.flat_map(&placeholders/1)
    |> Enum.uniq()
    |> Enum.with_index(1)
    |> Enum.map(fn {placeholder, i} -> declared(placeholder, "t#{i}") end)
  end

  defp placeholders(act) do
    act
    |> Map.values()
    |> Enum.flat_map(fn
      list when is_list(list) -> Enum.filter(list, &placeholder?/1)
      value -> if placeholder?(value), do: [value], else: []
    end)
  end

  defp placeholder?(value), do: is_tuple(value) and elem(value, 0) in [:taxon, :name]

  defp declared({:taxon, id} = p, ref) do
    taxon = Taxa.get_taxon!(id)

    %{
      "ref" => ref,
      "name_as_written" => Taxa.accepted_name(taxon),
      "rank" => Atom.to_string(taxon.rank),
      "gallformers_taxon_id" => id
    }
    |> Map.put(:placeholder, p)
  end

  defp declared({:name, name, id, rank, sensu} = p, ref) do
    %{"ref" => ref, "name_as_written" => name, "rank" => to_string(rank)}
    |> put_if("sensu", sensu)
    |> put_if("gallformers_taxon_id", id)
    |> Map.put(:placeholder, p)
  end

  defp declared({:name, name, id} = p, ref) do
    rank = if id, do: Atom.to_string(Taxa.get_taxon!(id).rank), else: "species"

    %{"ref" => ref, "name_as_written" => name, "rank" => rank}
    |> put_if("gallformers_taxon_id", id)
    |> Map.put(:placeholder, p)
  end

  # The act with its placeholders as the declared taxa's refs.
  defp fill(act, by_placeholder) do
    Map.new(act, fn
      {key, list} when is_list(list) ->
        {key, Enum.map(list, &Map.get(by_placeholder, &1, &1))}

      {key, value} ->
        {key, Map.get(by_placeholder, value, value)}
    end)
  end

  defp put_if(map, _key, falsy) when falsy in [nil, false], do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
