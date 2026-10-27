defmodule GallformersWeb.Admin.TaxonomyLive.EditTest do
  @moduledoc """
  A taxon's page in the taxonomy admin (matter a856, Task 9): rename,
  move, synonyms and common names, section membership, a plant's flags and
  WCVP link, images, and delete when nothing refers to it. Every write is
  the signed-in admin's, through `Gallformers.Import`, and in the replay
  log. (The Host range editor is `RangeEditorTest`.)
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Ecto.Query, only: [from: 2]
  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_audit_changes: 0]
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Tess Taxa")
    %{conn: conn, actor: Actor.user(user.id, "Tess Taxa")}
  end

  defp uniq, do: System.unique_integer([:positive])

  defp taxonomy_edits(op),
    do: for(e <- Import.list_replay_entries(), e.kind == :taxonomy_edit, e.key["op"] == op, do: e)

  # A plant genus (with sections when asked) in a family.
  defp genus(name \\ nil) do
    family = plant_fixture(rank: :family, name: "Editaceae#{uniq()}")
    plant_fixture(rank: :genus, name: name || "Editgenus#{uniq()}", parent: family)
  end

  describe "mounting" do
    test "shows the taxon's name, rank and lineage, linking each ancestor", %{conn: conn} do
      genus = genus()
      plant = plant_fixture(name: "#{Taxa.accepted_name(genus)} shown", parent: genus)

      {:ok, view, html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      assert html =~ "#{Taxa.accepted_name(genus)} shown"
      assert html =~ "Species"
      assert has_element?(view, "#taxon-lineage a[href='/admin/taxonomy/#{genus.id}']")
      assert has_element?(view, "a[href='/host/#{plant.id}']")
    end

    test "an unknown taxon goes back to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/taxonomy"}}} =
               live(conn, ~p"/admin/taxonomy/999999999")
    end

    test "requires an admin", %{conn: _conn} do
      conn = get(build_conn(), ~p"/admin/taxonomy/1")
      assert redirected_to(conn) =~ "/"
    end
  end

  describe "renaming" do
    test "renames the taxon, keeping the old name as a synonym, logged for replay",
         %{conn: conn} do
      genus = genus()
      plant = plant_fixture(name: "#{Taxa.accepted_name(genus)} oldname", parent: genus)
      new_name = "#{Taxa.accepted_name(genus)} newname"

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")
      html = view |> form("#rename-form", rename: %{name: new_name}) |> render_submit()

      assert html =~ "Renamed to #{new_name}"
      assert Taxa.accepted_name(plant.id) == new_name

      assert "#{Taxa.accepted_name(genus)} oldname" in Enum.map(
               Taxa.list_synonyms(plant),
               & &1.name
             )

      assert [%{payload: %{"name" => ^new_name}}] = taxonomy_edits("rename")
      assert has_element?(view, "#synonyms", "oldname")
    end
  end

  describe "moving" do
    test "moves the taxon under a parent picked by search", %{conn: conn} do
      genus = genus()
      other = genus("Othergenus#{uniq()}")
      plant = plant_fixture(name: "#{Taxa.accepted_name(genus)} mover", parent: genus)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")
      render_keyup(view, "search_parent", %{"value" => Taxa.accepted_name(other)})
      render_click(view, "select_parent", %{"id" => "#{other.id}"})
      html = view |> element("#move-button") |> render_click()

      assert html =~ "Moved under #{Taxa.accepted_name(other)}"
      assert Taxa.get_taxon!(plant.id).parent_id == other.id
      assert [_] = taxonomy_edits("place")
    end

    test "parent search offers only taxa of a higher rank, without the taxon itself",
         %{conn: conn} do
      name = "Searchgenus#{uniq()}"
      genus = genus(name)
      _plant = plant_fixture(name: "#{name} lowly", parent: genus)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus.id}")
      render_keyup(view, "search_parent", %{"value" => name})

      results = :sys.get_state(view.pid).socket.assigns.parent_results
      refute Enum.any?(results, &(&1.id == genus.id))
      refute Enum.any?(results, &(&1.name == "#{name} lowly"))
    end

    test "a move the tree refuses is reported and changes nothing", %{conn: conn} do
      genus = genus()
      plant = plant_fixture(name: "#{Taxa.accepted_name(genus)} stuck", parent: genus)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus.id}")
      # The genus under its own child: a cycle.
      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.assigns[:selected_parent], %{id: plant.id, name: "x"})
      end)

      html = render_click(view, "move", %{})

      assert html =~ "Not saved"
      refute Taxa.get_taxon!(genus.id).parent_id == plant.id
    end
  end

  describe "synonyms and common names" do
    test "adds and removes a synonym", %{conn: conn} do
      plant = plant_fixture(name: "Synplant#{uniq()} alba")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      html =
        view
        |> form("#synonym-form", synonym: %{name: "Synplant albida", sensu: ""})
        |> render_submit()

      assert html =~ "Synonym Synplant albida added"
      [synonym] = Taxa.list_synonyms(plant)
      assert synonym.name == "Synplant albida"
      assert [_] = for(e <- Import.list_replay_entries(), e.kind == :synonym_added, do: e)

      view |> element("#synonyms button[phx-value-id='#{synonym.id}']") |> render_click()

      assert Taxa.list_synonyms(plant) == []
      assert [_] = taxonomy_edits("remove_synonym")
    end

    test "a misapplied name keeps its sensu", %{conn: conn} do
      plant = plant_fixture(name: "Sensuplant#{uniq()} alba")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      view
      |> form("#synonym-form", synonym: %{name: "Sensuplant rubra", sensu: "auct. non L."})
      |> render_submit()

      assert [%{sensu: "auct. non L."}] = Taxa.list_synonyms(plant)
    end

    test "adds and removes a common name", %{conn: conn} do
      plant = plant_fixture(name: "Commonplant#{uniq()} alba")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      html =
        view |> form("#common-name-form", common_name: %{name: "white thing"}) |> render_submit()

      assert html =~ "Common name white thing added"
      [common] = Taxa.list_common_names(plant)
      assert [_] = taxonomy_edits("add_common_name")

      view |> element("#common-names button[phx-value-id='#{common.id}']") |> render_click()

      assert Taxa.list_common_names(plant) == []
      assert [_] = taxonomy_edits("remove_common_name")
    end

    test "a duplicate common name is refused", %{conn: conn, actor: actor} do
      plant = plant_fixture(name: "Dupcommon#{uniq()} alba")
      {:ok, _} = Taxa.add_common_name(actor, plant, "same name")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      html =
        view |> form("#common-name-form", common_name: %{name: "same name"}) |> render_submit()

      assert html =~ "Not saved"
      assert [_] = Taxa.list_common_names(plant)
    end
  end

  describe "sections" do
    setup do
      name = "Sectgenus#{uniq()}"
      genus = genus(name)
      section = plant_fixture(rank: :section, name: "Lobatae#{uniq()}", parent: genus)
      plant = plant_fixture(name: "#{name} rubra", parent: genus)
      %{genus: genus, section: section, plant: plant, genus_name: name}
    end

    test "a plant is put in a section of its genus, and taken out", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{ctx.plant.id}")

      view |> form("#section-form", %{section_id: ctx.section.id}) |> render_change()
      assert Taxa.get_taxon!(ctx.plant.id).parent_id == ctx.section.id

      view |> form("#section-form", %{section_id: ""}) |> render_change()
      assert Taxa.get_taxon!(ctx.plant.id).parent_id == ctx.genus.id
    end

    test "a section's page adds and removes member plants", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{ctx.section.id}")

      render_keyup(view, "search_member", %{"value" => "#{ctx.genus_name} rubra"})
      html = render_click(view, "select_member", %{"id" => "#{ctx.plant.id}"})

      assert html =~ "Added to the section"
      assert Taxa.get_taxon!(ctx.plant.id).parent_id == ctx.section.id
      assert has_element?(view, "#section-members", "#{ctx.genus_name} rubra")

      view |> element("#section-members button[phx-value-id='#{ctx.plant.id}']") |> render_click()
      assert Taxa.get_taxon!(ctx.plant.id).parent_id == ctx.genus.id
    end

    test "a plant of another genus can't join the section", %{conn: conn} = ctx do
      stranger = plant_fixture(name: "Strangergenus#{uniq()} alba", parent: genus())

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{ctx.section.id}")
      html = render_click(view, "select_member", %{"id" => "#{stranger.id}"})

      assert html =~ "must be in the section&#39;s genus"
      refute Taxa.get_taxon!(stranger.id).parent_id == ctx.section.id
    end
  end

  describe "a plant's details" do
    test "saves datacomplete and abundance, logged for replay", %{conn: conn} do
      plant = plant_fixture(name: "Flagplant#{uniq()} alba")
      [{_name, abundance_id} | _] = Taxa.abundance_options()

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      view
      |> form("#editorial-form",
        editorial: %{datacomplete: "true", abundance_id: "#{abundance_id}"}
      )
      |> render_submit()

      assert %{datacomplete: true, abundance_id: ^abundance_id} = Taxa.get_taxon!(plant.id)
      assert [_] = taxonomy_edits("update_editorial")
    end

    test "a taxon that is no plant has no plant details", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus().id}")

      refute has_element?(view, "#editorial-form")
      refute has_element?(view, "#wcvp-link")
    end
  end

  describe "the WCVP link" do
    test "matches a plant to WCVP by name", %{conn: conn} do
      plant = plant_fixture(name: "Wcvptestus alpinus")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")
      html = render_click(view, "wcvp_match", %{})

      assert html =~ "Linked to WCVP"
      assert Wcvp.get_link(plant.id).wcvp_id == "700"
      assert has_element?(view, "#wcvp-link", "700")
      assert [_ | _] = taxonomy_edits("set_wcvp")
    end

    test "a plant WCVP doesn't know is marked no match", %{conn: conn} do
      plant = plant_fixture(name: "Nowcvp#{uniq()} alba")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")
      html = render_click(view, "wcvp_match", %{})

      assert html =~ "No WCVP match found"
      assert Wcvp.get_link(plant.id).wcvp_match_status == "no_match"
    end

    test "syncs the range from WCVP and shows it", %{conn: conn} do
      plant = plant_fixture(name: "Wcvptestus alpinus")
      host_range_fixture(plant, [{"MX-JAL", "exact"}])

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")
      html = render_click(view, "wcvp_sync", %{})

      assert html =~ "Range synced from WCVP"
      assert %DateTime{} = Wcvp.get_link(plant.id).wcvp_synced_at
      assert [_] = taxonomy_edits("set_host_range")

      range_entries = :sys.get_state(view.pid).socket.assigns.range_entries
      refute Map.has_key?(range_entries, "MX-JAL")
    end

    test "ignores a plant for WCVP and clears it again", %{conn: conn} do
      plant = plant_fixture(name: "Ignoreplant#{uniq()} alba")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")
      render_click(view, "wcvp_ignore", %{})
      assert Wcvp.get_link(plant.id).wcvp_match_status == "ignored"

      render_click(view, "wcvp_clear_status", %{})
      assert is_nil(Wcvp.get_link(plant.id).wcvp_match_status)
    end
  end

  describe "images" do
    test "the taxon's images are managed on its page", %{conn: conn} do
      plant = plant_fixture(name: "Imageplant#{uniq()} alba")

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")

      assert has_element?(view, "#images #taxon-images")
    end
  end

  describe "deleting" do
    test "a taxon nothing refers to is deleted after typing its name", %{conn: conn} do
      name = "Lonely#{uniq()} alba"
      plant = plant_fixture(name: name)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{plant.id}")
      view |> element("#delete-button") |> render_click()
      assert has_element?(view, "#dangerous-delete-modal", name)

      html = render_submit(view, "confirm_delete", %{"confirmation" => "wrong"})
      assert html =~ "Name does not match"
      assert %Taxon{} = Taxa.get_taxon(plant.id)

      render_submit(view, "confirm_delete", %{"confirmation" => name})

      assert_redirect(view, "/admin/taxonomy")
      assert is_nil(Taxa.get_taxon(plant.id))
      assert [_] = taxonomy_edits("delete_taxon")

      deletes =
        from(c in test_audit_changes(), where: c.table_name == "taxa" and c.op == :delete)

      assert Repo.aggregate(deletes, :count) == 1
    end

    test "a referenced taxon shows what refers to it and has no delete", %{conn: conn} do
      genus = genus()
      _child = plant_fixture(name: "#{Taxa.accepted_name(genus)} kid", parent: genus)

      {:ok, view, _html} = live(conn, ~p"/admin/taxonomy/#{genus.id}")

      refute has_element?(view, "#delete-button")
      assert has_element?(view, "#taxon-references", "1 child taxon")
    end
  end
end
