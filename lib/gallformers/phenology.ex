defmodule Gallformers.Phenology do
  @moduledoc """
  The Phenology context.

  Provides functions for working with phenological observations of galls and
  the iNaturalist blacklist that suppresses rejected imports.

  Public displays consume an explicitly imported, curated snapshot. There is no
  automatic fetcher or source-metadata override engine. Prediction behavior and
  the shared climate reference are documented in `priv/phenology/README.md`.
  """
  use Boundary,
    deps: [
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Species,
      Gallformers.Galls
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Galls
  alias Gallformers.Phenology.Blacklist
  alias Gallformers.Phenology.Observation
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  @doc "Shared event predictions from selected evidence; never writes observations."
  @spec predict([map()], number(), [Gallformers.Phenology.Prediction.event()], keyword()) ::
          {:ok, [map()]} | {:error, atom()}
  defdelegate predict(observations, latitude, events, opts \\ []),
    to: Gallformers.Phenology.Prediction

  @doc "Bundled landmark rows shared with client-side selection."
  @spec seasonal_reference() :: [[float()]]
  defdelegate seasonal_reference(), to: Gallformers.Phenology.SeasonalClock, as: :reference

  @doc "Selection clock edges for a reference day, latitude and calendar-day margin."
  @spec seasonal_window(term(), term(), term()) :: {:ok, {float(), float()}} | :error
  defdelegate seasonal_window(day, latitude, days),
    to: Gallformers.Phenology.SeasonalClock,
    as: :window

  @doc "Whether a plotted day/latitude lies within the selected landmark window."
  @spec in_seasonal_window?(term(), term(), {float(), float()}) :: boolean()
  defdelegate in_seasonal_window?(day, latitude, window),
    to: Gallformers.Phenology.SeasonalClock,
    as: :in_window?

  # ----------------------------------------------------------------------
  # Observations
  # ----------------------------------------------------------------------

  @doc """
  Returns gall species that have at least one phenology observation, with
  the observation count attached. Ordered by species name. Used by the
  phenology explorer's species selector and by per-gall data-availability
  widgets.
  """
  @spec list_species_with_counts() :: [
          %{species_id: integer(), name: String.t(), n_obs: non_neg_integer()}
        ]
  def list_species_with_counts do
    from(o in Observation,
      join: s in Species,
      on: s.id == o.species_id,
      group_by: [s.id, s.name],
      order_by: s.name,
      select: %{species_id: s.id, name: s.name, n_obs: count(o.id)}
    )
    |> Repo.all()
  end

  @doc """
  Returns observations for a single gall species, ordered by date.
  """
  @spec list_observations_for_species(integer()) :: [Observation.t()]
  def list_observations_for_species(species_id) do
    from(o in Observation,
      where: o.species_id == ^species_id,
      order_by: [asc: o.date]
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of observations for a gall species.
  """
  @spec count_observations_for_species(integer()) :: non_neg_integer()
  def count_observations_for_species(species_id) do
    from(o in Observation,
      where: o.species_id == ^species_id,
      select: count(o.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns observations matching the given filters, with denormalized species
  name. Used by the public `/phenology` explorer to drive its multi-species
  scatter; each returned map is shaped for direct passing to the chart hook.

  Filters (all optional):
    * `:species_id` — exact GF gall ID; used by the compact panel and its link.
    * `:search` — list of name fragments. Returned obs belong to species
      whose name ILIKEs at least one fragment. Empty / nil = no name filter.
    * `:generation` — `:all` (default), `:sexgen`, or `:agamic`. Matches on
      the `(sexgen)` / `(agamic)` suffix convention in `species.name`.
    * `:phenophases` — list of phenophase values to keep. Nil means no
      phase restriction; an empty list deliberately returns no observations.
    * `:taxon_id` — a `taxonomy` node id (family, intermediate rank such as
      a tribe, or genus). Restricts obs to gall species sitting under that
      node in the taxonomy tree. Nil = no taxonomic filter.
    * `:plant_part_ids` / `:color_ids` / `:shape_ids` — lists of gall-trait
      filter-field ids. Restricts obs to gall species carrying those traits,
      reusing the ID tool's filter engine (`Gallformers.Galls`). Empty / nil
      lists = no trait filter for that facet.

  Always scoped to `species.taxoncode == "gall"` so host-plant rows can't
  leak in if they ever land in this table.
  """
  @spec search_observations(map()) :: [map()]
  def search_observations(filters \\ %{}) do
    from(o in Observation,
      join: s in Species,
      on: s.id == o.species_id,
      left_join: h in Species,
      on: h.id == o.host_species_id,
      where: s.taxoncode == "gall",
      order_by: [asc: o.date],
      select: %{
        id: o.id,
        species_id: o.species_id,
        species_name: s.name,
        host_species_id: o.host_species_id,
        host_species_name: h.name,
        date: o.date,
        doy: o.doy,
        phenophase: o.phenophase,
        lifestage: o.lifestage,
        viability: o.viability,
        latitude: o.latitude,
        longitude: o.longitude,
        source_type: o.source_type,
        source_url: o.source_url,
        page_url: o.page_url,
        site: o.site,
        state: o.state,
        country: o.country,
        seasind: o.seasind
      }
    )
    |> apply_search_filter(Map.get(filters, :search))
    |> apply_species_filter(Map.get(filters, :species_id))
    |> apply_generation_filter(Map.get(filters, :generation, :all))
    |> apply_phenophase_filter(Map.get(filters, :phenophases))
    |> apply_coordinate_filter(filters)
    |> apply_taxon_filter(Map.get(filters, :taxon_id))
    |> apply_trait_filter(filters)
    |> apply_place_filter(Map.get(filters, :place_id))
    |> Repo.all()
  end

  defp apply_species_filter(query, nil), do: query
  defp apply_species_filter(query, id), do: where(query, [o], o.species_id == ^id)

  defp apply_search_filter(query, nil), do: query
  defp apply_search_filter(query, []), do: query

  defp apply_search_filter(query, terms) when is_list(terms) do
    patterns =
      terms
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&"%#{&1}%")

    case patterns do
      [] ->
        query

      _ ->
        # OR across all name patterns: search matches "any of these fragments
        # anywhere in the species name."
        dyn =
          Enum.reduce(patterns, false, fn pattern, acc ->
            dynamic([_, s], ^acc or ilike(s.name, ^pattern))
          end)

        from(q in query, where: ^dyn)
    end
  end

  defp apply_generation_filter(query, :sexgen) do
    from([_, s] in query, where: ilike(s.name, "%(sexgen)%"))
  end

  defp apply_generation_filter(query, :agamic) do
    from([_, s] in query, where: ilike(s.name, "%(agamic)%"))
  end

  defp apply_generation_filter(query, _), do: query

  # `nil` means "no filter / key not provided" — kept for non-LV callers that
  # don't pass a `:phenophases` key. `[]` means "filter to nothing" — the
  # explorer uses this to honor an all-unchecked UI state strictly. The two
  # are intentionally distinguished.
  defp apply_phenophase_filter(query, nil), do: query
  defp apply_phenophase_filter(query, []), do: from(o in query, where: false)

  defp apply_phenophase_filter(query, phenophases) when is_list(phenophases) do
    from(o in query, where: o.phenophase in ^phenophases)
  end

  # Persistent geographic filter on the observation coordinates. Any obs
  # with NULL lat/lng is dropped as soon as any bound is set — we can't
  # tell whether it falls inside the user's box. Bounds are independent:
  # setting only min_lat is fine.
  defp apply_coordinate_filter(query, filters) do
    min_lat = Map.get(filters, :min_lat)
    max_lat = Map.get(filters, :max_lat)
    min_lng = Map.get(filters, :min_lng)
    max_lng = Map.get(filters, :max_lng)

    if min_lat || max_lat || min_lng || max_lng do
      query
      |> where([o], not is_nil(o.latitude) and not is_nil(o.longitude))
      |> maybe_min_lat(min_lat)
      |> maybe_max_lat(max_lat)
      |> maybe_min_lng(min_lng)
      |> maybe_max_lng(max_lng)
    else
      query
    end
  end

  defp maybe_min_lat(query, nil), do: query
  defp maybe_min_lat(query, v), do: where(query, [o], o.latitude >= ^v)

  defp maybe_max_lat(query, nil), do: query
  defp maybe_max_lat(query, v), do: where(query, [o], o.latitude <= ^v)

  defp maybe_min_lng(query, nil), do: query
  defp maybe_min_lng(query, v), do: where(query, [o], o.longitude >= ^v)

  defp maybe_max_lng(query, nil), do: query
  defp maybe_max_lng(query, v), do: where(query, [o], o.longitude <= ^v)

  # Taxonomic filter. A species links to its genus in `species_taxonomy`;
  # family / tribe (intermediate) filtering means "genus is a descendant of
  # the selected node." We resolve the node to the set of species beneath it
  # and constrain on species_id — keeping the positional bindings of the
  # existing filters untouched. An unknown / dataless node resolves to `[]`,
  # which correctly yields no observations.
  defp apply_taxon_filter(query, nil), do: query

  defp apply_taxon_filter(query, taxon_id) when is_integer(taxon_id) do
    species_ids = species_ids_under_taxon(taxon_id)
    from(o in query, where: o.species_id in ^species_ids)
  end

  defp apply_taxon_filter(query, _), do: query

  # Gall-trait filter. Rather than re-implement the nine-facet junction-table
  # joins the ID tool already owns, we hand the selected trait ids to
  # `Gallformers.Galls.filter_gall_species_ids/1` and constrain on the
  # returned species set — again binding-safe via species_id. Only the facets
  # with a non-empty selection are passed through; with none selected we skip
  # the call (and its query) entirely.
  defp apply_trait_filter(query, filters) do
    trait_filters =
      %{}
      |> put_trait(:plant_part_ids, Map.get(filters, :plant_part_ids))
      |> put_trait(:color_ids, Map.get(filters, :color_ids))
      |> put_trait(:shape_ids, Map.get(filters, :shape_ids))

    if map_size(trait_filters) == 0 do
      query
    else
      species_ids = Galls.filter_gall_species_ids(trait_filters)
      from(o in query, where: o.species_id in ^species_ids)
    end
  end

  defp put_trait(map, _key, nil), do: map
  defp put_trait(map, _key, []), do: map
  defp put_trait(map, key, list) when is_list(list), do: Map.put(map, key, list)

  # Geographic filter: constrain to species whose curated `gall_range` covers
  # the selected place OR any place beneath it (selecting a country pulls in
  # all its states/provinces). Binding-safe via species_id, same as the taxon
  # and trait filters. This filters on documented range, NOT on observation
  # coordinates — that's the separate coordinate/map filter.
  defp apply_place_filter(query, nil), do: query

  defp apply_place_filter(query, place_id) when is_integer(place_id) do
    species_ids = species_ids_in_place(place_id)
    from(o in query, where: o.species_id in ^species_ids)
  end

  defp apply_place_filter(query, _), do: query

  @doc """
  Returns the IDs of species that sit under the given `taxonomy` node —
  the node itself or any descendant — via their `species_taxonomy` link.

  Works for a family, an intermediate rank (subfamily / tribe / …), or a
  genus: species link to their genus (and optionally a section), so walking
  the subtree of the selected node and collecting every linked species
  captures them regardless of which level was chosen. Returns `[]` for an
  unknown id.
  """
  @spec species_ids_under_taxon(integer()) :: [integer()]
  def species_ids_under_taxon(taxon_id) when is_integer(taxon_id) do
    query = """
    WITH RECURSIVE subtree AS (
      SELECT id FROM taxonomy WHERE id = $1::bigint
      UNION ALL
      SELECT t.id FROM taxonomy t JOIN subtree s ON t.parent_id = s.id
    )
    SELECT DISTINCT st.species_id
    FROM species_taxonomy st
    WHERE st.taxonomy_id IN (SELECT id FROM subtree)
    """

    %{rows: rows} = Repo.query!(query, [taxon_id])
    Enum.map(rows, fn [id] -> id end)
  end

  @doc """
  Lists the family- and intermediate-rank (subfamily / tribe / …) `taxonomy`
  nodes that have at least one gall species carrying phenology observations,
  for the explorer's taxon selector. Only nodes with data are returned, so
  the selector can never offer a dead option.

  Genus nodes are intentionally excluded: there are far too many to scale in
  a dropdown, and the free-text search box already filters by genus (it
  ILIKEs the species name, whose first word is the genus). This selector is
  for the higher-level rollups the text box can't express.

  Each option is a map `%{id, name, group, n_species}` where `group` is a
  display label for the rank ("Family" / "Subfamily" / "Tribe" / …) and
  `n_species` is the count of distinct observed species beneath the node.
  Ordered family → intermediate ranks, alphabetized within each group.
  """
  @spec list_taxon_filter_options() :: [map()]
  def list_taxon_filter_options do
    query = """
    WITH RECURSIVE lineage AS (
      SELECT DISTINCT st.species_id, t.id, t.name, t.type, t.rank, t.parent_id
      FROM phenology_observations o
      JOIN species s ON s.id = o.species_id AND s.taxoncode = 'gall'
      JOIN species_taxonomy st ON st.species_id = o.species_id
      JOIN taxonomy t ON t.id = st.taxonomy_id AND t.type = 'genus'
      UNION ALL
      SELECT l.species_id, t.id, t.name, t.type, t.rank, t.parent_id
      FROM taxonomy t
      JOIN lineage l ON t.id = l.parent_id
      WHERE l.type <> 'family'
    )
    SELECT id, name, type, rank, count(DISTINCT species_id) AS n_species
    FROM lineage
    WHERE type <> 'genus'
    GROUP BY id, name, type, rank
    """

    %{rows: rows} = Repo.query!(query, [])

    rows
    |> Enum.map(fn [id, name, type, rank, n] ->
      %{
        id: id,
        name: name,
        group: taxon_group_label(type, rank),
        n_species: n,
        rank_order: taxon_rank_order(type, rank)
      }
    end)
    |> Enum.sort_by(&{&1.rank_order, &1.name})
  end

  defp taxon_group_label("family", _), do: "Family"
  defp taxon_group_label("intermediate", rank) when is_binary(rank), do: rank
  defp taxon_group_label("intermediate", _), do: "Intermediate"
  defp taxon_group_label("genus", _), do: "Genus"
  defp taxon_group_label(_, _), do: "Other"

  # Sort key so the select groups read family → subfamily → tribe → genus.
  defp taxon_rank_order("family", _), do: 0
  defp taxon_rank_order("intermediate", "Subfamily"), do: 1
  defp taxon_rank_order("intermediate", "Infrafamily"), do: 2
  defp taxon_rank_order("intermediate", "Supertribe"), do: 3
  defp taxon_rank_order("intermediate", "Tribe"), do: 4
  defp taxon_rank_order("intermediate", "Subtribe"), do: 5
  defp taxon_rank_order("intermediate", "Infratribe"), do: 6
  defp taxon_rank_order("intermediate", _), do: 7
  defp taxon_rank_order("genus", _), do: 8
  defp taxon_rank_order(_, _), do: 9

  @doc """
  Returns the IDs of gall species whose curated `gall_range` covers the given
  place or any place beneath it in `place_hierarchy` (a country resolves to
  all its states/provinces). Returns `[]` for an unknown id.
  """
  @spec species_ids_in_place(integer()) :: [integer()]
  def species_ids_in_place(place_id) when is_integer(place_id) do
    query = """
    WITH RECURSIVE descendants(id) AS (
      SELECT $1::bigint
      UNION ALL
      SELECT ph.place_id FROM place_hierarchy ph JOIN descendants d ON ph.parent_id = d.id
    )
    SELECT DISTINCT g.species_id
    FROM gall_range g
    WHERE g.place_id IN (SELECT id FROM descendants)
    """

    %{rows: rows} = Repo.query!(query, [place_id])
    Enum.map(rows, fn [id] -> id end)
  end

  @doc """
  Returns observations whose raw and processed phenophase disagree — i.e. an
  admin correction is in effect, or upstream data drifted and the correction
  needs re-review.
  """
  @spec list_observations_needing_review() :: [Observation.t()]
  def list_observations_needing_review do
    from(o in Observation,
      where: fragment("? IS DISTINCT FROM ?", o.phenophase, o.raw_phenophase),
      order_by: [desc: o.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single observation. Raises if not found.
  """
  @spec get_observation!(integer()) :: Observation.t()
  def get_observation!(id), do: Repo.get!(Observation, id)

  @doc """
  Creates an observation. For a fresh import (literature or iNat), raw and
  processed fields are typically set identically.
  """
  @spec create_observation(map()) :: {:ok, Observation.t()} | {:error, Ecto.Changeset.t()}
  def create_observation(attrs) do
    %Observation{}
    |> Observation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an observation during an explicit curated-data operation.
  """
  @spec update_observation(Observation.t(), map()) ::
          {:ok, Observation.t()} | {:error, Ecto.Changeset.t()}
  def update_observation(%Observation{} = observation, attrs) do
    observation
    |> Observation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an observation.
  """
  @spec delete_observation(Observation.t()) ::
          {:ok, Observation.t()} | {:error, Ecto.Changeset.t()}
  def delete_observation(%Observation{} = observation), do: Repo.delete(observation)

  @doc """
  Returns a blank changeset for forms.
  """
  @spec change_observation(Observation.t(), map()) :: Ecto.Changeset.t()
  def change_observation(%Observation{} = observation, attrs \\ %{}),
    do: Observation.changeset(observation, attrs)

  # ----------------------------------------------------------------------
  # Blacklist
  # ----------------------------------------------------------------------

  @doc """
  Returns true if the given iNaturalist observation ID has been blacklisted.
  Available to explicit import operations; no automated fetcher is installed.
  """
  @spec blacklisted?(integer()) :: boolean()
  def blacklisted?(inat_id) when is_integer(inat_id) do
    Repo.exists?(from b in Blacklist, where: b.inat_id == ^inat_id)
  end

  @doc """
  Adds an iNat observation to the blacklist so it won't be re-imported.
  """
  @spec blacklist(map()) :: {:ok, Blacklist.t()} | {:error, Ecto.Changeset.t()}
  def blacklist(attrs) do
    %Blacklist{}
    |> Blacklist.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns all blacklist entries.
  """
  @spec list_blacklist() :: [Blacklist.t()]
  def list_blacklist do
    from(b in Blacklist, order_by: [desc: b.inserted_at])
    |> Repo.all()
  end

  @doc """
  Removes a blacklist entry (e.g. an admin decided to re-allow an observation).
  """
  @spec unblacklist(Blacklist.t()) ::
          {:ok, Blacklist.t()} | {:error, Ecto.Changeset.t()}
  def unblacklist(%Blacklist{} = blacklist), do: Repo.delete(blacklist)
end
