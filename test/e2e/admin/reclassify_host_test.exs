defmodule GallformersWeb.E2E.ReclassifyHostTest do
  @moduledoc """
  E2E browser test for the reclassify modal on the host admin form.

  Separated from the gall reclassify tests because the host form page is
  significantly heavier (range map, country drill-down) and needs to run
  in its own ExUnit invocation to avoid LiveView mount timing issues.
  """
  use GallformersWeb.E2ECase

  import Ecto.Query

  alias Gallformers.Repo

  @moduletag :e2e
  @moduletag :e2e_admin_host

  # ──────────────────────────────────────────────────────────────────
  # Setup helpers
  # ──────────────────────────────────────────────────────────────────

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

  # Find a different genus in the same family as the given genus.
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

  # Count aliases for a species via the alias_species join table.
  defp alias_count(species_id) do
    Repo.one(
      from as in "alias_species",
        where: as.species_id == ^species_id,
        select: count(as.alias_id)
    )
  end

  # ──────────────────────────────────────────────────────────────────
  # Interaction helpers
  # ──────────────────────────────────────────────────────────────────

  defp open_reclassify_modal(conn) do
    conn
    |> click_button("Rename/Reclassify")
    |> assert_has("#reclassify-modal")
  end

  defp push_to_component(conn, event, payload \\ %{}) do
    json_payload = Jason.encode!(payload)

    js = """
    (function() {
      const compRoot = document.querySelector('#reclassify [data-phx-component]') ||
                        document.getElementById('reclassify');
      if (!compRoot) { console.error('push_to_component: no component element found'); return; }

      const phxComp = compRoot.dataset?.phxComponent ||
                       compRoot.querySelector('[data-phx-component]')?.dataset?.phxComponent;
      if (!phxComp) { console.error('push_to_component: no phx-component CID found'); return; }
      const cid = parseInt(phxComp);

      const js = [["push", {event: "#{event}", target: cid, data: #{json_payload}\}]];
      window.liveSocket.execJS(compRoot, JSON.stringify(js));
    })()
    """

    conn |> unwrap(&Playwright.Page.evaluate!(&1, js))

    :timer.sleep(500)
    conn
  end

  defp search_and_select_genus(conn, genus_name) do
    conn
    |> push_to_component("reclassify_clear_genus")
    |> push_to_component("reclassify_search_genus", %{value: genus_name})
    |> assert_has("#reclassify-genus-picker-results")
    |> unwrap(&Playwright.Page.click!(&1, "#reclassify-genus-picker-results button"))
    |> assert_has("#reclassify-genus-picker-selected")
  end

  defp click_reclassify_save(conn) do
    conn
    |> unwrap(fn page ->
      page
      |> Playwright.Page.locator("#reclassify-modal button")
      |> Playwright.Locator.get_by_text("Save")
      |> Playwright.Locator.click!()
    end)
  end

  # ──────────────────────────────────────────────────────────────────
  # Test
  # ──────────────────────────────────────────────────────────────────

  describe "reclassify host to different genus" do
    test "changes host genus and creates alias", %{conn: conn} do
      host = find_host_with_taxonomy()
      assert host, "Need a host with taxonomy for this test"

      target_genus =
        find_different_genus_in_family(host.family_id, host.genus_id, "plant")

      assert target_genus,
             "Need a different genus in #{host.family_name} for this test"

      original_alias_count = alias_count(host.id)

      conn
      |> visit("/admin/hosts/#{host.id}")
      |> open_reclassify_modal()
      |> search_and_select_genus(target_genus.name)
      |> click_reclassify_save()

      # Should see success flash
      |> assert_has("[role='alert']", text: "updated successfully")

      # Verify the species name now starts with the new genus
      |> assert_has("input.italic[disabled][value*='#{target_genus.name}']")

      # Verify alias was created
      assert alias_count(host.id) > original_alias_count
    end
  end
end
