defmodule GallformersWeb.Admin.TaxonomyLive.BasedOnSourceTest do
  @moduledoc """
  The taxonomy admin's changes to non-plant taxa ask "Based on which
  Source?" (matter `f923` Task 8): a move, a name, a synonym or common name
  and a new taxon open the dialog; the change is made as the chosen
  Source's accepted statement (a Source in Gallformers, a new citation, or
  Gallformers' own position with a reason). An edit an accepted newer paper
  outranks is explained in the dialog and changes nothing. Plants keep their
  direct edits (`EditTest`).
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, confirm: 1]
  import Gallformers.DataCase, only: [test_actor: 0]
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Sol Source")
    n = System.unique_integer([:positive])
    family = taxon_fixture(rank: :family, name: "Credidae#{n}", kingdom: "Animalia")
    other = taxon_fixture(rank: :family, name: "Othercredidae#{n}", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Creda#{n}", parent: family)
    species = taxon_fixture(name: "Creda#{n} alba", parent: genus)
    for taxon <- [family, other, genus, species], do: legacy!(taxon)

    %{
      conn: conn,
      user: user,
      actor: Actor.user(user.id, "Sol Source"),
      n: n,
      weld: source_fixture("Weld", "1959"),
      family: family,
      other: other,
      genus: genus,
      species: species
    }
  end

  # The tree's own statements of `taxon`, as the cutover makes them.
  defp legacy!(taxon) do
    taxon = Taxa.get_taxon!(taxon.id)
    attribution = %{source_id: Sources.get_legacy_data_source().id, stance: :confirm, stated: nil}
    key = %{taxon_id: taxon.id, parent_id: taxon.parent_id}
    {:ok, _} = Taxa.assert_placement(test_actor(), key, attribution)
    name = %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank}
    {:ok, _} = Taxa.assert_name(test_actor(), name, attribution)
  end

  defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

  defp pick_source(view, source) do
    view |> with_target("#basis-picker") |> render_hook("search_source", %{"value" => "Weld"})
    view |> element("#basis-picker-source [phx-value-id='#{source.id}']") |> render_click()
  end

  # The dialog sends the page its choice; render once the page has made it.
  defp submit_basis(view, params \\ %{}) do
    view |> form("#basis-picker-form", basis: params) |> render_submit()
    render(view)
  end

  defp move_genus(view, ctx) do
    render_keyup(view, "search_parent", %{"value" => Taxa.accepted_name(ctx.other)})
    render_click(view, "select_parent", %{"id" => "#{ctx.other.id}"})
    view |> element("#move-button") |> render_click()
  end

  describe "a taxon's page" do
    test "a move asks for the Source and is made as its accepted statement", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.genus.id}")

      move_genus(view, ctx)
      assert has_element?(view, "#basis-picker", "Based on which Source?")
      assert has_element?(view, "#basis-picker-change", "Othercredidae#{ctx.n}")

      assert has_element?(
               view,
               "#basis-picker-choices [data-recommended] #basis-picker-choice-source"
             )

      # Nothing changes until the Source is given.
      assert parent_id(ctx.genus) == ctx.family.id

      pick_source(view, ctx.weld)
      html = submit_basis(view)

      assert html =~ "Moved under Othercredidae#{ctx.n}"
      refute has_element?(view, "#basis-picker")
      assert parent_id(ctx.genus) == ctx.other.id

      {:ok, fact_id} =
        Taxa.find_act_fact(:placement, %{taxon_id: ctx.genus.id, parent_id: ctx.other.id})

      statement = Facts.get_attribution(fact_id, ctx.weld.id)
      assert statement.accepted_by_user_id == ctx.user.id
    end

    test "the next change starts with the Source last used", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.species.id}")

      view |> form("#synonym-form", synonym: %{name: "Creda nigra"}) |> render_submit()
      pick_source(view, ctx.weld)
      submit_basis(view)

      view |> form("#common-name-form", common_name: %{name: "white creda"}) |> render_submit()
      assert has_element?(view, "#basis-picker-source-selected", ctx.weld.title)
      submit_basis(view)

      assert ["Creda nigra"] = Enum.map(Taxa.list_synonyms(ctx.species), & &1.name)
      assert ["white creda"] = Enum.map(Taxa.list_common_names(ctx.species), & &1.name)
    end

    test "a name gives the accepted name, rank and authorship", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.species.id}")
      new_name = "Creda#{ctx.n} albida"

      view
      |> form("#rename-form", rename: %{name: new_name, authorship: "(Weld, 1959)"})
      |> render_submit()

      pick_source(view, ctx.weld)
      html = submit_basis(view)

      assert html =~ "Renamed to #{new_name}"
      assert Taxa.accepted_name(ctx.species.id) == new_name
      assert has_element?(view, "#synonyms", "Creda#{ctx.n} alba")
    end

    test "removing a synonym asks for the Source that drops it", ctx do
      {:ok, _} = Taxa.add_synonym(ctx.actor, ctx.species, "Creda nigra")
      [synonym] = Taxa.list_synonyms(ctx.species)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.species.id}")
      view |> element("#synonyms button[phx-value-id='#{synonym.id}']") |> render_click()
      assert has_element?(view, "#basis-picker-change", "Creda nigra")

      pick_source(view, ctx.weld)
      submit_basis(view)

      assert Taxa.list_synonyms(ctx.species) == []
    end

    test "a new citation is made a Source with the change", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.genus.id}")
      move_genus(view, ctx)

      view |> element("#basis-picker-choice-citation") |> render_click()
      assert has_element?(view, "#basis-picker-cite-title")

      title = "A revision of Creda #{ctx.n}"

      submit_basis(view, %{
        choice: "citation",
        title: title,
        authors: "Smith, J.; Jones, K.",
        authored: "2008"
      })

      assert %{authors: ["Smith, J.", "Jones, K."]} = Sources.get_source_by_title(title)
      assert parent_id(ctx.genus) == ctx.other.id
    end

    test "a citation missing its date is refused in the dialog", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.genus.id}")
      move_genus(view, ctx)
      view |> element("#basis-picker-choice-citation") |> render_click()

      submit_basis(view, %{choice: "citation", title: "Undated #{ctx.n}", authors: "Smith, J."})

      assert has_element?(view, "#basis-picker-error", "Authored")
      assert parent_id(ctx.genus) == ctx.family.id
    end

    test "Gallformers' own position needs a reason", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.genus.id}")
      move_genus(view, ctx)
      view |> element("#basis-picker-choice-gallformers") |> render_click()
      assert has_element?(view, "#basis-picker-reason")

      submit_basis(view, %{choice: "gallformers", reason: ""})
      assert has_element?(view, "#basis-picker-error", "reason")
      assert parent_id(ctx.genus) == ctx.family.id

      html = submit_basis(view, %{choice: "gallformers", reason: "No paper places it yet."})
      assert html =~ "Moved under"
      assert parent_id(ctx.genus) == ctx.other.id
    end

    test "an edit an accepted newer paper outranks is explained and changes nothing", ctx do
      newer = source_fixture("Revision", "2019")

      {:ok, %{attribution: accepted}} =
        Taxa.assert_placement(
          ctx.actor,
          %{taxon_id: ctx.genus.id, parent_id: ctx.other.id},
          confirm(newer)
        )

      {:ok, _} = Facts.accept(ctx.actor, accepted.id)
      older = source_fixture("Weld", "2008")

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.genus.id}")
      render_keyup(view, "search_parent", %{"value" => Taxa.accepted_name(ctx.family)})
      render_click(view, "select_parent", %{"id" => "#{ctx.family.id}"})
      view |> element("#move-button") |> render_click()

      pick_source(view, older)
      submit_basis(view)

      assert has_element?(view, "#basis-picker-error", "2019")
      assert has_element?(view, "#basis-picker-error", "won't change the tree")
      assert parent_id(ctx.genus) == ctx.other.id
    end

    test "cancelling changes nothing", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.genus.id}")
      move_genus(view, ctx)

      render_click(view, "cancel_basis", %{})

      refute has_element?(view, "#basis-picker")
      assert parent_id(ctx.genus) == ctx.family.id
      assert Import.list_replay_entries() == []
    end

    test "a non-plant's synonym form has no sensu (a synonymy has none)", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/#{ctx.species.id}")
      refute has_element?(view, "#synonym-form input[name='synonym[sensu]']")
    end
  end

  describe "a new taxon" do
    test "is created as the Source's placement and name", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy/new")

      render_keyup(view, "search_parent", %{"value" => Taxa.accepted_name(ctx.genus)})
      render_click(view, "select_parent", %{"id" => "#{ctx.genus.id}"})
      name = "Creda#{ctx.n} nova"

      view
      |> form("#taxon-form", taxon: %{name: name, rank: "species"})
      |> render_submit()

      assert has_element?(view, "#basis-picker", "Based on which Source?")
      pick_source(view, ctx.weld)
      view |> form("#basis-picker-form") |> render_submit()

      # The page makes the change (and redirects) after the submit returns.
      {path, _flash} = assert_redirect(view, 5_000)
      assert {:ok, nova} = Taxa.resolve_name(name, rank: :species)
      assert path == ~p"/admin/taxonomy/#{nova.id}"
      assert nova.parent_id == ctx.genus.id
    end
  end

  describe "moving several from the list" do
    test "asks for the Source in the move dialog", ctx do
      sister = taxon_fixture(rank: :genus, name: "Credella#{ctx.n}", parent: ctx.family)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/taxonomy?#{%{parent: ctx.family.id}}")
      render_click(view, "toggle_select", %{"id" => "#{ctx.genus.id}"})
      render_click(view, "toggle_select", %{"id" => "#{sister.id}"})
      render_click(view, "open_move_modal", %{})
      render_keyup(view, "search_move_target", %{"value" => Taxa.accepted_name(ctx.other)})
      render_click(view, "select_move_target", %{"id" => "#{ctx.other.id}"})
      view |> element("#move-selected") |> render_click()

      assert has_element?(view, "#basis-picker", "Based on which Source?")
      pick_source(view, ctx.weld)
      html = submit_basis(view)

      assert html =~ "Moved 2 taxa under Othercredidae#{ctx.n}"
      assert parent_id(ctx.genus) == ctx.other.id
      assert parent_id(sister) == ctx.other.id
    end
  end
end
