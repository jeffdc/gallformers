defmodule GallformersWeb.E2E.TaxonomyAdminTest do
  @moduledoc """
  E2E browser tests for taxonomy admin cascade delete and genus rename.

  Tests exercise the full browser stack against real production data.
  All writes use the Ecto sandbox so they roll back automatically.
  """
  use GallformersWeb.E2ECase

  import Ecto.Query
  import Fluffy.Locator, only: [by_css: 1]

  alias Gallformers.Repo

  @moduletag :e2e
  @moduletag :e2e_admin

  # ──────────────────────────────────────────────────────────────────
  # Setup helpers — find real taxonomy entries to test against
  # ──────────────────────────────────────────────────────────────────

  # Find a small genus (2-5 species) suitable for delete testing.
  defp find_small_genus do
    Repo.one(
      from g in "taxonomy",
        where: g.type == "genus",
        where: not like(g.name, "Unknown%"),
        where:
          fragment(
            """
            (SELECT COUNT(*) FROM species_taxonomy st WHERE st.taxonomy_id = ?)
            BETWEEN 2 AND 5
            """,
            g.id
          ),
        select: %{id: g.id, name: g.name, parent_id: g.parent_id},
        limit: 1
    )
  end

  # Find a small family (few genera, few species total) for delete testing.
  defp find_small_family do
    Repo.one(
      from f in "taxonomy",
        where: f.type == "family",
        where:
          fragment(
            """
            (SELECT COUNT(*) FROM taxonomy g WHERE g.parent_id = ? AND g.type = 'genus') BETWEEN 1 AND 3
            AND (
              SELECT COUNT(*) FROM species_taxonomy st
              JOIN taxonomy g ON g.id = st.taxonomy_id
              WHERE g.parent_id = ? AND g.type = 'genus'
            ) BETWEEN 1 AND 10
            """,
            f.id,
            f.id
          ),
        select: %{id: f.id, name: f.name},
        limit: 1
    )
  end

  # Find a large family (50+ species) for impact display testing.
  defp find_large_family do
    Repo.one(
      from f in "taxonomy",
        where: f.type == "family",
        where:
          fragment(
            """
            (
              SELECT COUNT(*) FROM species_taxonomy st
              JOIN taxonomy g ON g.id = st.taxonomy_id
              WHERE g.parent_id = ? AND g.type = 'genus'
            ) >= 50
            """,
            f.id
          ),
        select: %{id: f.id, name: f.name},
        limit: 1
    )
  end

  # Find a genus with 3+ species for rename testing.
  defp find_genus_for_rename do
    Repo.one(
      from g in "taxonomy",
        where: g.type == "genus",
        where: not like(g.name, "Unknown%"),
        where:
          fragment(
            """
            (SELECT COUNT(*) FROM species_taxonomy st WHERE st.taxonomy_id = ?)
            BETWEEN 3 AND 10
            """,
            g.id
          ),
        select: %{id: g.id, name: g.name, parent_id: g.parent_id},
        limit: 1
    )
  end

  # Find a section with no species linked directly (so simple delete succeeds).
  defp find_section do
    Repo.one(
      from s in "taxonomy",
        where: s.type == "section",
        where:
          fragment(
            """
            NOT EXISTS (
              SELECT 1 FROM species_taxonomy st WHERE st.taxonomy_id = ?
            )
            """,
            s.id
          ),
        select: %{id: s.id, name: s.name, parent_id: s.parent_id},
        limit: 1
    )
  end

  # Find an Unknown genus that has undescribed species.
  defp find_unknown_genus do
    Repo.one(
      from g in "taxonomy",
        where: g.type == "genus",
        where: like(g.name, "Unknown%"),
        where:
          fragment(
            """
            EXISTS (
              SELECT 1 FROM species_taxonomy st
              JOIN species s ON s.id = st.species_id
              WHERE st.taxonomy_id = ?
            )
            """,
            g.id
          ),
        select: %{id: g.id, name: g.name},
        limit: 1
    )
  end

  # Count species linked to a taxonomy entry via species_taxonomy.
  defp species_count_for_taxonomy(taxonomy_id) do
    Repo.one(
      from st in "species_taxonomy",
        where: st.taxonomy_id == ^taxonomy_id,
        select: count(st.species_id)
    )
  end

  # Get species names linked to a taxonomy entry.
  defp species_for_taxonomy(taxonomy_id) do
    Repo.all(
      from st in "species_taxonomy",
        join: s in "species",
        on: s.id == st.species_id,
        where: st.taxonomy_id == ^taxonomy_id,
        select: %{id: s.id, name: s.name}
    )
  end

  # Count aliases for a species via the alias_species join table.
  defp alias_count(species_id) do
    Repo.one(
      from as_join in "alias_species",
        where: as_join.species_id == ^species_id,
        select: count(as_join.alias_id)
    )
  end

  # Check if a taxonomy entry exists.
  defp taxonomy_exists?(taxonomy_id) do
    Repo.one(
      from t in "taxonomy",
        where: t.id == ^taxonomy_id,
        select: count(t.id)
    ) > 0
  end

  # Count genera under a family.
  defp genera_count_for_family(family_id) do
    Repo.one(
      from t in "taxonomy",
        where: t.parent_id == ^family_id and t.type == "genus",
        select: count(t.id)
    )
  end

  # Count all species under a family (through its genera).
  defp species_count_for_family(family_id) do
    Repo.one(
      from st in "species_taxonomy",
        join: g in "taxonomy",
        on: g.id == st.taxonomy_id,
        where: g.parent_id == ^family_id and g.type == "genus",
        select: count(st.species_id)
    )
  end

  # ──────────────────────────────────────────────────────────────────
  # Shared interaction helpers
  # ──────────────────────────────────────────────────────────────────

  # Poll a DB condition until it holds (Playwright's default 5s expect timeout).
  # Use instead of flaky flash alert assertions.
  defp wait_for_db(conn, condition, opts) do
    message = Keyword.get(opts, :message, "DB condition not met within timeout")

    Fluffy.Expect.expect(
      conn,
      Fluffy.Expect.poll(fn _session -> condition.() end, &assert(&1, message))
    )
  end

  # Click the Delete button to open the cascade delete modal.
  defp open_delete_modal(conn) do
    conn
    |> click_button("Delete")
  end

  # Type the confirmation name and submit the cascade delete form.
  defp confirm_cascade_delete(conn, name) do
    conn
    |> Fluffy.Playwright.press_sequentially(by_css("#delete-confirmation"), name)
    # Waits for the InputEvent hook to enable the submit button
    |> click_button("Delete Forever")
  end

  # Fill a taxonomy form field using Playwright's native interactions.
  # Select all existing text (Meta+a on macOS, Control+a elsewhere), then type the new value
  # which fires input/change events that LiveView picks up via phx-change.
  defp fill_taxonomy_field(conn, field, value) do
    locator = by_css(~s(#taxonomy-form [name="taxonomy[#{field}]"]))

    conn
    |> Fluffy.click(locator)
    |> Fluffy.press(locator, "ControlOrMeta+a")
    |> Fluffy.Playwright.press_sequentially(locator, value)

    # Wait for LiveView to process phx-change
    :timer.sleep(500)
    conn
  end

  # Submit the taxonomy form by clicking Save.
  defp submit_taxonomy_form(conn) do
    conn
    |> click_button("Save")
  end

  # ──────────────────────────────────────────────────────────────────
  # Cascade delete tests
  # ──────────────────────────────────────────────────────────────────

  describe "cascade delete" do
    test "view deletion impact before deleting a genus", %{conn: conn} do
      genus = find_small_genus()
      assert genus, "Need a small genus (2-5 species) for this test"

      expected_species_count = species_count_for_taxonomy(genus.id)
      assert expected_species_count >= 2

      conn
      |> visit("/admin/taxonomy/#{genus.id}")
      |> open_delete_modal()

      # Modal should appear with impact information
      conn
      |> assert_has("#cascade-delete-modal")
      |> assert_has("#cascade-delete-modal", text: "#{expected_species_count}")
      |> assert_has("#cascade-delete-modal", text: "species")
    end

    test "cascade delete a genus removes genus and species", %{conn: conn} do
      genus = find_small_genus()
      assert genus, "Need a small genus (2-5 species) for this test"

      species_before = species_for_taxonomy(genus.id)
      assert length(species_before) >= 2

      conn
      |> visit("/admin/taxonomy/#{genus.id}")
      |> open_delete_modal()
      |> assert_has("#cascade-delete-modal")
      |> confirm_cascade_delete(genus.name)

      # Should redirect to taxonomy listing with success flash
      conn
      |> assert_has("[role='alert']", text: "Deleted")

      # Verify via DB: genus should be gone
      refute taxonomy_exists?(genus.id)

      # Verify via DB: all species under that genus should be gone
      for sp <- species_before do
        remaining =
          Repo.one(from s in "species", where: s.id == ^sp.id, select: count(s.id))

        assert remaining == 0, "Species #{sp.name} (#{sp.id}) should have been deleted"
      end
    end

    test "cascade delete a family removes family, genera, and species", %{conn: conn} do
      family = find_small_family()
      assert family, "Need a small family (few genera, few species) for this test"

      genera_before = genera_count_for_family(family.id)
      species_before = species_count_for_family(family.id)
      assert genera_before >= 1
      assert species_before >= 1

      conn
      |> visit("/admin/taxonomy/#{family.id}")
      |> open_delete_modal()
      |> assert_has("#cascade-delete-modal")
      |> confirm_cascade_delete(family.name)

      # Should redirect with success flash
      conn
      |> assert_has("[role='alert']", text: "Deleted")

      # Verify via DB: family gone
      refute taxonomy_exists?(family.id)

      # Verify via DB: genera under family gone
      assert genera_count_for_family(family.id) == 0

      # Verify via DB: species under those genera gone
      assert species_count_for_family(family.id) == 0
    end

    test "large family shows impact warning with high species count", %{conn: conn} do
      family = find_large_family()
      assert family, "Need a family with 50+ species for this test"

      expected_species = species_count_for_family(family.id)
      assert expected_species >= 50

      conn
      |> visit("/admin/taxonomy/#{family.id}")
      |> open_delete_modal()

      # Modal should appear with the large count
      conn
      |> assert_has("#cascade-delete-modal")
      |> assert_has("#cascade-delete-modal", text: "#{expected_species}")
      |> assert_has("#cascade-delete-modal", text: "species")
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Genus rename cascade tests
  # ──────────────────────────────────────────────────────────────────

  describe "genus rename cascade" do
    test "renaming a genus cascades to species names and creates aliases", %{conn: conn} do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with 3+ species for this test"

      species_before = species_for_taxonomy(genus.id)
      assert length(species_before) >= 3

      alias_counts_before = Map.new(species_before, fn sp -> {sp.id, alias_count(sp.id)} end)

      new_name = "Testgenus#{System.unique_integer([:positive])}"

      conn
      |> visit("/admin/taxonomy/#{genus.id}")
      |> fill_taxonomy_field("name", new_name)
      |> submit_taxonomy_form()

      # Wait for DB to reflect the rename
      wait_for_db(
        conn,
        fn ->
          Repo.one(from t in "taxonomy", where: t.id == ^genus.id, select: t.name) == new_name
        end,
        message: "Genus #{genus.id} was not renamed to #{new_name} in time"
      )

      # Verify via DB: each species name starts with the new genus name
      species_after = species_for_taxonomy(genus.id)
      assert length(species_after) == length(species_before)

      for sp <- species_after do
        assert String.starts_with?(sp.name, new_name),
               "Species #{sp.name} should start with #{new_name}"
      end

      # Verify via DB: each species got a new alias
      for sp <- species_after do
        assert alias_count(sp.id) > Map.get(alias_counts_before, sp.id, 0),
               "Species #{sp.id} should have a new alias after genus rename"
      end
    end

    test "rename aliases are scientific type", %{conn: conn} do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with 3+ species for this test"

      species_before = species_for_taxonomy(genus.id)
      old_alias_ids = get_all_alias_ids(species_before)

      new_name = "Testgenus#{System.unique_integer([:positive])}"

      conn
      |> visit("/admin/taxonomy/#{genus.id}")
      |> fill_taxonomy_field("name", new_name)
      |> submit_taxonomy_form()

      # Wait for DB to reflect the rename
      wait_for_db(
        conn,
        fn ->
          Repo.one(from t in "taxonomy", where: t.id == ^genus.id, select: t.name) == new_name
        end,
        message: "Genus #{genus.id} was not renamed to #{new_name} in time"
      )

      # Find new aliases created after the rename
      for sp <- species_before do
        new_aliases =
          Repo.all(
            from as_join in "alias_species",
              join: a in "alias",
              on: a.id == as_join.alias_id,
              where: as_join.species_id == ^sp.id,
              where: as_join.alias_id not in ^old_alias_ids,
              select: %{type: a.type, name: a.name}
          )

        for alias_rec <- new_aliases do
          assert alias_rec.type == "scientific",
                 "New alias '#{alias_rec.name}' should be scientific type, got: #{alias_rec.type}"
        end
      end
    end

    test "rename preserves species count", %{conn: conn} do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with 3+ species for this test"

      count_before = species_count_for_taxonomy(genus.id)
      new_name = "Testgenus#{System.unique_integer([:positive])}"

      conn
      |> visit("/admin/taxonomy/#{genus.id}")
      |> fill_taxonomy_field("name", new_name)
      |> submit_taxonomy_form()

      # Wait for DB to reflect the rename
      wait_for_db(
        conn,
        fn ->
          Repo.one(from t in "taxonomy", where: t.id == ^genus.id, select: t.name) == new_name
        end,
        message: "Genus #{genus.id} was not renamed to #{new_name} in time"
      )

      count_after = species_count_for_taxonomy(genus.id)

      assert count_after == count_before,
             "Species count should be unchanged: #{count_before} before, #{count_after} after"
    end

    test "editing description only does not rename species or create aliases", %{
      conn: conn
    } do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with species for this test"

      species_before = species_for_taxonomy(genus.id)
      alias_counts_before = Map.new(species_before, fn sp -> {sp.id, alias_count(sp.id)} end)

      new_desc = "Test description #{System.unique_integer([:positive])}"

      conn
      |> visit("/admin/taxonomy/#{genus.id}")
      |> fill_taxonomy_field("description", new_desc)
      |> submit_taxonomy_form()

      # Wait for DB to reflect the description update
      wait_for_db(
        conn,
        fn ->
          Repo.one(from t in "taxonomy", where: t.id == ^genus.id, select: t.description) ==
            new_desc
        end,
        message: "Genus #{genus.id} description was not updated in time"
      )

      # Verify: no species were renamed
      species_after = species_for_taxonomy(genus.id)

      for sp <- species_after do
        original = Enum.find(species_before, fn s -> s.id == sp.id end)
        assert sp.name == original.name, "Species #{sp.id} should not have been renamed"
      end

      # Verify: no new aliases created
      for sp <- species_after do
        assert alias_count(sp.id) == Map.get(alias_counts_before, sp.id, 0),
               "Species #{sp.id} should not have new aliases"
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Genus rename collision tests
  # ──────────────────────────────────────────────────────────────────

  describe "genus rename collision" do
    test "genus rename with collision is rejected, genus unchanged", %{conn: conn} do
      # Find a real family to create test data under
      family =
        Repo.one(
          from f in "taxonomy",
            where: f.type == "family",
            limit: 1,
            select: %{id: f.id, name: f.name}
        )

      assert family, "Need a family for this test"

      # Create a test genus under this family
      unique = System.unique_integer([:positive])
      test_genus_name = "Collisiongenus#{unique}"

      {:ok, test_genus} =
        Gallformers.Taxonomy.create_taxonomy(%{
          name: test_genus_name,
          type: "genus",
          parent_id: family.id
        })

      # Create a species under this genus
      {:ok, test_species} =
        Repo.insert(%Gallformers.Species.Species{
          name: "#{test_genus_name} testspecies",
          taxoncode: "gall",
          datacomplete: false
        })

      Gallformers.Taxonomy.link_species_to_taxonomy(test_species.id, test_genus.id)

      # Pick a target name that will collide
      target_genus_name = "Targetgenus#{unique}"

      # Create a species whose name matches what the rename would produce
      {:ok, _blocker} =
        Repo.insert(%Gallformers.Species.Species{
          name: "#{target_genus_name} testspecies",
          taxoncode: "gall",
          datacomplete: false
        })

      # Navigate to the taxonomy admin page for our test genus
      conn
      |> visit("/admin/taxonomy/#{test_genus.id}")
      |> fill_taxonomy_field("name", target_genus_name)
      |> submit_taxonomy_form()

      # Nothing observable to wait for when the save is rejected
      :timer.sleep(1500)

      # Verify genus name unchanged in DB (collision should have been rejected)
      unchanged =
        Repo.one(
          from t in "taxonomy",
            where: t.id == ^test_genus.id,
            select: %{name: t.name}
        )

      assert unchanged.name == test_genus_name,
             "Genus should not have been renamed due to collision"
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Edge case tests
  # ──────────────────────────────────────────────────────────────────

  describe "edge cases" do
    test "delete a section does not cascade-delete species", %{conn: conn} do
      section = find_section()

      if is_nil(section) do
        IO.puts("SKIP: No section found in prod data")
      else
        # Species linked to this section's parent genus should survive
        parent_genus_species_count = species_count_for_taxonomy(section.parent_id)

        conn
        |> visit("/admin/taxonomy/#{section.id}")
        |> open_delete_modal()
        |> assert_has("#cascade-delete-modal")
        |> confirm_cascade_delete(section.name)

        # Should redirect with success flash
        conn
        |> assert_has("[role='alert']", text: "Deleted")

        # Section should be gone
        refute taxonomy_exists?(section.id)

        # Parent genus species should still exist
        assert species_count_for_taxonomy(section.parent_id) == parent_genus_species_count
      end
    end

    test "Unknown genus has undescribed species", %{conn: conn} do
      unknown = find_unknown_genus()

      if is_nil(unknown) do
        IO.puts("SKIP: No Unknown genus found in prod data")
      else
        # Visit the genus page and check species display
        conn
        |> visit("/genus/#{unknown.id}")

        # Species under an Unknown genus should be displayed
        species = species_for_taxonomy(unknown.id)
        assert length(species) > 0, "Unknown genus should have species"

        # The page should render
        conn
        |> assert_has("body")
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────────

  # Get all existing alias IDs for a list of species (for before/after comparison).
  defp get_all_alias_ids(species_list) do
    species_ids = Enum.map(species_list, & &1.id)

    Repo.all(
      from as_join in "alias_species",
        where: as_join.species_id in ^species_ids,
        select: as_join.alias_id
    )
  end
end
