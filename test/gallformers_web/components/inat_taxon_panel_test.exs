defmodule GallformersWeb.InatTaxonPanelTest do
  @moduledoc """
  The `inat_taxon_panel` (matter `cb28` Task 5): its steps as the approved
  mockup words them, against iNaturalist's recorded taxa beside a tree made
  for each case; and the LiveComponent holding its state
  (`GallformersWeb.Admin.InatTaxonPanel`), hosted by a minimal LiveView:
  finding, looking, ticking, the button's words, and `{:imported, id}`.
  """
  use GallformersWeb.ConnCase, async: false

  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]
  import Gallformers.INaturalistFixtures
  import Phoenix.LiveViewTest

  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias GallformersWeb.Admin.InatTaxonPanel
  alias GallformersWeb.ReviewComponents

  defp text(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.text() |> words()

  # The words a page shows, without its markup.
  defp squish(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> words()

  defp words(text), do: text |> String.split() |> Enum.join(" ")

  defp has?(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.any?()

  defp rubus_tree do
    rosaceae = plant_fixture(rank: :family, name: "Rosaceae")
    rubus = plant_fixture(rank: :genus, name: "Rubus", parent: rosaceae)
    plant_fixture(name: "Rubus frondosus", parent: rubus)
    %{rosaceae: rosaceae, rubus: rubus}
  end

  defp look(plan, opts \\ []) do
    render_component(
      &ReviewComponents.inat_taxon_panel/1,
      Keyword.merge(
        [
          id: "inat",
          step: :look,
          plan: plan,
          ticked: plan.ticked,
          authorship: plan.authorship,
          credit: "iNaturalist, accessed 8 Nov 2026"
        ],
        opts
      )
    )
  end

  describe "inat_taxon_panel: look and choose" do
    setup do
      rubus_tree()
      %{plan: Import.plan_inat_taxon(inat_taxon(1_449_402), "Rubus pensilvanicus")}
    end

    test "the taxon, where it goes, what is under it, its names", %{plan: plan} do
      html = look(plan, answering: true, back: true)
      flat = squish(html)

      assert flat =~ "From iNaturalist"
      assert flat =~ "← Other results"
      assert flat =~ "Arguti section"
      assert flat =~ "Field Highbush Blackberries · 22,268 observations · iNaturalist ↗"

      # The ranks above Rosaceae folded; the needed one ticked.
      assert text(html, "[data-role=inat-above]") =~
               "Plantae › … › Rosales 5 ranks above it we don't hold Show them"

      assert flat =~ "Add: needed to attach it"
      assert flat =~ "We have it"
      assert flat =~ "Under it on iNaturalist 26"
      assert flat =~ "we have it under Rubus"
      assert flat =~ "Move here"
      assert flat =~ "Show 18 more"
      assert flat =~ "Rubus pensilvanicus synonym · the name that matched"
      assert flat =~ "Field Highbush Blackberries common name · iNaturalist's"

      assert flat =~
               "Marked as from iNaturalist, with its iNaturalist ID. Plants are edited directly, so no statements are recorded."

      assert text(html, "[data-role=inat-add]") == "Add 2 taxa and 2 names"
      assert flat =~ "Then the question is answered with Arguti."

      # Authorship: a field for each taxon added, the subgenus and the section.
      assert html =~ ~s(name="authorship[t]")
      assert html =~ "iNaturalist has no authors: add them if you know them"
    end

    test "unfolded, every rank shows; every child shows", %{plan: plan} do
      flat = plan |> look(higher: true, more: true) |> squish()
      refute flat =~ "Show them"
      refute flat =~ "Show 18 more"
      assert flat =~ "Tracheophyta phylum"
      assert flat =~ "Rubus densissimus"
    end

    test "the button says what it does", %{plan: plan} do
      frondosus = Enum.find(plan.children, &(&1.name == "Rubus frondosus")).key
      html = look(plan, ticked: MapSet.put(plan.ticked, frondosus))
      assert text(html, "[data-role=inat-add]") == "Add 2 taxa, move 1 and 2 names"

      assert ReviewComponents.inat_add_label(0, 0, 0) == "Use it"
      assert ReviewComponents.inat_add_label(1, 0, 0) == "Add 1 taxon"
      assert ReviewComponents.inat_add_label(0, 1, 2) == "Move 1 and add 2 names"
      assert ReviewComponents.inat_add_label(0, 0, 1) == "Add 1 name"
    end
  end

  describe "inat_taxon_panel: other cases" do
    test "an animal: credited to the day's iNaturalist Source; nothing held above it" do
      plan = Import.plan_inat_taxon(inat_taxon(49_995), "Syrphidae")
      flat = plan |> look() |> squish()

      assert flat =~
               "Each is iNaturalist's statement (iNaturalist, accessed 8 Nov 2026), accepted by you."

      assert flat =~
               "We hold nothing above it: it goes in at the top of the tree, as our families do."

      assert flat =~ "Animalia › … › Aschiza 9 ranks above it we don't hold"
      assert flat =~ "Hover Flies common name · iNaturalist's"
      refute flat =~ "Then the question is answered with"
    end

    test "a rank we don't use: the curator picks one; Add waits for it" do
      rubus_tree()
      plan = Import.plan_inat_taxon(inat_taxon(1_449_411), nil)
      html = look(plan)

      assert squish(html) =~ "iNaturalist ranks it a complex, which we don't use. Add it as:"
      assert html =~ ~s(<option value="">Choose a rank</option>)
      assert html =~ "Choose the rank to add it as."
      assert has?(html, "[data-role=inat-add][disabled]")

      html = look(plan, rank: :species)
      refute html =~ "Choose the rank to add it as."
    end

    test "a taxon we hold: it says so" do
      %{rubus: rubus} = rubus_tree()
      plant_fixture(rank: :section, name: "Arguti", parent: rubus)
      plan = Import.plan_inat_taxon(inat_taxon(1_449_402), nil)

      assert text(look(plan), "[data-role=inat-held]") ==
               "We have it: the import links it and adds what you tick."
    end

    test "an inactive taxon offers the one that replaced it" do
      plan = Import.plan_inat_taxon(inat_taxon(78_894), "Rubus pensilvanicus")
      html = look(plan)

      assert text(html, "[data-role=inat-inactive]") =~
               "iNaturalist no longer uses this taxon: another has replaced it. Look at the one that replaced it"

      assert html =~ ~s(phx-value-id="1449402")
      refute html =~ ~s(data-role="inat-add")
    end
  end

  describe "inat_taxon_panel: find" do
    test "results, with the name that matched" do
      stub_inat_taxa()
      {:ok, results} = Import.search_inat_taxa("Rubus pensilvanicus")

      flat =
        render_component(&ReviewComponents.inat_taxon_panel/1,
          id: "inat",
          step: :find,
          query: "Rubus pensilvanicus",
          results: results
        )
        |> squish()

      assert flat =~ "A name, or an iNaturalist link or number."
      assert flat =~ "Arguti section"
      assert flat =~ "Field Highbush Blackberries · 22,268 observations"
      assert flat =~ "Matched “Rubus pensilvanicus”, a name iNaturalist files under it"
      assert flat =~ "Look at it"
    end

    test "nothing found: the names WCVP gives for it" do
      flat =
        render_component(&ReviewComponents.inat_taxon_panel/1,
          id: "inat",
          step: :find,
          query: "Rubus villosus var. frondosus",
          results: [],
          suggest: ["Rubus pensilvanicus"],
          answering: true
        )
        |> squish()

      assert flat =~
               "iNaturalist has nothing by “Rubus villosus var. frondosus”. Try another name the Source might mean."

      assert flat =~ "Names WCVP gives for it: Rubus pensilvanicus"
    end
  end

  # -- the LiveComponent ----------------------------------------------------------------

  defmodule HostLive do
    use Phoenix.LiveView

    def mount(_params, %{"start" => start}, socket) do
      {:ok,
       Phoenix.Component.assign(socket,
         start: start,
         said: [],
         actor: Gallformers.DataCase.test_actor()
       )}
    end

    def handle_info({InatTaxonPanel, message}, socket),
      do: {:noreply, Phoenix.Component.update(socket, :said, &(&1 ++ [message]))}

    def render(assigns) do
      ~H"""
      <p id="said">{inspect(@said)}</p>
      <.live_component
        module={InatTaxonPanel}
        id="inat"
        actor={@actor}
        start={@start}
        back
        answering
      />
      """
    end
  end

  defp host(conn, start) do
    {:ok, view, _html} = live_isolated(conn, HostLive, session: %{"start" => start})
    view
  end

  describe "the LiveComponent" do
    setup do
      stub_inat_taxa()
      :ok
    end

    test "opens on a taxon, ticks change what Add does, Add brings it in", %{conn: conn} do
      %{rubus: rubus} = rubus_tree()
      view = host(conn, {:taxon, 1_449_402, "Rubus pensilvanicus"})

      assert render(view) =~ "Reading it from iNaturalist…"
      html = render_async(view)
      assert text(html, "[data-role=inat-add]") == "Add 2 taxa and 2 names"

      # Unticking the synonym.
      view |> element("input[phx-value-key='s:Rubus pensilvanicus']") |> render_click()
      assert text(render(view), "[data-role=inat-add]") == "Add 2 taxa and 1 name"

      view |> element("button", "Show 18 more") |> render_click()
      assert render(view) =~ "Rubus densissimus"

      view |> element("button", "Show them") |> render_click()
      assert render(view) =~ "Tracheophyta"

      view
      |> element("form[data-role=inat-authorship]")
      |> render_change(%{"authorship" => %{"t" => "Focke"}})

      view |> element("[data-role=inat-add]") |> render_click()

      {:ok, arguti} = Taxa.resolve_name("Arguti", rank: :section, kingdom: "Plantae")
      # The caller is told: `[{:imported, id}]`, as `inspect/1` writes it.
      assert render(view) =~ "[imported: #{arguti.id}]"
      assert Taxa.inat_id(arguti) == 1_449_402
      assert Taxa.get_taxon!(Taxa.get_taxon!(arguti.id).parent_id).parent_id == rubus.id

      assert Enum.find(Taxa.get_taxon!(arguti.id).names, &(&1.status == :accepted)).authorship ==
               "Focke"
    end

    test "opened from its caller's search: “Other results” and Close go back", %{conn: conn} do
      view = host(conn, {:taxon, 49_995, "Syrphidae"})
      render_async(view)

      view |> element("button", "← Other results") |> render_click()
      assert render(view) =~ ":close"
    end

    test "a search, a result looked at, and back to the results", %{conn: conn} do
      view = host(conn, {:query, "Rubus pensilvanicus"})
      html = render_async(view)
      assert squish(html) =~ "Matched “Rubus pensilvanicus”, a name iNaturalist files under it"

      view |> element("li[data-inat='1449402'] button", "Look at it") |> render_click()
      html = render_async(view)
      assert html =~ "Where it goes"

      view |> element("button", "← Other results") |> render_click()
      html = render(view)
      assert html =~ "Matched “Rubus pensilvanicus”"
      refute html =~ ":close"
    end

    test "nothing on iNaturalist: the names WCVP gives for it, one click each", %{conn: conn} do
      view = host(conn, {:query, "Wcvpunplacedus vagus var. alter"})
      html = render_async(view)

      assert squish(html) =~ "iNaturalist has nothing by “Wcvpunplacedus vagus var. alter”."
      assert squish(html) =~ "Names WCVP gives for it: Wcvpunplacedus vagus"
    end

    @tag :capture_log
    test "iNaturalist down says so", %{conn: conn} do
      stub_inat_down()
      view = host(conn, {:query, "Syrphidae"})
      assert render_async(view) =~ "iNaturalist couldn&#39;t be reached."
    end

    test "a refusal shows in the panel", %{conn: conn} do
      rubus_tree()
      view = host(conn, {:taxon, 1_449_411, nil})
      render_async(view)

      # A genus can't go under the section it needs.
      view |> element("form[data-role=inat-rank]") |> render_change(%{"rank" => "genus"})
      view |> element("[data-role=inat-add]") |> render_click()

      assert render(view) =~ "Nothing was added"
      assert Taxa.resolve_name("Alleghenienses") == :none
      assert Sources.inaturalist_source(Date.utc_today()) == nil
    end
  end
end
