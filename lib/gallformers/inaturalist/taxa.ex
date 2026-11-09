defmodule Gallformers.INaturalist.Taxa do
  @moduledoc """
  iNaturalist's taxa, read from its public API (matter `cb28`):

    * `search/1` — taxa by name (`/v1/taxa/autocomplete`, which matches
      synonyms and common names too and says which name matched), or the
      one taxon an iNaturalist link or number names;
    * `fetch/1` — one taxon with its ancestors, children and every name
      (`/v1/taxa/:id?all_names=true`), as a `Gallformers.INaturalist.Taxon`.

  Requests go through `Gallformers.INaturalist.get_json/2` (its user agent,
  retries and test stub). A search is one request, a taxon one more: well
  under iNaturalist's limits.
  """
  alias Gallformers.INaturalist
  alias Gallformers.INaturalist.Taxon

  @results 6

  @typedoc "A search result."
  @type result :: %{
          id: integer(),
          name: String.t(),
          rank: String.t(),
          common: String.t() | nil,
          matched: String.t() | nil,
          observations: non_neg_integer(),
          active?: boolean()
        }

  @taxon_url ~r{\Ahttps?://(?:www\.)?inaturalist\.org/taxa/(\d+)}

  @doc """
  The taxa iNaturalist has for `query`: a name (at most #{@results}, as
  iNaturalist orders them, each with the name that `matched`), or the taxon
  an iNaturalist link or number names (`matched` nil; none when it has no
  such taxon). A blank query asks nothing.
  """
  @spec search(String.t()) :: {:ok, [result()]} | {:error, term()}
  def search(query) when is_binary(query) do
    query = String.trim(query)

    cond do
      query == "" ->
        {:ok, []}

      match?({:ok, _id}, parse_taxon_id(query)) ->
        {:ok, id} = parse_taxon_id(query)
        by_id(id)

      true ->
        by_name(query)
    end
  end

  defp by_name(query) do
    case INaturalist.get_json("taxa/autocomplete", q: query, per_page: @results) do
      {:ok, %{"results" => results}} when is_list(results) -> {:ok, Enum.map(results, &result/1)}
      {:ok, _body} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp by_id(id) do
    case fetch(id) do
      {:ok, taxon} -> {:ok, [taxon_result(taxon)]}
      {:error, :not_found} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp result(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      rank: raw["rank"],
      common: raw["preferred_common_name"],
      matched: raw["matched_term"],
      observations: raw["observations_count"] || 0,
      active?: raw["is_active"] != false
    }
  end

  defp taxon_result(%Taxon{} = t) do
    %{
      id: t.id,
      name: t.name,
      rank: t.rank,
      common: t.common,
      matched: nil,
      observations: t.observations,
      active?: t.active?
    }
  end

  @doc """
  Taxon `id` (an integer, or its digits) with its ancestors, children and
  names. `{:error, :not_found}` when iNaturalist has no such taxon.
  """
  @spec fetch(integer() | String.t()) :: {:ok, Taxon.t()} | {:error, term()}
  def fetch(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {id, ""} -> fetch(id)
      _ -> {:error, :not_found}
    end
  end

  def fetch(id) when is_integer(id) do
    case INaturalist.get_json("taxa/#{id}", all_names: true) do
      {:ok, %{"results" => [raw | _]}} -> {:ok, parse_taxon(raw)}
      {:ok, %{"results" => []}} -> {:error, :not_found}
      {:ok, _body} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "A taxon of iNaturalist's API response, as a `Gallformers.INaturalist.Taxon`."
  @spec parse_taxon(map()) :: Taxon.t()
  def parse_taxon(raw) when is_map(raw) do
    ancestors = Enum.map(raw["ancestors"] || [], &relative/1)

    %Taxon{
      id: raw["id"],
      name: raw["name"],
      rank: raw["rank"],
      rank_level: raw["rank_level"],
      active?: raw["is_active"] != false,
      replaced_by: raw["current_synonymous_taxon_ids"] || [],
      common: raw["preferred_common_name"],
      observations: raw["observations_count"] || 0,
      kingdom: kingdom(raw, ancestors),
      ancestors: ancestors,
      children: Enum.map(raw["children"] || [], &relative/1),
      names:
        for(
          %{"name" => name, "lexicon" => lexicon} <- raw["names"] || [],
          is_binary(name),
          do: %{name: name, lexicon: lexicon}
        ),
      url: "https://www.inaturalist.org/taxa/#{raw["id"]}"
    }
  end

  # A kingdom is its own kingdom.
  defp kingdom(%{"rank" => "kingdom", "name" => name}, _ancestors), do: name

  defp kingdom(_raw, ancestors) do
    case Enum.find(ancestors, &(&1.rank == "kingdom")) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp relative(raw) do
    %{id: raw["id"], name: raw["name"], rank: raw["rank"], active?: raw["is_active"] != false}
  end

  @doc ~S|The iNaturalist taxon ID in a link to its page ("…/taxa/1449402-Arguti") or digits.|
  @spec parse_taxon_id(String.t()) :: {:ok, integer()} | :error
  def parse_taxon_id(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      input =~ ~r/\A\d+\z/ -> {:ok, String.to_integer(input)}
      match = Regex.run(@taxon_url, input) -> {:ok, match |> Enum.at(1) |> String.to_integer()}
      true -> :error
    end
  end
end
