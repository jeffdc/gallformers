defmodule Gallformers.Wcvp.Lookup do
  @moduledoc """
  Search and lookup functions for the WCVP secondary database.

  All queries use `Gallformers.Repo.WCVP` against the raw `wcvp_names`
  and `wcvp_distributions` tables. Functions return empty results
  (not errors) when the repo is unavailable.
  """

  import Ecto.Query

  alias Gallformers.Repo

  @doc """
  Returns the built_at timestamp from the WCVP database meta table.
  Returns nil if the repo is unavailable or the meta table doesn't exist.
  """
  @spec built_at() :: DateTime.t() | nil
  def built_at do
    case Repo.WCVP.one(
           from(m in "meta",
             where: m.key == "built_at",
             select: m.value
           )
         ) do
      nil ->
        nil

      iso_string ->
        case DateTime.from_iso8601(iso_string) do
          {:ok, dt, _offset} -> dt
          _ -> nil
        end
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Returns whether the WCVP repo is started and queryable.
  """
  @spec available?() :: boolean()
  def available? do
    Repo.WCVP.query("SELECT 1")
    true
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @doc """
  Fuzzy name search on taxon_name via prefix match.

  Uses case-insensitive matching (SQLite-compatible, no ilike).
  Returns a list of maps with name fields.

  ## Options

    * `:limit` - maximum results to return (default 20)

  Returns an empty list if the repo is unavailable.
  """
  @spec search(String.t(), keyword()) :: [map()]
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    include_synonyms = Keyword.get(opts, :include_synonyms, false)
    pattern = "#{query}%"

    base =
      from(n in name_query(),
        where: like(n.taxon_name, ^pattern),
        order_by: n.taxon_name,
        limit: ^limit,
        select_merge: %{
          taxon_status: n.taxon_status,
          accepted_plant_name_id: n.accepted_plant_name_id
        }
      )

    base =
      if include_synonyms do
        base
      else
        from(n in base, where: n.taxon_status == "Accepted")
      end

    Repo.WCVP.all(base)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Contains-based name search on taxon_name.

  Splits the query on whitespace and requires each term to appear
  anywhere in the name (case-insensitive). This handles subspecies,
  varieties, and partial matches.

  ## Options

    * `:limit` - maximum results to return (default 20)

  Returns an empty list if the repo is unavailable.
  """
  @spec search_contains(String.t(), keyword()) :: [map()]
  def search_contains(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    include_synonyms = Keyword.get(opts, :include_synonyms, false)

    terms =
      query
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&"%#{String.downcase(&1)}%")

    base =
      from(n in name_query(),
        order_by: n.taxon_name,
        limit: ^limit,
        select_merge: %{
          taxon_status: n.taxon_status,
          accepted_plant_name_id: n.accepted_plant_name_id
        }
      )

    base =
      if include_synonyms do
        base
      else
        from(n in base, where: n.taxon_status == "Accepted")
      end

    query =
      Enum.reduce(terms, base, fn pattern, q ->
        from(n in q, where: like(fragment("lower(?)", n.taxon_name), ^pattern))
      end)

    Repo.WCVP.all(query)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Finds a WCVP accepted name record by exact species name match.

  Returns the matching record as a map (same shape as search results)
  or nil if no match found. Only matches accepted names.
  """
  @spec match_by_name(String.t(), keyword()) :: map() | nil
  def match_by_name(name, opts \\ []) do
    case Repo.WCVP.one(
           from(n in name_query(),
             where: n.taxon_name == ^name and n.taxon_status == "Accepted",
             limit: 1,
             select_merge: %{taxon_status: n.taxon_status}
           )
         ) do
      %{} = accepted ->
        accepted

      nil ->
        if Keyword.get(opts, :resolve_synonyms, false) do
          resolve_synonym_by_name(name)
        end
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp resolve_synonym_by_name(name) do
    case Repo.WCVP.one(
           from(n in "wcvp_names",
             where: n.taxon_name == ^name and n.taxon_status == "Synonym",
             select: %{
               plant_name_id: n.plant_name_id,
               accepted_plant_name_id: n.accepted_plant_name_id
             },
             limit: 1
           )
         ) do
      %{accepted_plant_name_id: accepted_id} when accepted_id not in [nil, ""] ->
        Repo.WCVP.one(
          from(n in name_query(),
            where: n.plant_name_id == ^accepted_id,
            select_merge: %{taxon_status: n.taxon_status}
          )
        )

      _ ->
        nil
    end
  end

  @doc """
  Exact lookup by plant_name_id.

  Returns a map with all name fields plus `:native_distribution` and
  `:introduced_distribution` (each a list of area_code_l3 strings).
  Returns nil if not found or repo unavailable.
  """
  @spec get(String.t()) :: map() | nil
  def get(plant_name_id) do
    case Repo.WCVP.one(from(n in name_query(), where: n.plant_name_id == ^plant_name_id)) do
      nil ->
        nil

      name ->
        distributions =
          from(d in "wcvp_distributions",
            where:
              d.plant_name_id == ^plant_name_id and
                d.extinct == "0" and d.location_doubtful == "0",
            order_by: d.area_code_l3,
            select: %{area_code_l3: d.area_code_l3, introduced: d.introduced}
          )
          |> Repo.WCVP.all()

        {introduced, native} = Enum.split_with(distributions, &(&1.introduced == "1"))

        name
        |> Map.put(:native_distribution, Enum.map(native, & &1.area_code_l3))
        |> Map.put(:introduced_distribution, Enum.map(introduced, & &1.area_code_l3))
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  Resolves synonyms by looking up the accepted name for a given plant_name_id.

  If the record's `accepted_plant_name_id` differs from its own `plant_name_id`
  (i.e., it's a synonym), returns the accepted name record as a map.
  Returns `nil` if the record is already accepted, not found, or the repo is unavailable.
  """
  @spec get_accepted_name(String.t()) :: map() | nil
  def get_accepted_name(plant_name_id) do
    case Repo.WCVP.one(
           from(n in "wcvp_names",
             where: n.plant_name_id == ^plant_name_id,
             select: %{
               plant_name_id: n.plant_name_id,
               accepted_plant_name_id: n.accepted_plant_name_id
             }
           )
         ) do
      nil ->
        nil

      %{accepted_plant_name_id: accepted_id} when accepted_id in [nil, ""] ->
        nil

      %{plant_name_id: id, accepted_plant_name_id: id} ->
        # Already accepted (accepted_plant_name_id == plant_name_id)
        nil

      %{accepted_plant_name_id: accepted_id} ->
        Repo.WCVP.one(
          from(n in name_query(),
            where: n.plant_name_id == ^accepted_id,
            select_merge: %{taxon_status: n.taxon_status}
          )
        )
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # Base query with the 7 core name fields shared across all lookup functions.
  # Callers use select_merge to add taxon_status, accepted_plant_name_id, etc.
  defp name_query do
    from(n in "wcvp_names",
      select: %{
        plant_name_id: n.plant_name_id,
        taxon_name: n.taxon_name,
        family: n.family,
        genus: n.genus,
        species: n.species,
        taxon_authors: n.taxon_authors,
        powo_id: n.powo_id
      }
    )
  end
end
