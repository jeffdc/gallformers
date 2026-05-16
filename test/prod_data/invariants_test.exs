defmodule Gallformers.ProdData.InvariantsTest do
  use Gallformers.ProdDataCase

  @moduletag :prod_data

  alias Gallformers.Taxonomy.Taxonomy

  test "database has real data" do
    assert data_count(Taxonomy) > 500
  end

  # ---------------------------------------------------------------------------
  # Taxonomy tree integrity
  # ---------------------------------------------------------------------------

  describe "taxonomy tree integrity" do
    test "every genus has a parent_id pointing to a family or intermediate rank" do
      bad =
        Repo.all(
          from g in "taxonomy",
            left_join: p in "taxonomy",
            on: g.parent_id == p.id,
            where:
              g.type == "genus" and
                (is_nil(p.id) or p.type not in ["family", "intermediate"]),
            select: %{id: g.id, name: g.name, parent_id: g.parent_id}
        )

      assert bad == [],
             "Found #{length(bad)} genera whose parent is not a family or intermediate: #{inspect(Enum.take(bad, 10))}"
    end

    test "every section has a parent_id pointing to a genus (not a family)" do
      bad =
        Repo.all(
          from s in "taxonomy",
            left_join: p in "taxonomy",
            on: s.parent_id == p.id,
            where: s.type == "section" and (is_nil(p.id) or p.type != "genus"),
            select: %{id: s.id, name: s.name, parent_id: s.parent_id}
        )

      assert bad == [],
             "Found #{length(bad)} sections whose parent is not a genus: #{inspect(Enum.take(bad, 10))}"
    end

    test "no taxonomy record has parent_id pointing to itself" do
      bad =
        Repo.all(
          from t in "taxonomy",
            where: t.parent_id == t.id,
            select: %{id: t.id, name: t.name}
        )

      assert bad == [],
             "Found #{length(bad)} self-referencing taxonomy records: #{inspect(Enum.take(bad, 10))}"
    end

    test "no orphaned taxonomy records (parent_id pointing to nonexistent record)" do
      bad =
        Repo.all(
          from t in "taxonomy",
            left_join: p in "taxonomy",
            on: t.parent_id == p.id,
            where: not is_nil(t.parent_id) and is_nil(p.id),
            select: %{id: t.id, name: t.name, parent_id: t.parent_id}
        )

      assert bad == [],
             "Found #{length(bad)} orphaned taxonomy records: #{inspect(Enum.take(bad, 10))}"
    end

    test "taxonomy type field is consistent (families have no parent, genera/sections/intermediates do)" do
      # Families should have no parent_id (they are roots)
      families_with_parent =
        Repo.all(
          from t in "taxonomy",
            where: t.type == "family" and not is_nil(t.parent_id),
            select: %{id: t.id, name: t.name, parent_id: t.parent_id}
        )

      assert families_with_parent == [],
             "Found #{length(families_with_parent)} families with a parent_id: #{inspect(Enum.take(families_with_parent, 10))}"

      # Genera, sections, and intermediates should have a parent_id
      missing_parent =
        Repo.all(
          from t in "taxonomy",
            where: t.type in ["genus", "section", "intermediate"] and is_nil(t.parent_id),
            select: %{id: t.id, name: t.name, type: t.type}
        )

      assert missing_parent == [],
             "Found #{length(missing_parent)} genera/sections/intermediates without parent_id: #{inspect(Enum.take(missing_parent, 10))}"
    end
  end

  # ---------------------------------------------------------------------------
  # Species-taxonomy linkage
  # ---------------------------------------------------------------------------

  describe "species-taxonomy linkage" do
    test "every species has at least one row in species_taxonomy" do
      bad =
        Repo.all(
          from s in "species",
            left_join: st in "species_taxonomy",
            on: s.id == st.species_id,
            where: is_nil(st.species_id),
            select: %{id: s.id, name: s.name}
        )

      assert bad == [],
             "Found #{length(bad)} species with no species_taxonomy link: #{inspect(Enum.take(bad, 10))}"
    end

    test "every species has exactly one genus link" do
      # Species with zero genus links
      zero_genus =
        Repo.all(
          from s in "species",
            left_join: st in "species_taxonomy",
            on: s.id == st.species_id,
            left_join: t in "taxonomy",
            on: st.taxonomy_id == t.id and t.type == "genus",
            group_by: [s.id, s.name],
            having: count(t.id) == 0,
            select: %{id: s.id, name: s.name}
        )

      assert zero_genus == [],
             "Found #{length(zero_genus)} species with no genus link: #{inspect(Enum.take(zero_genus, 10))}"

      # Species with multiple genus links
      multi_genus =
        Repo.all(
          from s in "species",
            join: st in "species_taxonomy",
            on: s.id == st.species_id,
            join: t in "taxonomy",
            on: st.taxonomy_id == t.id and t.type == "genus",
            group_by: [s.id, s.name],
            having: count(t.id) > 1,
            select: %{id: s.id, name: s.name, genus_count: count(t.id)}
        )

      assert multi_genus == [],
             "Found #{length(multi_genus)} species with multiple genus links: #{inspect(Enum.take(multi_genus, 10))}"
    end

    test "no species has a section link without also having a genus link" do
      genus_species =
        from st in "species_taxonomy",
          join: t in "taxonomy",
          on: st.taxonomy_id == t.id and t.type == "genus",
          select: st.species_id

      bad =
        Repo.all(
          from s in "species",
            join: st_sec in "species_taxonomy",
            on: s.id == st_sec.species_id,
            join: t_sec in "taxonomy",
            on: st_sec.taxonomy_id == t_sec.id and t_sec.type == "section",
            where: s.id not in subquery(genus_species),
            select: %{id: s.id, name: s.name}
        )

      assert bad == [],
             "Found #{length(bad)} species with section but no genus link: #{inspect(Enum.take(bad, 10))}"
    end

    test "at most one genus-level placeholder species per genus" do
      # A species's genus is the linked row in `taxonomy` whose type = 'genus'
      # via the `species_taxonomy` join table. There should never be more than
      # one species flagged as `genus_placeholder = true` for a given genus.
      violations =
        Repo.all(
          from s in "species",
            join: st in "species_taxonomy",
            on: s.id == st.species_id,
            join: t in "taxonomy",
            on: st.taxonomy_id == t.id and t.type == "genus",
            where: s.genus_placeholder == true,
            group_by: [t.id, t.name],
            having: count(s.id) > 1,
            select: %{
              genus_id: t.id,
              genus_name: t.name,
              placeholder_count: count(s.id),
              species_names: fragment("array_agg(?)", s.name)
            }
        )

      assert violations == [],
             "Found #{length(violations)} genera with multiple genus_placeholder species: #{inspect(Enum.take(violations, 10))}"
    end

    test "every species_taxonomy row points to a valid species_id and taxonomy_id" do
      bad_species =
        Repo.all(
          from st in "species_taxonomy",
            left_join: s in "species",
            on: st.species_id == s.id,
            where: is_nil(s.id),
            select: %{species_id: st.species_id, taxonomy_id: st.taxonomy_id}
        )

      assert bad_species == [],
             "Found #{length(bad_species)} species_taxonomy rows with invalid species_id: #{inspect(Enum.take(bad_species, 10))}"

      bad_taxonomy =
        Repo.all(
          from st in "species_taxonomy",
            left_join: t in "taxonomy",
            on: st.taxonomy_id == t.id,
            where: is_nil(t.id),
            select: %{species_id: st.species_id, taxonomy_id: st.taxonomy_id}
        )

      assert bad_taxonomy == [],
             "Found #{length(bad_taxonomy)} species_taxonomy rows with invalid taxonomy_id: #{inspect(Enum.take(bad_taxonomy, 10))}"
    end
  end

  # ---------------------------------------------------------------------------
  # Gall traits consistency
  # ---------------------------------------------------------------------------

  describe "gall traits consistency" do
    test "every gall species has exactly one gall_traits row" do
      missing =
        Repo.all(
          from s in "species",
            left_join: gt in "gall_traits",
            on: s.id == gt.species_id,
            where: s.taxoncode == "gall" and is_nil(gt.species_id),
            select: %{id: s.id, name: s.name}
        )

      assert missing == [],
             "Found #{length(missing)} gall species without gall_traits: #{inspect(Enum.take(missing, 10))}"
    end

    test "no gall_traits row points to a non-gall species" do
      bad =
        Repo.all(
          from gt in "gall_traits",
            join: s in "species",
            on: gt.species_id == s.id,
            where: s.taxoncode != "gall",
            select: %{species_id: gt.species_id, name: s.name, taxoncode: s.taxoncode}
        )

      assert bad == [],
             "Found #{length(bad)} gall_traits rows for non-gall species: #{inspect(Enum.take(bad, 10))}"
    end

    test "no gall with datacomplete=true lacks sources" do
      bad =
        Repo.all(
          from s in "species",
            where: s.taxoncode == "gall",
            where: s.datacomplete == true,
            where: s.id not in subquery(from(ss in "species_source", select: ss.species_id)),
            select: %{id: s.id, name: s.name}
        )

      assert bad == [],
             "Found #{length(bad)} complete galls without sources: #{inspect(Enum.take(bad, 10))}"
    end

    test "no undescribed gall has datacomplete=true" do
      bad =
        Repo.all(
          from s in "species",
            join: gt in "gall_traits",
            on: gt.species_id == s.id,
            where: s.taxoncode == "gall",
            where: gt.undescribed == true,
            where: s.datacomplete == true,
            select: %{id: s.id, name: s.name}
        )

      assert bad == [],
             "Found #{length(bad)} undescribed complete galls: #{inspect(Enum.take(bad, 10))}"
    end

    test "no duplicate gallformers_code values" do
      bad =
        Repo.all(
          from gt in "gall_traits",
            where: not is_nil(gt.gallformers_code) and gt.gallformers_code != "",
            group_by: gt.gallformers_code,
            having: count(gt.species_id) > 1,
            select: gt.gallformers_code
        )

      assert bad == [],
             "Found #{length(bad)} duplicate gallformers codes: #{inspect(bad)}"
    end

    test "every gall under an Unknown genus has undescribed=true in gall_traits" do
      bad =
        Repo.all(
          from s in "species",
            join: st in "species_taxonomy",
            on: s.id == st.species_id,
            join: t in "taxonomy",
            on: st.taxonomy_id == t.id and t.type == "genus",
            join: gt in "gall_traits",
            on: s.id == gt.species_id,
            where:
              s.taxoncode == "gall" and
                t.is_placeholder == true and
                gt.undescribed != true,
            select: %{id: s.id, name: s.name, genus: t.name}
        )

      assert bad == [],
             "Found #{length(bad)} galls in Unknown genus without undescribed=true: #{inspect(Enum.take(bad, 10))}"
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown genus naming
  # ---------------------------------------------------------------------------

  describe "unknown genus naming" do
    test "all placeholder genera match the pattern 'Unknown (FamilyName)'" do
      bad =
        Repo.all(
          from t in "taxonomy",
            where:
              t.type == "genus" and
                t.is_placeholder == true and
                not fragment("? LIKE 'Unknown (%)'", t.name),
            select: %{id: t.id, name: t.name}
        )

      assert bad == [],
             "Found #{length(bad)} placeholder genera not matching 'Unknown (Family)': #{inspect(Enum.take(bad, 10))}"
    end

    test "every gall family has exactly one Unknown genus" do
      # Find families that have gall species but no Unknown genus
      # "Plant" description families are host-only, so skip those
      families_missing_unknown =
        Repo.all(
          from f in "taxonomy",
            join: g in "taxonomy",
            on: g.parent_id == f.id and g.type == "genus",
            join: st in "species_taxonomy",
            on: st.taxonomy_id == g.id,
            join: s in "species",
            on: st.species_id == s.id and s.taxoncode == "gall",
            left_join: u in "taxonomy",
            on: u.parent_id == f.id and u.type == "genus" and u.is_placeholder == true,
            where: f.type == "family" and f.description != "Plant",
            group_by: [f.id, f.name],
            having: count(fragment("DISTINCT ?", u.id)) == 0,
            select: %{id: f.id, name: f.name}
        )

      assert families_missing_unknown == [],
             "Found #{length(families_missing_unknown)} gall families without an Unknown genus: #{inspect(Enum.take(families_missing_unknown, 10))}"

      # Families with multiple Unknown genera
      families_multi_unknown =
        Repo.all(
          from f in "taxonomy",
            join: u in "taxonomy",
            on: u.parent_id == f.id and u.type == "genus" and u.is_placeholder == true,
            where: f.type == "family",
            group_by: [f.id, f.name],
            having: count(u.id) > 1,
            select: %{id: f.id, name: f.name, unknown_count: count(u.id)}
        )

      assert families_multi_unknown == [],
             "Found #{length(families_multi_unknown)} families with multiple Unknown genera: #{inspect(Enum.take(families_multi_unknown, 10))}"
    end

    test "no species name starts with a bare 'Unknown ' (should be 'Unknown (Family)')" do
      bad =
        Repo.all(
          from s in "species",
            where:
              fragment("? LIKE 'Unknown %'", s.name) and
                not fragment("? LIKE 'Unknown (%'", s.name),
            select: %{id: s.id, name: s.name}
        )

      assert bad == [],
             "Found #{length(bad)} species with bare 'Unknown' name: #{inspect(Enum.take(bad, 10))}"
    end
  end

  # ---------------------------------------------------------------------------
  # Alias integrity
  # ---------------------------------------------------------------------------

  describe "alias integrity" do
    test "every alias_species row points to a valid alias_id and species_id" do
      bad_alias =
        Repo.all(
          from als in "alias_species",
            left_join: a in "alias",
            on: als.alias_id == a.id,
            where: is_nil(a.id),
            select: %{alias_id: als.alias_id, species_id: als.species_id}
        )

      assert bad_alias == [],
             "Found #{length(bad_alias)} alias_species rows with invalid alias_id: #{inspect(Enum.take(bad_alias, 10))}"

      bad_species =
        Repo.all(
          from als in "alias_species",
            left_join: s in "species",
            on: als.species_id == s.id,
            where: is_nil(s.id),
            select: %{alias_id: als.alias_id, species_id: als.species_id}
        )

      assert bad_species == [],
             "Found #{length(bad_species)} alias_species rows with invalid species_id: #{inspect(Enum.take(bad_species, 10))}"
    end

    test "no alias record exists without at least one alias_species link" do
      orphans =
        Repo.all(
          from a in "alias",
            left_join: als in "alias_species",
            on: a.id == als.alias_id,
            left_join: ta in "taxonomy_alias",
            on: a.id == ta.alias_id,
            where: is_nil(als.alias_id) and is_nil(ta.alias_id),
            select: %{id: a.id, name: a.name, type: a.type}
        )

      assert orphans == [],
             "Found #{length(orphans)} orphaned aliases (no species or taxonomy link): #{inspect(Enum.take(orphans, 10))}"
    end
  end
end
