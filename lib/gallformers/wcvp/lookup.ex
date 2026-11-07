defmodule Gallformers.Wcvp.Lookup do
  @moduledoc """
  Search and lookup functions for the WCVP secondary database.

  All queries use `Gallformers.Repo.WCVP` against the `wcvp_names`
  and `wcvp_distributions` tables. Functions return empty results
  (not errors) when the repo is unavailable.
  """

  @behaviour Gallformers.Wcvp.LookupBehaviour

  require Logger

  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Wcvp.{WcvpDistribution, WcvpName}

  # Names or IDs per query in the bulk lookups.
  @bulk_chunk 1000

  @doc """
  Returns the built_at timestamp from the WCVP database meta table.
  Returns nil if the repo is unavailable or the meta table doesn't exist.
  """
  @impl true
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
  @impl true
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

  Uses case-insensitive prefix matching via `lower()` + `LIKE`
  (optimized for the `text_pattern_ops` index on `lower(taxon_name)`).
  Returns a list of WcvpName structs.

  ## Options

    * `:limit` - maximum results to return (default 20)
    * `:include_synonyms` - include non-Accepted records (default false)

  Returns an empty list if the repo is unavailable.
  """
  @impl true
  @spec search(String.t(), keyword()) :: [WcvpName.t()]
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    include_synonyms = Keyword.get(opts, :include_synonyms, false)
    pattern = "#{String.downcase(query)}%"

    base =
      from(n in name_query(),
        where: like(fragment("lower(?)", n.taxon_name), ^pattern),
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
  anywhere in the name (case-insensitive via `ilike`). This handles
  subspecies, varieties, and partial matches.

  ## Options

    * `:limit` - maximum results to return (default 20)
    * `:include_synonyms` - include non-Accepted records (default false)

  Returns an empty list if the repo is unavailable.
  """
  @impl true
  @spec search_contains(String.t(), keyword()) :: [WcvpName.t()]
  def search_contains(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    include_synonyms = Keyword.get(opts, :include_synonyms, false)

    terms =
      query
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&"%#{&1}%")

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
        from(n in q, where: ilike(n.taxon_name, ^pattern))
      end)

    Repo.WCVP.all(query)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Finds a WCVP accepted name record by exact species name match.

  Returns the matching record as a WcvpName struct or nil if no match found.
  Only matches accepted names.
  """
  @impl true
  @spec match_by_name(String.t(), keyword()) :: WcvpName.t() | nil
  def match_by_name(name, opts \\ []) do
    with_retry("match_by_name(#{name})", fn -> do_match_by_name(name, opts) end)
  end

  defp do_match_by_name(name, opts) do
    normalized_name = String.downcase(name)

    case Repo.WCVP.one(
           from(n in name_query(),
             where:
               fragment("lower(?)", n.taxon_name) == ^normalized_name and
                 n.taxon_status == "Accepted",
             limit: 1,
             select_merge: %{taxon_status: n.taxon_status}
           )
         ) do
      %WcvpName{} = accepted ->
        accepted

      nil ->
        if Keyword.get(opts, :resolve_synonyms, false) do
          resolve_synonym_by_name(normalized_name)
        end
    end
  end

  defp resolve_synonym_by_name(normalized_name) do
    case Repo.WCVP.one(
           from(n in WcvpName,
             where:
               fragment("lower(?)", n.taxon_name) == ^normalized_name and
                 n.taxon_status == "Synonym",
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

  Returns a WcvpName struct, with its `:taxon_status` and
  `:accepted_plant_name_id`, and with `:native_distribution` and
  `:introduced_distribution` virtual fields populated (each a list of
  area_code_l3 strings). Returns nil if not found or repo unavailable.
  """
  @impl true
  @spec get(String.t()) :: WcvpName.t() | nil
  def get(plant_name_id) do
    with_retry("get(#{plant_name_id})", fn ->
      case Repo.WCVP.one(
             from(n in name_query(),
               where: n.plant_name_id == ^plant_name_id,
               select_merge: %{
                 taxon_status: n.taxon_status,
                 accepted_plant_name_id: n.accepted_plant_name_id
               }
             )
           ) do
        nil ->
          nil

        %WcvpName{} = name ->
          distributions =
            from(d in WcvpDistribution,
              where:
                d.plant_name_id == ^plant_name_id and
                  d.extinct == "0" and d.location_doubtful == "0",
              order_by: d.area_code_l3,
              select: %{area_code_l3: d.area_code_l3, introduced: d.introduced}
            )
            |> Repo.WCVP.all()

          {introduced, native} = Enum.split_with(distributions, &(&1.introduced == "1"))

          %{
            name
            | native_distribution: Enum.map(native, & &1.area_code_l3),
              introduced_distribution: Enum.map(introduced, & &1.area_code_l3)
          }
      end
    end)
  end

  @doc """
  Resolves synonyms by looking up the accepted name for a given plant_name_id.

  If the record's `accepted_plant_name_id` differs from its own `plant_name_id`
  (i.e., it's a synonym), returns the accepted name record as a WcvpName struct.
  Returns `nil` if the record is already accepted, not found, or the repo is unavailable.
  """
  @impl true
  @spec get_accepted_name(String.t()) :: WcvpName.t() | nil
  def get_accepted_name(plant_name_id) do
    case Repo.WCVP.one(
           from(n in WcvpName,
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
            select_merge: %{
              taxon_status: n.taxon_status,
              accepted_plant_name_id: n.accepted_plant_name_id
            }
          )
        )
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc """
  The records with these `plant_name_id`s, whatever their status (no
  distributions): each with its `taxon_name`, `taxon_rank`, `taxon_status`,
  `accepted_plant_name_id` and `taxon_authors`. Raises when the repo is
  unavailable (check `available?/0` first), so a bulk caller never takes
  "unavailable" for "not held".
  """
  @impl true
  @spec get_names([String.t()]) :: [WcvpName.t()]
  def get_names(plant_name_ids) when is_list(plant_name_ids) do
    plant_name_ids
    |> Enum.uniq()
    |> Enum.chunk_every(@bulk_chunk)
    |> Enum.flat_map(fn ids ->
      Repo.WCVP.all(from(n in authorship_query(), where: n.plant_name_id in ^ids))
    end)
  end

  @doc """
  Every record whose `taxon_name` is one of `names`, ignoring case,
  whatever its status (homonyms, synonyms and illegitimate names
  included), as `get_names/1` gives them. Raises when the repo is
  unavailable.
  """
  @impl true
  @spec find_names([String.t()]) :: [WcvpName.t()]
  def find_names(names) when is_list(names) do
    names
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.chunk_every(@bulk_chunk)
    |> Enum.flat_map(fn lowered ->
      Repo.WCVP.all(
        from(n in authorship_query(), where: fragment("lower(?)", n.taxon_name) in ^lowered)
      )
    end)
  end

  defp authorship_query do
    from(n in WcvpName,
      select: %WcvpName{
        plant_name_id: n.plant_name_id,
        taxon_name: n.taxon_name,
        taxon_rank: n.taxon_rank,
        taxon_status: n.taxon_status,
        accepted_plant_name_id: n.accepted_plant_name_id,
        taxon_authors: n.taxon_authors
      }
    )
  end

  # Base query selecting core name fields as a WcvpName struct.
  # Callers use select_merge to add taxon_status, accepted_plant_name_id, etc.
  defp name_query do
    from(n in WcvpName,
      select: %WcvpName{
        plant_name_id: n.plant_name_id,
        taxon_name: n.taxon_name,
        taxon_rank: n.taxon_rank,
        family: n.family,
        genus: n.genus,
        species: n.species,
        taxon_authors: n.taxon_authors,
        powo_id: n.powo_id
      }
    )
  end

  # Runs a WCVP query function with a single retry on transient DB errors.
  # After idle periods, pool connections can go stale; the first query fails
  # but the pool reconnects, so the retry succeeds.
  defp with_retry(label, fun) do
    fun.()
  rescue
    e ->
      Logger.warning("WCVP #{label} failed (#{Exception.message(e)}), retrying once")

      try do
        fun.()
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
  catch
    :exit, reason ->
      Logger.warning("WCVP #{label} exit (#{inspect(reason)}), retrying once")

      try do
        fun.()
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
  end
end
