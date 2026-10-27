defmodule Gallformers.OldModelFixtures do
  @moduledoc """
  Rows of today's model (`species`, `taxonomy`, `gallhost`, ...), inserted
  directly as the data migration (`Gallformers.CatalogMigration`) reads them.
  The old tables are not audited.

  IDs are explicit and far above the seeds (`priv/repo/test_seeds.sql`);
  the seeds' own rows (e.g. Cynipidae, ID 30, with its tribe Cynipini, the
  genus Andricus, ID 33, and the placeholder genus "Unknown", ID 35) are
  used where a test needs a real hierarchy.
  """

  alias Gallformers.Repo

  @now ~U[2026-01-01 00:00:00Z]

  @doc "A `taxonomy` row. `opts`: `:parent`, `:description`, `:rank`, `:placeholder`."
  def taxonomy!(id, name, type, opts \\ []) do
    Repo.insert_all("taxonomy", [
      %{
        id: id,
        name: name,
        type: type,
        description: opts[:description],
        rank: opts[:rank],
        parent_id: opts[:parent],
        is_placeholder: Keyword.get(opts, :placeholder, false),
        inserted_at: @now,
        updated_at: @now
      }
    ])

    id
  end

  @doc """
  A plant `species` row linked to `taxonomy_ids`. `opts`: `:placeholder`,
  `:datacomplete`, `:abundance_id`.
  """
  def plant!(id, name, taxonomy_ids, opts \\ []) do
    species!(id, name, "plant",
      genus_placeholder: Keyword.get(opts, :placeholder, false),
      datacomplete: Keyword.get(opts, :datacomplete, false),
      abundance_id: opts[:abundance_id]
    )

    Enum.each(List.wrap(taxonomy_ids), &link!(id, &1))
    id
  end

  @doc """
  A gall `species` row with its `gall_traits` row, linked to `taxonomy_ids`.
  `opts`: `:undescribed`, `:code`, `:detachable`, `:datacomplete`,
  `:abundance_id`, `:range_confirmed`, `:range_computed_at`.
  """
  def gall!(id, name, taxonomy_ids, opts \\ []) do
    species!(id, name, "gall",
      datacomplete: Keyword.get(opts, :datacomplete, false),
      abundance_id: opts[:abundance_id]
    )

    Repo.insert_all("gall_traits", [
      %{
        species_id: id,
        undescribed: Keyword.get(opts, :undescribed, false),
        gallformers_code: opts[:code],
        detachable: opts[:detachable],
        range_confirmed: Keyword.get(opts, :range_confirmed, false),
        range_computed_at: opts[:range_computed_at]
      }
    ])

    Enum.each(List.wrap(taxonomy_ids), &link!(id, &1))
    id
  end

  defp species!(id, name, taxoncode, fields) do
    Repo.insert_all("species", [
      Map.merge(
        %{id: id, name: name, taxoncode: taxoncode, inserted_at: @now, updated_at: @now},
        Map.new(fields)
      )
    ])
  end

  defp link!(species_id, taxonomy_id),
    do: Repo.insert_all("species_taxonomy", [%{species_id: species_id, taxonomy_id: taxonomy_id}])

  @doc "A `gallhost` row. `opts`: `:inserted_at` (when the link was made)."
  def gallhost!(gall_id, host_id, opts \\ []) do
    at = Keyword.get(opts, :inserted_at, @now)

    Repo.insert_all("gallhost", [
      %{gall_species_id: gall_id, host_species_id: host_id, inserted_at: at, updated_at: at}
    ])
  end

  @doc """
  A `host_range` row for a place code. `opts`: `:precision` (default
  `"exact"`), `:distribution_type` (default `"native"`). A string third
  argument is the precision.
  """
  def host_range!(species_id, code, opts \\ [])

  def host_range!(species_id, code, precision) when is_binary(precision),
    do: host_range!(species_id, code, precision: precision)

  def host_range!(species_id, code, opts) do
    Repo.insert_all("host_range", [
      %{
        species_id: species_id,
        place_id: place_id(code),
        precision: Keyword.get(opts, :precision, "exact"),
        distribution_type: Keyword.get(opts, :distribution_type, "native")
      }
    ])
  end

  @doc "A `gall_range` row (a Gall's stored range) for a place code."
  def gall_range!(species_id, code, precision \\ "exact") do
    Repo.insert_all("gall_range", [
      %{species_id: species_id, place_id: place_id(code), precision: precision}
    ])
  end

  @doc "A `host_traits` row. `opts`: `:wcvp_synced_at`."
  def host_traits!(species_id, opts \\ []) do
    Repo.insert_all("host_traits", [
      %{species_id: species_id, wcvp_synced_at: opts[:wcvp_synced_at]}
    ])
  end

  @doc "A `place` row under the place with code `parent` (or a root)."
  def place!(id, code, name, parent \\ nil) do
    Repo.insert_all("place", [%{id: id, code: code, name: name, type: "state"}])

    if parent,
      do: Repo.insert_all("place_hierarchy", [%{place_id: id, parent_id: place_id(parent)}])

    id
  end

  @doc """
  An `alias` row of `type` (`"common"`, `"scientific"`,
  `"former_undescribed"`) on species (`alias_species`) and taxonomy rows
  (`taxonomy_alias`): `owners` is a list of `{:species | :taxonomy, id}`.
  """
  def alias!(id, name, type, owners) do
    Repo.insert_all("alias", [
      %{id: id, name: name, type: type, description: "", inserted_at: @now, updated_at: @now}
    ])

    for {kind, owner} <- owners do
      case kind do
        :species -> Repo.insert_all("alias_species", [%{alias_id: id, species_id: owner}])
        :taxonomy -> Repo.insert_all("taxonomy_alias", [%{alias_id: id, taxonomy_id: owner}])
      end
    end

    id
  end

  @doc "A `keys` row with `couplets` (a string-keyed map, stored as JSON)."
  def key!(id, slug, couplets) do
    Repo.insert_all("keys", [
      %{
        id: id,
        slug: slug,
        title: "Key #{slug}",
        version: "1",
        authors: "[]",
        couplets: Jason.encode!(couplets),
        inserted_at: ~N[2026-01-01 00:00:00],
        updated_at: ~N[2026-01-01 00:00:00]
      }
    ])

    id
  end

  @doc "A key's couplets as stored (decoded JSON)."
  def key_couplets(id) do
    %{rows: [[json]]} = Repo.query!("SELECT couplets FROM keys WHERE id = $1", [id])
    Jason.decode!(json)
  end

  @doc """
  A Trait join row: `table` is the old vocabulary table (`"color"`,
  `"plant_part"`, ...), `value` its value, inserted into the vocabulary
  when missing.
  """
  def trait!(species_id, table, value) do
    column = if table == "plant_part", do: "part", else: table

    %{rows: [[value_id]]} =
      Repo.query!(
        """
        WITH found AS (SELECT id FROM #{table} WHERE #{column} = $1),
             added AS (INSERT INTO #{table} (#{column}) SELECT $1
                       WHERE NOT EXISTS (SELECT 1 FROM found) RETURNING id)
        SELECT id FROM found UNION ALL SELECT id FROM added
        """,
        [value]
      )

    Repo.query!(
      "INSERT INTO gall_#{table} (species_id, #{table}_id) VALUES ($1, $2)",
      [species_id, value_id]
    )
  end

  @doc "A `species_source` row. `opts`: `:useasdefault`, `:externallink`."
  def species_source!(species_id, source_id, description, opts \\ []) do
    {1, [%{id: id}]} =
      Repo.insert_all(
        "species_source",
        [
          %{
            species_id: species_id,
            source_id: source_id,
            description: description,
            useasdefault: Keyword.get(opts, :useasdefault, false),
            externallink: Keyword.get(opts, :externallink, "")
          }
        ],
        returning: [:id]
      )

    id
  end

  @doc "An `image` row."
  def image!(species_id, path) do
    {1, [%{id: id}]} =
      Repo.insert_all("image", [%{species_id: species_id, path: path}], returning: [:id])

    id
  end

  @doc "A seeded place's ID by code."
  def place_id(code) do
    %{rows: [[id]]} = Repo.query!("SELECT id FROM place WHERE code = $1", [code])
    id
  end

  # -- the shared scenario -------------------------------------------------------

  @doc """
  A small old-model catalog:

    * Fagaceae (plants) > Quercus > section Lobatae, with Quercus fixturalba
      (genus link), Quercus fixturrubra (genus and section links) and the
      genus placeholder "Quercus spp."; ranges for fixturalba (US-CA) and the
      placeholder (MX-JAL, CA-AB). Fixturalba is data-complete and
      uncommon (abundance 2); fixturrubra neither.
    * Andricus (seeded, under Cynipini, Cynipinae, Cynipidae): the pair
      Andricus fixtura (agamic) / (sexgen), an undescribed gall, and a name
      with an unknown suffix.
    * An undescribed gall in Cynipidae's placeholder genus (seeded), and one
      in the Unknown family's placeholder genus.
    * Host links: the pair on fixturalba, the agamic gall also on the
      placeholder.
  """
  def old_catalog_fixture do
    fagaceae = taxonomy!(880_001, "Fixturaceae", "family", description: "Plant")
    quercus = taxonomy!(880_002, "Fixturquercus", "genus", parent: fagaceae)
    lobatae = taxonomy!(880_003, "Fixturlobatae", "section", parent: quercus)
    unknown_family = taxonomy!(880_020, "Unknown", "family", description: "Unknown")

    unknown_genus =
      taxonomy!(880_021, "Unknown", "genus", parent: unknown_family, placeholder: true)

    alba = plant!(880_101, "Fixturquercus alba", quercus, datacomplete: true, abundance_id: 2)
    rubra = plant!(880_102, "Fixturquercus rubra", [quercus, lobatae])
    spp = plant!(880_103, "Fixturquercus spp", quercus, placeholder: true)

    host_range!(alba, "US-CA")
    host_range!(spp, "MX-JAL")
    host_range!(spp, "CA-AB")

    agamic = gall!(880_201, "Andricus fixtura (agamic)", 33, code: "fixtura-agamic")
    sexgen = gall!(880_202, "Andricus fixtura (sexgen)", 33, datacomplete: true)
    undescribed = gall!(880_203, "Andricus q-alba-fixture-gall", 33, undescribed: true)
    unknown_suffix = gall!(880_204, "Andricus fixturaria (pacificus)", 33)
    in_family = gall!(880_205, "Unknown (Cynipidae) q-alba-fixture-bead", 35, undescribed: true)

    no_inducer =
      gall!(880_206, "Unknown (Unknown) fixture-mystery", unknown_genus, undescribed: true)

    gallhost!(agamic, alba)
    gallhost!(sexgen, alba)
    gallhost!(agamic, spp)

    %{
      fagaceae: fagaceae,
      quercus: quercus,
      lobatae: lobatae,
      unknown_family: unknown_family,
      unknown_genus: unknown_genus,
      alba: alba,
      rubra: rubra,
      spp: spp,
      agamic: agamic,
      sexgen: sexgen,
      undescribed: undescribed,
      unknown_suffix: unknown_suffix,
      in_family: in_family,
      no_inducer: no_inducer
    }
  end

  @doc """
  A gall-forming plant family kept twice, as today's Santalaceae is (a plant
  family and a "Plant (gall forming)" family of the same name with " (gall)"):

    * Fixtursantalaceae (Plant) > Fixturphoradendron, with the plant
      Fixturphoradendron leucarpum.
    * Fixtursantalaceae (gall) (Plant (gall forming)) > Fixturphoradendron
      (again) > section Fixturvillosae, and the placeholder genus
      "Unknown (Fixtursantalaceae (gall))"; the gall Fixturphoradendron
      serotinum on the second genus, an undescribed gall in the placeholder.
  """
  def gall_family_fixture do
    family = taxonomy!(880_040, "Fixtursantalaceae", "family", description: "Plant")
    genus = taxonomy!(880_041, "Fixturphoradendron", "genus", parent: family)

    gall_family =
      taxonomy!(880_042, "Fixtursantalaceae (gall)", "family",
        description: "Plant (gall forming)"
      )

    gall_genus = taxonomy!(880_043, "Fixturphoradendron", "genus", parent: gall_family)

    placeholder =
      taxonomy!(880_044, "Unknown (Fixtursantalaceae (gall))", "genus",
        parent: gall_family,
        placeholder: true
      )

    section = taxonomy!(880_045, "Fixturvillosae", "section", parent: gall_genus)

    plant = plant!(880_160, "Fixturphoradendron leucarpum", genus)
    gall = gall!(880_270, "Fixturphoradendron serotinum", gall_genus)

    undescribed =
      gall!(880_271, "Unknown (Fixtursantalaceae (gall)) fixture-broom", placeholder,
        undescribed: true
      )

    %{
      family: family,
      genus: genus,
      gall_family: gall_family,
      gall_genus: gall_genus,
      placeholder: placeholder,
      section: section,
      plant: plant,
      gall: gall,
      undescribed: undescribed
    }
  end

  @doc """
  A family whose type gives no kingdom (`"Unknown"`), as today's
  Plasmodiophoridae: Fixturphoridae > Fixturphora, with the gall
  Fixturphora brassicae.
  """
  def kingdomless_family_fixture do
    family = taxonomy!(880_050, "Fixturphoridae", "family", description: "Unknown")
    genus = taxonomy!(880_051, "Fixturphora", "genus", parent: family)
    gall = gall!(880_272, "Fixturphora brassicae", genus)

    %{family: family, genus: genus, gall: gall}
  end
end
