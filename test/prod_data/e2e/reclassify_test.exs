defmodule GallformersWeb.ProdDataE2E.ReclassifyTest do
  @moduledoc """
  E2E browser tests for the reclassify modal on gall and host admin forms.

  Tests exercise the full browser stack against real production data.
  All writes use the Ecto sandbox so they roll back automatically.
  """
  use GallformersWeb.ProdDataE2ECase

  import Ecto.Query

  alias Gallformers.Repo

  @moduletag :prod_data

  # ──────────────────────────────────────────────────────────────────
  # Setup helpers — find real species to test against
  # ──────────────────────────────────────────────────────────────────

  # Find a gall species that has a known genus and family in the taxonomy table.
  # species → species_taxonomy → genus taxonomy row → parent_id → family taxonomy row
  defp find_gall_with_taxonomy do
    Repo.one(
      from s in "species",
        join: st in "species_taxonomy",
        on: st.species_id == s.id,
        join: genus in "taxonomy",
        on: genus.id == st.taxonomy_id and genus.type == "genus",
        join: family in "taxonomy",
        on: family.id == genus.parent_id and family.type == "family",
        where: s.taxoncode == "gall",
        where: not like(genus.name, "Unknown%"),
        select: %{
          id: s.id,
          name: s.name,
          genus_id: genus.id,
          genus_name: genus.name,
          family_id: family.id,
          family_name: family.name
        },
        limit: 1
    )
  end

  # Find a different genus in the same family as the given genus.
  # Genus must have at least one species of the given taxoncode (via species_taxonomy).
  defp find_different_genus_in_family(family_id, exclude_genus_id, taxoncode) do
    Repo.one(
      from t in "taxonomy",
        where: t.parent_id == ^family_id,
        where: t.type == "genus",
        where: t.id != ^exclude_genus_id,
        where: not like(t.name, "Unknown%"),
        where:
          fragment(
            """
            EXISTS (
              SELECT 1 FROM species_taxonomy st
              JOIN species s ON s.id = st.species_id
              WHERE st.taxonomy_id = ? AND s.taxoncode = ?
            )
            """,
            t.id,
            ^taxoncode
          ),
        select: %{id: t.id, name: t.name},
        limit: 1
    )
  end

  # Find a genus in a different family than the given family.
  # Genus must have at least one species of the given taxoncode (via species_taxonomy).
  defp find_genus_in_different_family(exclude_family_id, taxoncode) do
    Repo.one(
      from t in "taxonomy",
        join: parent in "taxonomy",
        on: parent.id == t.parent_id,
        where: t.type == "genus",
        where: parent.type == "family",
        where: parent.id != ^exclude_family_id,
        where: not like(t.name, "Unknown%"),
        where:
          fragment(
            """
            EXISTS (
              SELECT 1 FROM species_taxonomy st
              JOIN species s ON s.id = st.species_id
              WHERE st.taxonomy_id = ? AND s.taxoncode = ?
            )
            """,
            t.id,
            ^taxoncode
          ),
        select: %{
          id: t.id,
          name: t.name,
          family_id: parent.id,
          family_name: parent.name
        },
        limit: 1
    )
  end

  # Find an undescribed gall (under an Unknown/placeholder genus).
  defp find_undescribed_gall do
    Repo.one(
      from s in "species",
        join: st in "species_taxonomy",
        on: st.species_id == s.id,
        join: genus in "taxonomy",
        on: genus.id == st.taxonomy_id and genus.type == "genus",
        where: s.taxoncode == "gall",
        where: like(genus.name, "Unknown%"),
        select: %{id: s.id, name: s.name, genus_id: genus.id, genus_name: genus.name},
        limit: 1
    )
  end

  # Find a host (plant) species with taxonomy.
  defp find_host_with_taxonomy do
    Repo.one(
      from s in "species",
        join: st in "species_taxonomy",
        on: st.species_id == s.id,
        join: genus in "taxonomy",
        on: genus.id == st.taxonomy_id and genus.type == "genus",
        join: family in "taxonomy",
        on: family.id == genus.parent_id and family.type == "family",
        where: s.taxoncode == "plant",
        where: not like(genus.name, "Unknown%"),
        select: %{
          id: s.id,
          name: s.name,
          genus_id: genus.id,
          genus_name: genus.name,
          family_id: family.id,
          family_name: family.name
        },
        limit: 1
    )
  end

  # Count aliases for a species via the alias_species join table.
  defp alias_count(species_id) do
    Repo.one(
      from as in "alias_species",
        where: as.species_id == ^species_id,
        select: count(as.alias_id)
    )
  end

  # ──────────────────────────────────────────────────────────────────
  # Shared interaction helpers
  # ──────────────────────────────────────────────────────────────────

  # Wait for LiveView to be connected and ready.
  defp wait_for_liveview(session) do
    assert_has(session, css(".phx-connected"))
  end

  # Open the reclassify modal by clicking the Rename/Reclassify button.
  defp open_reclassify_modal(session) do
    session
    |> click(css("button", text: "Rename/Reclassify"))
    |> assert_has(css("#reclassify-modal"))
  end

  # Push a LiveView event to the reclassify LiveComponent via liveSocket.execJS.
  # Constructs a JS command that pushes an event to the component's CID.
  defp push_to_component(session, event, payload \\ %{}) do
    json_payload = Jason.encode!(payload)

    session
    |> execute_script(
      """
      // Find the reclassify component root and its CID
      // The component wraps in <div id="reclassify"> which has a child with data-phx-component
      const compRoot = document.querySelector('#reclassify [data-phx-component]') ||
                        document.getElementById('reclassify');
      if (!compRoot) { console.error('push_to_component: no component element found'); return; }

      // Get the CID — either from data-phx-component directly or from a child element
      const phxComp = compRoot.dataset?.phxComponent ||
                       compRoot.querySelector('[data-phx-component]')?.dataset?.phxComponent;
      if (!phxComp) { console.error('push_to_component: no phx-component CID found'); return; }
      const cid = parseInt(phxComp);

      // Build LiveView JS push command and execute it
      // format: [["push", {event: "...", target: CID, data: {...}}]]
      const js = [["push", {event: arguments[0], target: cid, data: JSON.parse(arguments[1])}]];
      window.liveSocket.execJS(compRoot, JSON.stringify(js));
      """,
      [event, json_payload]
    )

    :timer.sleep(500)
    session
  end

  # Type into the family typeahead in the reclassify modal and select a result.
  defp search_and_select_family(session, family_name) do
    # Clear existing family selection, then search, then select
    session
    |> push_to_component("reclassify_clear_family")
    |> push_to_component("reclassify_search_family", %{value: family_name})
    |> assert_has(css("#reclassify-family-picker-results"))
    |> click(css("#reclassify-family-picker-results button", count: :any, at: 0))
  end

  # Type into the genus typeahead in the reclassify modal and select a result.
  defp search_and_select_genus(session, genus_name) do
    # Clear existing genus selection, then search, then select
    session
    |> push_to_component("reclassify_clear_genus")
    |> push_to_component("reclassify_search_genus", %{value: genus_name})
    |> assert_has(css("#reclassify-genus-picker-results"))
    |> click(css("#reclassify-genus-picker-results button", count: :any, at: 0))
  end

  # Set the epithet value by pushing the event directly to the component.
  defp set_epithet(session, new_epithet) do
    push_to_component(session, "update_reclassify_epithet", %{value: new_epithet})
  end

  # Click the Save button in the reclassify modal.
  defp click_reclassify_save(session) do
    session
    |> click(css("#reclassify-modal button", text: "Save"))
  end

  # Click the Cancel button in the reclassify modal.
  defp click_reclassify_cancel(session) do
    session
    |> click(css("#reclassify-modal button", text: "Cancel"))

    # Give time for the modal to animate out
    :timer.sleep(300)
    session
  end

  # ──────────────────────────────────────────────────────────────────
  # Test: Reclassify gall to different genus in same family
  # ──────────────────────────────────────────────────────────────────

  describe "reclassify gall to different genus in same family" do
    test "changes genus and creates alias", %{session: session} do
      gall = find_gall_with_taxonomy()
      assert gall, "Need a gall with taxonomy for this test"

      target_genus =
        find_different_genus_in_family(gall.family_id, gall.genus_id, "gall")

      assert target_genus,
             "Need a different genus in #{gall.family_name} for this test"

      original_alias_count = alias_count(gall.id)

      session
      |> visit("/admin/galls/#{gall.id}")
      |> wait_for_liveview()
      |> open_reclassify_modal()
      |> search_and_select_genus(target_genus.name)
      |> click_reclassify_save()

      # Should see success flash
      session
      |> assert_has(css("[role='alert']", text: "updated successfully"))

      # Verify the species name now starts with the new genus
      session
      |> assert_has(css("input.italic[disabled][value*='#{target_genus.name}']"))

      # Verify alias was created
      assert alias_count(gall.id) > original_alias_count
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Test: Reclassify gall to genus in different family
  # ──────────────────────────────────────────────────────────────────

  describe "reclassify gall to genus in different family" do
    test "changes family and genus, creates alias", %{session: session} do
      gall = find_gall_with_taxonomy()
      assert gall, "Need a gall with taxonomy for this test"

      target = find_genus_in_different_family(gall.family_id, "gall")
      assert target, "Need a genus in a different family for this test"

      original_alias_count = alias_count(gall.id)

      session
      |> visit("/admin/galls/#{gall.id}")
      |> wait_for_liveview()
      |> open_reclassify_modal()
      |> search_and_select_family(target.family_name)
      |> search_and_select_genus(target.name)
      |> click_reclassify_save()

      # Should see success flash
      session
      |> assert_has(css("[role='alert']", text: "updated successfully"))

      # Verify the species name now starts with the new genus
      session
      |> assert_has(css("input.italic[disabled][value*='#{target.name}']"))

      # Verify alias was created
      assert alias_count(gall.id) > original_alias_count
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Test: Rename epithet only (same genus)
  # ──────────────────────────────────────────────────────────────────

  describe "rename epithet only" do
    test "changes epithet without changing genus", %{session: session} do
      gall = find_gall_with_taxonomy()
      assert gall, "Need a gall with taxonomy for this test"

      new_epithet = "testepithet#{System.unique_integer([:positive])}"
      original_alias_count = alias_count(gall.id)

      session
      |> visit("/admin/galls/#{gall.id}")
      |> wait_for_liveview()
      |> open_reclassify_modal()
      |> set_epithet(new_epithet)
      |> click_reclassify_save()

      # Should see success flash
      session
      |> assert_has(css("[role='alert']", text: "updated successfully"))

      # Verify the species name contains the new epithet
      session
      |> assert_has(css("input.italic[disabled][value*='#{new_epithet}']"))

      # Verify the genus portion is unchanged
      session
      |> assert_has(css("input.italic[disabled][value*='#{gall.genus_name}']"))

      # Verify alias was created for old name
      assert alias_count(gall.id) > original_alias_count
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Test: No-op — open modal and close without changes
  # ──────────────────────────────────────────────────────────────────

  describe "no-op close modal" do
    test "closing modal without changes preserves species", %{session: session} do
      gall = find_gall_with_taxonomy()
      assert gall, "Need a gall with taxonomy for this test"

      original_alias_count = alias_count(gall.id)

      session
      |> visit("/admin/galls/#{gall.id}")
      |> wait_for_liveview()
      |> open_reclassify_modal()
      |> click_reclassify_cancel()

      # Modal should be hidden (it stays in DOM but becomes invisible)
      # The ReclassifyLive component sets show=false, so the :if={@show} removes the modal
      session
      |> refute_has(css("#reclassify-modal", visible: true))

      # Species name should be unchanged
      session
      |> assert_has(css("input.italic[disabled][value='#{gall.name}']"))

      # No new aliases
      assert alias_count(gall.id) == original_alias_count
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Test: No-op — submit without making changes
  # ──────────────────────────────────────────────────────────────────

  describe "no-op submit without changes" do
    test "submitting unchanged data creates no aliases", %{session: session} do
      gall = find_gall_with_taxonomy()
      assert gall, "Need a gall with taxonomy for this test"

      original_alias_count = alias_count(gall.id)

      session
      |> visit("/admin/galls/#{gall.id}")
      |> wait_for_liveview()
      |> open_reclassify_modal()
      |> click_reclassify_save()

      # Should see "No changes made" info flash
      session
      |> assert_has(css("[role='alert']", text: "No changes"))

      # No new aliases
      assert alias_count(gall.id) == original_alias_count
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Test: Reclassify undescribed gall to real genus
  # ──────────────────────────────────────────────────────────────────

  describe "reclassify undescribed gall" do
    test "moves from Unknown genus to real genus", %{session: session} do
      gall = find_undescribed_gall()

      if is_nil(gall) do
        IO.puts("SKIP: No undescribed gall found in prod data")
      else
        # Find a real (non-Unknown) genus to move to — use gall taxoncode
        target = find_genus_in_different_family(0, "gall")
        assert target, "Need a non-Unknown genus for this test"

        session
        |> visit("/admin/galls/#{gall.id}")
        |> wait_for_liveview()
        |> open_reclassify_modal()
        |> search_and_select_family(target.family_name)
        |> search_and_select_genus(target.name)
        |> click_reclassify_save()

        # Should see success flash
        session
        |> assert_has(css("[role='alert']", text: "updated successfully"))

        # Species name should no longer start with "Unknown"
        session
        |> refute_has(css("input.italic[disabled][value^='Unknown']"))
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Test: Reclassify host to different genus
  # ──────────────────────────────────────────────────────────────────

  describe "reclassify host to different genus" do
    test "changes host genus and creates alias", %{session: session} do
      host = find_host_with_taxonomy()
      assert host, "Need a host with taxonomy for this test"

      target_genus =
        find_different_genus_in_family(host.family_id, host.genus_id, "plant")

      assert target_genus,
             "Need a different genus in #{host.family_name} for this test"

      original_alias_count = alias_count(host.id)

      session
      |> visit("/admin/hosts/#{host.id}")
      |> wait_for_liveview()
      |> open_reclassify_modal()
      |> search_and_select_genus(target_genus.name)
      |> click_reclassify_save()

      # Should see success flash
      session
      |> assert_has(css("[role='alert']", text: "updated successfully"))

      # Verify the species name now starts with the new genus
      session
      |> assert_has(css("input.italic[disabled][value*='#{target_genus.name}']"))

      # Verify alias was created
      assert alias_count(host.id) > original_alias_count
    end
  end
end
