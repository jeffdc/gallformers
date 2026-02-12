defmodule GallformersWeb.ProdDataE2E.TaxonomyAdminTest do
  @moduledoc """
  E2E browser tests for taxonomy admin cascade delete and genus rename.

  Tests exercise the full browser stack against real production data.
  All writes use the Ecto sandbox so they roll back automatically.
  """
  use GallformersWeb.ProdDataE2ECase

  import Ecto.Query

  alias Gallformers.Repo

  @moduletag :prod_data

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

  defp wait_for_liveview(session) do
    assert_has(session, css(".phx-connected"))
  end

  # Push the "delete" event to the LiveView to open the cascade delete modal.
  # Using execJS because Wallaby's click on phx-click buttons can be unreliable
  # in LiveView forms.
  defp open_delete_modal(session) do
    session
    |> execute_script(
      """
      const view = document.querySelector('[data-phx-main]');
      if (view) {
        window.liveSocket.execJS(view, JSON.stringify([["push", {event: "delete"}]]));
      }
      """,
      []
    )

    :timer.sleep(500)
    session
  end

  # Type the confirmation name and submit the cascade delete modal.
  # The confirmation input uses the InputEvent hook, so we set the value,
  # dispatch an input event to trigger the hook, then submit the form.
  defp confirm_cascade_delete(session, name) do
    session
    |> execute_script(
      """
      const input = document.getElementById('delete-confirmation');
      if (input) {
        input.value = arguments[0];
        input.dispatchEvent(new Event('input', { bubbles: true }));
      }
      """,
      [name]
    )

    # Wait for InputEvent hook to push update_delete_confirmation
    :timer.sleep(500)

    # Submit the form via LiveView event push
    session
    |> execute_script(
      """
      const view = document.querySelector('[data-phx-main]');
      if (view) {
        const js = [["push", {event: "confirm_cascade_delete", data: {confirmation: arguments[0]}}]];
        window.liveSocket.execJS(view, JSON.stringify(js));
      }
      """,
      [name]
    )

    # Wait for the delete + redirect
    :timer.sleep(2000)
    session
  end

  # Fill a taxonomy form field and trigger phx-change validation.
  # Wallaby's fill_in doesn't fire phx-change, so the form stays "not dirty"
  # and the Save button remains disabled. Instead, we set the field value and
  # push the validate event directly.
  defp fill_taxonomy_field(session, field, value) do
    session
    |> execute_script(
      """
      const input = document.querySelector('#taxonomy-form [name="taxonomy[' + arguments[0] + ']"]');
      if (input) {
        input.value = arguments[1];
      }
      // Push the validate event with the full form data
      const form = document.getElementById('taxonomy-form');
      if (form) {
        const formData = new FormData(form);
        const data = {taxonomy: {}};
        for (const [key, val] of formData.entries()) {
          const match = key.match(/taxonomy\\[(.+)\\]/);
          if (match) { data.taxonomy[match[1]] = val; }
        }
        const view = document.querySelector('[data-phx-main]');
        if (view) {
          window.liveSocket.execJS(view, JSON.stringify([["push", {event: "validate", data: data}]]));
        }
      }
      """,
      [field, value]
    )

    :timer.sleep(500)
    session
  end

  # Submit the taxonomy form via LiveView event push.
  defp submit_taxonomy_form(session) do
    session
    |> execute_script(
      """
      const form = document.getElementById('taxonomy-form');
      if (form) {
        const formData = new FormData(form);
        const data = {taxonomy: {}};
        for (const [key, val] of formData.entries()) {
          const match = key.match(/taxonomy\\[(.+)\\]/);
          if (match) { data.taxonomy[match[1]] = val; }
        }
        const view = document.querySelector('[data-phx-main]');
        if (view) {
          window.liveSocket.execJS(view, JSON.stringify([["push", {event: "save", data: data}]]));
        }
      }
      """,
      []
    )

    :timer.sleep(1500)
    session
  end

  # ──────────────────────────────────────────────────────────────────
  # Cascade delete tests
  # ──────────────────────────────────────────────────────────────────

  describe "cascade delete" do
    test "view deletion impact before deleting a genus", %{session: session} do
      genus = find_small_genus()
      assert genus, "Need a small genus (2-5 species) for this test"

      expected_species_count = species_count_for_taxonomy(genus.id)
      assert expected_species_count >= 2

      session
      |> visit("/admin/taxonomy/#{genus.id}")
      |> wait_for_liveview()
      |> open_delete_modal()

      # Modal should appear with impact information
      session
      |> assert_has(css("#cascade-delete-modal"))
      |> assert_has(css("#cascade-delete-modal", text: "#{expected_species_count}"))
      |> assert_has(css("#cascade-delete-modal", text: "species"))
    end

    test "cascade delete a genus removes genus and species", %{session: session} do
      genus = find_small_genus()
      assert genus, "Need a small genus (2-5 species) for this test"

      species_before = species_for_taxonomy(genus.id)
      assert length(species_before) >= 2

      session
      |> visit("/admin/taxonomy/#{genus.id}")
      |> wait_for_liveview()
      |> open_delete_modal()
      |> assert_has(css("#cascade-delete-modal"))
      |> confirm_cascade_delete(genus.name)

      # Should redirect to taxonomy listing with success flash
      session
      |> assert_has(css("[role='alert']", text: "Deleted"))

      # Verify via DB: genus should be gone
      refute taxonomy_exists?(genus.id)

      # Verify via DB: all species under that genus should be gone
      for sp <- species_before do
        remaining =
          Repo.one(from s in "species", where: s.id == ^sp.id, select: count(s.id))

        assert remaining == 0, "Species #{sp.name} (#{sp.id}) should have been deleted"
      end
    end

    test "cascade delete a family removes family, genera, and species", %{session: session} do
      family = find_small_family()
      assert family, "Need a small family (few genera, few species) for this test"

      genera_before = genera_count_for_family(family.id)
      species_before = species_count_for_family(family.id)
      assert genera_before >= 1
      assert species_before >= 1

      session
      |> visit("/admin/taxonomy/#{family.id}")
      |> wait_for_liveview()
      |> open_delete_modal()
      |> assert_has(css("#cascade-delete-modal"))
      |> confirm_cascade_delete(family.name)

      # Should redirect with success flash
      session
      |> assert_has(css("[role='alert']", text: "Deleted"))

      # Verify via DB: family gone
      refute taxonomy_exists?(family.id)

      # Verify via DB: genera under family gone
      assert genera_count_for_family(family.id) == 0

      # Verify via DB: species under those genera gone
      assert species_count_for_family(family.id) == 0
    end

    test "large family shows impact warning with high species count", %{session: session} do
      family = find_large_family()
      assert family, "Need a family with 50+ species for this test"

      expected_species = species_count_for_family(family.id)
      assert expected_species >= 50

      session
      |> visit("/admin/taxonomy/#{family.id}")
      |> wait_for_liveview()
      |> open_delete_modal()

      # Modal should appear with the large count
      session
      |> assert_has(css("#cascade-delete-modal"))
      |> assert_has(css("#cascade-delete-modal", text: "#{expected_species}"))
      |> assert_has(css("#cascade-delete-modal", text: "species"))
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Genus rename cascade tests
  # ──────────────────────────────────────────────────────────────────

  describe "genus rename cascade" do
    test "renaming a genus cascades to species names and creates aliases", %{session: session} do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with 3+ species for this test"

      species_before = species_for_taxonomy(genus.id)
      assert length(species_before) >= 3

      alias_counts_before = Map.new(species_before, fn sp -> {sp.id, alias_count(sp.id)} end)

      new_name = "Testgenus#{System.unique_integer([:positive])}"

      session
      |> visit("/admin/taxonomy/#{genus.id}")
      |> wait_for_liveview()
      |> fill_taxonomy_field("name", new_name)
      |> submit_taxonomy_form()

      # Should see success flash
      session
      |> assert_has(css("[role='alert']", text: "updated successfully"))

      # Verify via DB: genus name updated
      updated_genus =
        Repo.one(from t in "taxonomy", where: t.id == ^genus.id, select: %{name: t.name})

      assert updated_genus.name == new_name

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

    test "rename aliases are scientific type", %{session: session} do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with 3+ species for this test"

      species_before = species_for_taxonomy(genus.id)
      old_alias_ids = get_all_alias_ids(species_before)

      new_name = "Testgenus#{System.unique_integer([:positive])}"

      session
      |> visit("/admin/taxonomy/#{genus.id}")
      |> wait_for_liveview()
      |> fill_taxonomy_field("name", new_name)
      |> submit_taxonomy_form()
      |> assert_has(css("[role='alert']", text: "updated successfully"))

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

    test "rename preserves species count", %{session: session} do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with 3+ species for this test"

      count_before = species_count_for_taxonomy(genus.id)
      new_name = "Testgenus#{System.unique_integer([:positive])}"

      session
      |> visit("/admin/taxonomy/#{genus.id}")
      |> wait_for_liveview()
      |> fill_taxonomy_field("name", new_name)
      |> submit_taxonomy_form()
      |> assert_has(css("[role='alert']", text: "updated successfully"))

      count_after = species_count_for_taxonomy(genus.id)

      assert count_after == count_before,
             "Species count should be unchanged: #{count_before} before, #{count_after} after"
    end

    test "editing description only does not rename species or create aliases", %{
      session: session
    } do
      genus = find_genus_for_rename()
      assert genus, "Need a genus with species for this test"

      species_before = species_for_taxonomy(genus.id)
      alias_counts_before = Map.new(species_before, fn sp -> {sp.id, alias_count(sp.id)} end)

      session
      |> visit("/admin/taxonomy/#{genus.id}")
      |> wait_for_liveview()
      |> fill_taxonomy_field(
        "description",
        "Test description #{System.unique_integer([:positive])}"
      )
      |> submit_taxonomy_form()

      # Should see success flash
      session
      |> assert_has(css("[role='alert']", text: "updated successfully"))

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
  # Edge case tests
  # ──────────────────────────────────────────────────────────────────

  describe "edge cases" do
    test "delete a section does not cascade-delete species", %{session: session} do
      section = find_section()

      if is_nil(section) do
        IO.puts("SKIP: No section found in prod data")
      else
        # Species linked to this section's parent genus should survive
        parent_genus_species_count = species_count_for_taxonomy(section.parent_id)

        session
        |> visit("/admin/taxonomy/#{section.id}")
        |> wait_for_liveview()
        |> open_delete_modal()
        |> assert_has(css("#cascade-delete-modal"))
        |> confirm_cascade_delete(section.name)

        # Should redirect with success flash
        session
        |> assert_has(css("[role='alert']", text: "Deleted"))

        # Section should be gone
        refute taxonomy_exists?(section.id)

        # Parent genus species should still exist
        assert species_count_for_taxonomy(section.parent_id) == parent_genus_species_count
      end
    end

    test "Unknown genus has undescribed species", %{session: session} do
      unknown = find_unknown_genus()

      if is_nil(unknown) do
        IO.puts("SKIP: No Unknown genus found in prod data")
      else
        # Visit the genus page and check species display
        session
        |> visit("/genus/#{unknown.id}")
        |> wait_for_liveview()

        # Species under an Unknown genus should be displayed
        species = species_for_taxonomy(unknown.id)
        assert length(species) > 0, "Unknown genus should have species"

        # The page should render
        session
        |> assert_has(css("body"))
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
