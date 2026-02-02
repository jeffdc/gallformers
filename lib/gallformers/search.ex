defmodule Gallformers.Search do
  @moduledoc """
  The Search context.

  Provides functions for searching across species, hosts, and other entities.
  """

  import Ecto.Query

  alias Gallformers.Glossaries.Glossary
  alias Gallformers.Places.Place
  alias Gallformers.Repo
  alias Gallformers.Search.Ranking
  alias Gallformers.Sources.Source
  alias Gallformers.Species.{Alias, GallTraits, Species}
  alias Gallformers.Taxonomy.Taxonomy

  @doc """
  Searches galls by name (partial match).
  Returns the same fields as Species.list_galls for API compatibility.
  """
  @spec search_galls(String.t()) :: [map()]
  def search_galls(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      join: gt in GallTraits,
      on: gt.species_id == s.id,
      left_join: a in Gallformers.Species.Abundance,
      on: s.abundance_id == a.id,
      where: s.taxoncode == "gall" and fragment("lower(?) LIKE ?", s.name, ^search_term),
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete,
        abundance_id: s.abundance_id,
        abundance_name: a.abundance,
        detachable: gt.detachable,
        undescribed: gt.undescribed
      }
    )
    |> Repo.all()
  end

  @doc """
  Searches galls by name with pagination.
  Returns the same fields as Species.list_galls_paginated for API compatibility.
  """
  @spec search_galls_paginated(String.t(), integer(), integer()) :: [map()]
  def search_galls_paginated(query, limit, offset) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      join: gt in GallTraits,
      on: gt.species_id == s.id,
      left_join: a in Gallformers.Species.Abundance,
      on: s.abundance_id == a.id,
      where: s.taxoncode == "gall" and fragment("lower(?) LIKE ?", s.name, ^search_term),
      order_by: s.name,
      limit: ^limit,
      offset: ^offset,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete,
        abundance_id: s.abundance_id,
        abundance_name: a.abundance,
        detachable: gt.detachable,
        undescribed: gt.undescribed
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of galls matching a search query.
  """
  @spec count_search_galls(String.t()) :: integer()
  def count_search_galls(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      where: s.taxoncode == "gall" and fragment("lower(?) LIKE ?", s.name, ^search_term),
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Searches hosts by name (partial match).
  Returns fields expected by the host API controller.
  """
  @spec search_hosts(String.t()) :: [map()]
  def search_hosts(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      where: s.taxoncode == "plant" and fragment("lower(?) LIKE ?", s.name, ^search_term),
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete
      }
    )
    |> Repo.all()
  end

  @doc """
  Searches hosts by name with pagination.
  Returns fields expected by the host API controller.
  """
  @spec search_hosts_paginated(String.t(), integer(), integer()) :: [map()]
  def search_hosts_paginated(query, limit, offset) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      where: s.taxoncode == "plant" and fragment("lower(?) LIKE ?", s.name, ^search_term),
      order_by: s.name,
      limit: ^limit,
      offset: ^offset,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode,
        datacomplete: s.datacomplete
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of hosts matching a search query.
  """
  @spec count_search_hosts(String.t()) :: integer()
  def count_search_hosts(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      where: s.taxoncode == "plant" and fragment("lower(?) LIKE ?", s.name, ^search_term),
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Searches all species (galls and hosts) by name.
  """
  @spec search_all(String.t()) :: [map()]
  def search_all(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Species,
      where: fragment("lower(?) LIKE ?", s.name, ^search_term),
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns galls that share the same binomial name prefix.

  Related galls share the same genus + species epithet but have additional qualifiers.
  Example: "Andricus quercuscalifornicus agamic" and "Andricus quercuscalifornicus sexual"
  """
  @spec get_related_galls(integer(), String.t()) :: [map()]
  def get_related_galls(exclude_id, name_prefix) do
    from(s in Species,
      where:
        s.taxoncode == "gall" and
          like(s.name, ^"#{name_prefix}%") and
          s.id != ^exclude_id,
      order_by: s.name,
      select: %{
        id: s.id,
        name: s.name,
        taxoncode: s.taxoncode
      }
    )
    |> Repo.all()
  end

  @doc """
  Performs a global search across all entity types.

  Returns a map with results grouped by type.
  """
  @spec global_search(String.t()) :: map()
  def global_search(query) when is_binary(query) do
    query
    |> String.trim()
    |> do_global_search()
  end

  defp do_global_search(""), do: empty_results()

  defp do_global_search(query) do
    search_terms = Ranking.parse_query(query)

    %{
      galls: search_galls_with_aliases(query),
      hosts: search_hosts_with_aliases(query),
      glossary: search_glossary(query) |> Ranking.add_scores_and_sort(search_terms),
      sources: search_sources(query) |> Ranking.add_scores_and_sort(search_terms),
      taxonomy: search_taxonomy(query) |> Ranking.add_scores_and_sort(search_terms),
      places: search_places(query) |> Ranking.add_scores_and_sort(search_terms)
    }
  end

  @doc """
  Returns empty search results.
  """
  @spec empty_results() :: map()
  def empty_results do
    %{
      galls: [],
      hosts: [],
      glossary: [],
      sources: [],
      taxonomy: [],
      places: []
    }
  end

  @doc """
  Searches galls by name or alias using FTS5 for fast prefix matching.
  Falls back to LIKE search for mid-word matches.
  """
  @spec search_galls_with_aliases(String.t()) :: [map()]
  def search_galls_with_aliases(query) do
    # Try FTS5 first for prefix matching
    fts_results = search_galls_fts(query)

    if Enum.empty?(fts_results) do
      # Fall back to LIKE for mid-word matches
      search_galls_with_aliases_like(query)
    else
      fts_results
    end
  end

  # FTS5-based gall search
  defp search_galls_fts(query) do
    sanitized = Gallformers.Species.sanitize_fts_query(query)

    if sanitized == "" do
      []
    else
      fts_query =
        sanitized
        |> String.split(~r/\s+/, trim: true)
        |> Enum.map_join(" ", &"#{&1}*")

      sql = """
      SELECT s.id, s.name, gt.undescribed
      FROM species_fts f
      JOIN species s ON s.id = f.species_id
      JOIN gall_traits gt ON gt.species_id = s.id
      WHERE s.taxoncode = 'gall' AND species_fts MATCH ?
      ORDER BY bm25(species_fts)
      LIMIT 100
      """

      case Repo.query(sql, [fts_query]) do
        {:ok, %{rows: rows}} ->
          search_terms = Ranking.parse_query(query)

          rows
          |> Enum.map(&transform_gall_fts_row/1)
          |> load_all_aliases_for_species()
          |> Ranking.add_scores_and_sort(search_terms)

        {:error, _} ->
          []
      end
    end
  end

  # LIKE-based fallback for mid-word matches
  defp search_galls_with_aliases_like(query) do
    search_term = "%#{String.downcase(query)}%"
    search_terms = Ranking.parse_query(query)

    # Search by species name
    name_results =
      from(s in Species,
        join: gt in GallTraits,
        on: gt.species_id == s.id,
        where: s.taxoncode == "gall" and fragment("lower(?) LIKE ?", s.name, ^search_term),
        order_by: s.name,
        select: %{
          id: s.id,
          name: s.name,
          type: "gall",
          undescribed: gt.undescribed
        }
      )
      |> Repo.all()

    # Search by alias name and return the parent species
    alias_results =
      from(a in Alias,
        join: s in assoc(a, :species),
        join: gt in GallTraits,
        on: gt.species_id == s.id,
        where: s.taxoncode == "gall" and fragment("lower(?) LIKE ?", a.name, ^search_term),
        order_by: s.name,
        select: %{
          id: s.id,
          name: s.name,
          type: "gall",
          undescribed: gt.undescribed
        }
      )
      |> Repo.all()

    # Merge and deduplicate, then load all aliases for each species
    (name_results ++ alias_results)
    |> Enum.uniq_by(& &1.id)
    |> load_all_aliases_for_species()
    |> Ranking.add_scores_and_sort(search_terms)
  end

  @doc """
  Searches hosts by name or alias using FTS5 for fast prefix matching.
  Falls back to LIKE search for mid-word matches.
  """
  @spec search_hosts_with_aliases(String.t()) :: [map()]
  def search_hosts_with_aliases(query) do
    # Try FTS5 first for prefix matching
    fts_results = search_hosts_fts(query)

    if Enum.empty?(fts_results) do
      # Fall back to LIKE for mid-word matches
      search_hosts_with_aliases_like(query)
    else
      fts_results
    end
  end

  # FTS5-based host search
  defp search_hosts_fts(query) do
    sanitized = Gallformers.Species.sanitize_fts_query(query)

    if sanitized == "" do
      []
    else
      fts_query =
        sanitized
        |> String.split(~r/\s+/, trim: true)
        |> Enum.map_join(" ", &"#{&1}*")

      sql = """
      SELECT f.species_id, s.name
      FROM species_fts f
      JOIN species s ON s.id = f.species_id
      WHERE s.taxoncode = 'plant' AND species_fts MATCH ?
      ORDER BY bm25(species_fts)
      LIMIT 100
      """

      case Repo.query(sql, [fts_query]) do
        {:ok, %{rows: rows}} ->
          search_terms = Ranking.parse_query(query)

          rows
          |> Enum.map(&transform_host_fts_row/1)
          |> load_all_aliases_for_species()
          |> Ranking.add_scores_and_sort(search_terms)

        {:error, _} ->
          []
      end
    end
  end

  # LIKE-based fallback for mid-word matches
  defp search_hosts_with_aliases_like(query) do
    search_term = "%#{String.downcase(query)}%"
    search_terms = Ranking.parse_query(query)

    # Search by species name
    name_results =
      from(s in Species,
        where: s.taxoncode == "plant" and fragment("lower(?) LIKE ?", s.name, ^search_term),
        order_by: s.name,
        select: %{
          id: s.id,
          name: s.name,
          type: "host"
        }
      )
      |> Repo.all()

    # Search by alias name
    alias_results =
      from(a in Alias,
        join: s in assoc(a, :species),
        where: s.taxoncode == "plant" and fragment("lower(?) LIKE ?", a.name, ^search_term),
        order_by: s.name,
        select: %{
          id: s.id,
          name: s.name,
          type: "host"
        }
      )
      |> Repo.all()

    # Merge and deduplicate, then load all aliases for each species
    (name_results ++ alias_results)
    |> Enum.uniq_by(& &1.id)
    |> load_all_aliases_for_species()
    |> Ranking.add_scores_and_sort(search_terms)
  end

  defp transform_gall_fts_row([id, name, undescribed]) do
    %{id: id, name: name, type: "gall", undescribed: undescribed == 1}
  end

  defp transform_host_fts_row([id, name]) do
    %{id: id, name: name, type: "host"}
  end

  @doc """
  Searches glossary entries by word or definition.
  """
  @spec search_glossary(String.t()) :: [map()]
  def search_glossary(query) do
    search_term = "%#{String.downcase(query)}%"

    from(g in Glossary,
      where:
        fragment("lower(?) LIKE ?", g.word, ^search_term) or
          fragment("lower(?) LIKE ?", g.definition, ^search_term),
      order_by: g.word,
      select: %{
        id: g.id,
        name: g.word,
        type: "glossary",
        definition: g.definition
      }
    )
    |> Repo.all()
  end

  @doc """
  Searches sources by title or author.
  """
  @spec search_sources(String.t()) :: [map()]
  def search_sources(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Source,
      where:
        fragment("lower(?) LIKE ?", s.title, ^search_term) or
          fragment("lower(?) LIKE ?", s.author, ^search_term),
      order_by: s.title,
      select: %{
        id: s.id,
        name: s.title,
        type: "source",
        author: s.author,
        pubyear: s.pubyear
      }
    )
    |> Repo.all()
  end

  @doc """
  Searches taxonomy entries (genus, family, section) by name or description.

  Excludes placeholder entries (is_placeholder = true) that have no children,
  since empty placeholders serve no purpose in search results. Placeholders
  with children are kept so users can find species under them.
  """
  @spec search_taxonomy(String.t()) :: [map()]
  def search_taxonomy(query) do
    search_term = "%#{String.downcase(query)}%"

    from(t in Taxonomy,
      left_join: parent in assoc(t, :parent),
      left_join: st in "species_taxonomy",
      on: st.taxonomy_id == t.id,
      # Exclude placeholders with no species (handle NULL/0 as false)
      where:
        t.type in ["genus", "family", "section"] and
          (fragment("lower(?) LIKE ?", t.name, ^search_term) or
             fragment("lower(coalesce(?, '')) LIKE ?", t.description, ^search_term)) and
          not (fragment("coalesce(?, 0)", t.is_placeholder) == 1 and is_nil(st.species_id)),
      group_by: [t.id, parent.id],
      order_by: [t.type, t.name],
      select: %{
        id: t.id,
        name: t.name,
        type: t.type,
        description: t.description,
        parent_name: parent.name
      }
    )
    |> Repo.all()
  end

  @doc """
  Searches places by name or code.
  """
  @spec search_places(String.t()) :: [map()]
  def search_places(query) do
    search_term = "%#{String.downcase(query)}%"

    from(p in Place,
      where:
        fragment("lower(?) LIKE ?", p.name, ^search_term) or
          fragment("lower(?) LIKE ?", p.code, ^search_term),
      order_by: p.name,
      select: %{
        id: p.id,
        name: p.name,
        type: "place",
        code: p.code
      }
    )
    |> Repo.all()
  end

  # Loads all aliases for each species in the results list
  defp load_all_aliases_for_species(results) when results == [], do: []

  defp load_all_aliases_for_species(results) do
    species_ids = Enum.map(results, & &1.id)

    # Fetch all aliases for these species via the alias_species join table
    alias_map =
      from(a in Alias,
        join: as in "alias_species",
        on: as.alias_id == a.id,
        where: as.species_id in ^species_ids,
        select: {as.species_id, a.name}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    # Add aliases to each result
    Enum.map(results, fn result ->
      aliases = Map.get(alias_map, result.id, [])
      Map.put(result, :aliases, aliases)
    end)
  end
end
