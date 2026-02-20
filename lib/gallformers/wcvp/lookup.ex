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
    pattern = "#{query}%"

    from(n in "wcvp_names",
      where: fragment("lower(?) LIKE lower(?)", n.taxon_name, ^pattern),
      order_by: n.taxon_name,
      limit: ^limit,
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
    |> Repo.WCVP.all()
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Exact lookup by plant_name_id.

  Returns a map with all name fields plus `:distribution` (a list of
  area_code_l3 strings). Returns nil if not found or repo unavailable.
  """
  @spec get(String.t()) :: map() | nil
  def get(plant_name_id) do
    case Repo.WCVP.one(
           from(n in "wcvp_names",
             where: n.plant_name_id == ^plant_name_id,
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
         ) do
      nil ->
        nil

      name ->
        distributions =
          from(d in "wcvp_distributions",
            where: d.plant_name_id == ^plant_name_id,
            order_by: d.area_code_l3,
            select: d.area_code_l3
          )
          |> Repo.WCVP.all()

        Map.put(name, :distribution, distributions)
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
