defmodule Gallformers.Import.StableRef do
  @moduledoc """
  Stable references for the replay log (`9449` §5, Task 14): what survives
  the cutover data migration when database IDs do not.

    * **Taxon** — `%{"name", "rank", "kingdom"}`: its accepted name at the
      time, with rank and kingdom (names are not globally unique). The log
      is replayed in order, so a taxon renamed earlier in the log is found
      by its new name later.
    * **Gall** — a Gall an import batch created is `%{"batch_id", "ref"}`
      (the producer's `batch_id` and the Gall's ref in it); any other Gall
      is `%{"id"}`: migrated Galls keep their species IDs.
    * **Source** — `%{"title"}`: titles are unique, migrated Sources keep
      them, and an importer-created Source is created again with the same
      title when its package is replayed.

  A decision (`Gallformers.Import.Queue`) is stored with its
  `"taxon_id"`, `"gall_id"` and `"source_id"` replaced by `"taxon"`,
  `"gall"` and `"source"` references.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog
  alias Gallformers.Import.Batch
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @doc "A taxon's stable reference."
  @spec taxon(integer()) :: map()
  def taxon(id) when is_integer(id) do
    taxon = Taxa.get_taxon!(id)

    %{
      "name" => Taxa.accepted_name(taxon),
      "rank" => to_string(taxon.rank),
      "kingdom" => taxon.kingdom
    }
  end

  @doc "The taxon a stable reference names: one taxon with that accepted name."
  @spec resolve_taxon(map()) :: {:ok, integer()} | {:error, term()}
  def resolve_taxon(%{"name" => name, "rank" => rank} = ref) do
    found =
      case Taxa.resolve_name(name, rank: String.to_existing_atom(rank), kingdom: ref["kingdom"]) do
        {:ok, taxon} -> [taxon]
        {:ambiguous, taxa} -> taxa
        :none -> []
      end

    case Enum.filter(found, &(&1.matched_name.status == :accepted)) do
      [taxon] -> {:ok, taxon.id}
      [] -> {:error, {:taxon_not_found, ref}}
      _several -> {:error, {:taxon_ambiguous, ref}}
    end
  end

  @doc "A Gall's stable reference."
  @spec gall(integer()) :: map()
  def gall(id) when is_integer(id) do
    created =
      Repo.one(
        from(s in BatchStatement,
          join: b in Batch,
          on: b.id == s.batch_id,
          where: s.kind == :gall and s.gall_id == ^id and s.method == "created",
          order_by: s.id,
          limit: 1,
          select: %{"batch_id" => b.producer_batch_id, "ref" => s.ref}
        )
      )

    created || %{"id" => id}
  end

  @doc "The Gall a stable reference names."
  @spec resolve_gall(map()) :: {:ok, integer()} | {:error, term()}
  def resolve_gall(%{"batch_id" => batch_id, "ref" => ref} = stable) do
    Repo.one(
      from(s in BatchStatement,
        join: b in Batch,
        on: b.id == s.batch_id,
        where:
          b.producer_batch_id == ^batch_id and s.kind == :gall and s.ref == ^ref and
            s.method == "created",
        select: s.gall_id
      )
    )
    |> found(stable)
  end

  def resolve_gall(%{"id" => id} = stable) do
    (Catalog.get_gall(id) && id) |> found(stable)
  end

  @doc "A Source's stable reference."
  @spec source(integer()) :: map()
  def source(id) when is_integer(id), do: %{"title" => Sources.get_source!(id).title}

  @doc "The Source a stable reference names."
  @spec resolve_source(map()) :: {:ok, integer()} | {:error, term()}
  def resolve_source(%{"title" => title} = stable) do
    case Sources.get_source_by_title(title) do
      %{id: id} -> {:ok, id}
      nil -> {:error, {:not_found, stable}}
    end
  end

  @doc "A decision with its IDs replaced by stable references."
  @spec encode_decision(map()) :: map()
  def encode_decision(decision) do
    Map.new(decision, fn
      {"taxon_id", id} -> {"taxon", taxon(id)}
      {"gall_id", id} -> {"gall", gall(id)}
      {"source_id", id} -> {"source", source(id)}
      other -> other
    end)
  end

  @doc "A decision with its stable references resolved to IDs."
  @spec decode_decision(map()) :: {:ok, map()} | {:error, term()}
  def decode_decision(decision) do
    Enum.reduce_while(decision, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case decode_pair(key, value) do
        {:ok, {k, v}} -> {:cont, {:ok, Map.put(acc, k, v)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp decode_pair("taxon", ref),
    do: with({:ok, id} <- resolve_taxon(ref), do: {:ok, {"taxon_id", id}})

  defp decode_pair("gall", ref),
    do: with({:ok, id} <- resolve_gall(ref), do: {:ok, {"gall_id", id}})

  defp decode_pair("source", ref),
    do: with({:ok, id} <- resolve_source(ref), do: {:ok, {"source_id", id}})

  defp decode_pair(key, value), do: {:ok, {key, value}}

  defp found(id, _stable) when is_integer(id), do: {:ok, id}
  defp found(_nil, stable), do: {:error, {:not_found, stable}}
end
