defmodule Gallformers.Import.GallformersFragment do
  @moduledoc """
  The gall batch of Gallformers' own statements about one Gall
  (`priv/import/GALLFORMERS_STATEMENTS.md`), for
  `Gallformers.Import.submit_gallformers_fragment/2`: a curator's range
  exclusion on the Gall page, the curation tray's Fact edits
  (`Gallformers.Curation`).

  The caller gives the Gall's summary (`Gallformers.Catalog.gall_summary/1`)
  and the Facts in the contract's form, with two placeholders the batch
  fills in: `:gall` for the Gall's ref (`"g1"`) and `{:taxon, taxon}`
  (`%{taxon_id, name, rank}`) for a taxon's ref. The batch then:

    * names the Gall as an import names it (`identified_by`): by its
      Inducer and generation, with its first Host as well when the Inducer
      is above species rank or missing — or, for a Gall with neither, by
      the first Host its statements confirm; `gallformers_gall_id` is
      checked against that;
    * declares each taxon once (`taxa[]`, by its accepted name and rank;
      with `gallformers_taxon_id` when `taxon_ids: true`), the identifying
      ones first;
    * numbers the Facts `f1`, `f2`, … in the order given.

  `{:error, :unidentified}` for a Gall it cannot name.
  """

  @species_ranks [:species, :subspecies, :variety, :form]

  @typedoc "A taxon as the Gall summary gives it."
  @type taxon :: %{
          required(:taxon_id) => integer(),
          required(:name) => String.t(),
          optional(atom()) => any()
        }

  @doc """
  The gall batch stating `facts` about the Gall `summary` describes. Options:
  `taxon_ids: true` gives each declared taxon its `gallformers_taxon_id`.
  """
  @spec gall_batch(map(), [map()], keyword()) :: {:ok, map()} | {:error, :unidentified}
  def gall_batch(summary, facts, opts \\ []) when is_list(facts),
    do: galls_batch([{summary, facts}], opts)

  @doc """
  As `gall_batch/3`, for several Galls in one batch: `entries` are
  `{summary, facts}`, each Gall's `:gall` placeholder its own ref (`g1`,
  `g2`, … in order), its Facts numbered on from the previous Gall's.
  `{:error, :unidentified}` when any of them cannot be named.
  """
  @spec galls_batch([{map(), [map()]}], keyword()) :: {:ok, map()} | {:error, :unidentified}
  def galls_batch(entries, opts \\ []) when is_list(entries) do
    galls =
      entries
      |> Enum.with_index(1)
      |> Enum.map(fn {{summary, facts}, i} ->
        {"g#{i}", summary, facts, identifying(summary, facts)}
      end)

    if Enum.any?(galls, fn {_ref, _summary, _facts, ident} -> ident == :unidentified end) do
      {:error, :unidentified}
    else
      taxa =
        galls
        |> Enum.flat_map(fn {_ref, _s, facts, {inducer, host}} ->
          Enum.reject([inducer, host], &is_nil/1) ++ named_taxa(facts)
        end)
        |> Enum.uniq_by(& &1.taxon_id)

      refs = taxa |> Enum.with_index(1) |> Map.new(fn {t, i} -> {t.taxon_id, "t#{i}"} end)

      facts =
        galls
        |> Enum.flat_map(fn {gall_ref, _s, facts, _ident} ->
          Enum.map(facts, &fill(&1, gall_ref, refs))
        end)
        |> Enum.with_index(1)
        |> Enum.map(fn {fact, i} -> Map.put(fact, "id", "f#{i}") end)

      {:ok,
       %{
         "format" => "gallformers-import",
         "format_version" => 3,
         "vocabulary_version" => vocabulary_version(),
         "batch_type" => "gall",
         "mode" => "add",
         "produced_at" => DateTime.utc_now(:second) |> DateTime.to_iso8601(),
         "producer" => %{"name" => "gallformers-admin", "version" => "1"},
         "source" => %{"gallformers" => true},
         "taxa" => Enum.map(taxa, &declared(&1, refs, opts)),
         "galls" => Enum.map(galls, &gall(&1, refs)),
         "facts" => facts
       }}
    end
  end

  # The Gall's identifying taxa: {inducer, host}, or :unidentified.
  defp identifying(summary, facts) do
    inducer = List.first(summary.inducers)
    host = if described?(inducer), do: nil, else: List.first(summary.hosts)
    host = if is_nil(inducer) and is_nil(host), do: confirmed_host(facts), else: host

    if is_nil(inducer) and is_nil(host), do: :unidentified, else: {inducer, host}
  end

  defp gall({ref, summary, _facts, {inducer, host}}, refs) do
    identified_by =
      %{}
      |> put_if("inducer", inducer && refs[inducer.taxon_id])
      |> put_if("host", host && refs[host.taxon_id])
      |> put_if(
        "generation",
        summary.generation && %{"value" => summary.generation, "as_written" => summary.generation}
      )

    %{
      "ref" => ref,
      "name_as_written" => summary.name,
      "gallformers_gall_id" => summary.gall_id,
      "identified_by" => identified_by
    }
  end

  defp described?(%{rank: rank}), do: rank in @species_ranks
  defp described?(nil), do: false

  defp confirmed_host(facts) do
    Enum.find_value(facts, fn
      %{"stance" => "confirm", "type" => "host_of", "subject" => {:taxon, taxon}} -> taxon
      _ -> nil
    end)
  end

  defp named_taxa(facts) do
    for fact <- facts, {_key, {:taxon, taxon}} <- fact, do: taxon
  end

  defp declared(taxon, refs, opts) do
    %{
      "ref" => refs[taxon.taxon_id],
      "name_as_written" => taxon.name,
      "rank" => Atom.to_string(taxon.rank)
    }
    |> put_if("gallformers_taxon_id", Keyword.get(opts, :taxon_ids) && taxon.taxon_id)
  end

  defp fill(fact, gall_ref, refs) do
    Map.new(fact, fn
      {key, :gall} -> {key, gall_ref}
      {key, {:taxon, taxon}} -> {key, refs[taxon.taxon_id]}
      other -> other
    end)
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, _key, false), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  # The vocabulary the admin writes with: the Trait vocabulary's date
  # (`priv/import/vocab/traits.json`).
  @traits Path.expand("../../../priv/import/vocab/traits.json", __DIR__)
  @external_resource @traits
  @vocabulary_version @traits
                      |> File.read!()
                      |> JSON.decode!()
                      |> Map.fetch!("vocabulary_version")

  defp vocabulary_version, do: @vocabulary_version
end
