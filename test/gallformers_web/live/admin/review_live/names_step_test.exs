defmodule GallformersWeb.Admin.ReviewLive.NamesStepTest do
  @moduledoc """
  The Names step (matter `d213`, Task 18): three sections (Host plants;
  Which taxon is it; Where the Source and the tree differ), every taxon
  answer with its identity line and whether it holds the Source's name, a
  Host's WCVP panel read when its row opens, at most three candidates, the
  tree changed from a synonym question, and "Accept firm matches".

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo
  alias Gallformers.Taxa

  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  # A gall batch by Ashmead 1897: "Q. lobata" names no plant here, so it is
  # a Host question; Torymus is a name Gallformers doesn't hold.
  defp gall_package!(host \\ "Q. lobata", opts \\ []) do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> put_in(["taxa", Access.at(1), "name_as_written"], host)
      |> then(fn gall ->
        if opts[:common_name],
          do:
            put_in(gall, ["taxa", Access.at(1)], %{
              "ref" => "t2",
              "name_as_written" => host,
              "common_name" => true
            }),
          else: gall
      end)

    package = package(gall: gall) |> with_review() |> deliver!()
    [batch] = Import.list_batches(package)
    %{package: package, batch: batch}
  end

  # A taxonomy batch by Ashmead 1897 naming `name` as a valid species, which
  # the tree holds as a synonym of Fixtrhytis clarkei.
  defp synonym_package!(name) do
    andricus = taxon_fixture(name: "Fixtandricus", rank: :genus, kingdom: "Animalia")
    callirhytis = taxon_fixture(name: "Fixtrhytis", rank: :genus, kingdom: "Animalia")
    held = taxon_fixture(name: "Fixtrhytis clarkei", parent: callirhytis)
    other = taxon_fixture(name: "Fixtandricus dimorphus", parent: andricus)
    {:ok, _} = Taxa.add_synonym(test_actor(), held, "Fixtandricus wisliceni")
    {:ok, _} = Taxa.add_synonym(test_actor(), held, "Zzfixtus wisliceni")

    taxonomy =
      taxonomy_batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> put_in(["taxa", Access.at(0), "name_as_written"], name)

    package = package(gall: nil, taxonomy: taxonomy) |> with_review() |> deliver!()
    [item] = Import.list_queue_items(package, kind: :taxonomy_disagreement)
    %{package: package, item: item, held: held, other: other, andricus: andricus}
  end

  defp step(conn, package), do: live(conn, ~p"/admin/review/packages/#{package.id}/names")

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  defp choose(view, item, label) do
    id =
      view
      |> element("#item-#{item.id}-choices label", label)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("input")
      |> LazyHTML.attribute("id")
      |> List.first()

    view |> element("##{id}") |> render_click()
  end

  # The query of the "Create a new plant" link in `selector`, which opens
  # the New Taxon page in a new tab.
  defp new_plant_query(view, selector) do
    link = "#{selector} a[target=_blank][rel=noopener]"
    assert has_element?(view, link, "Create a new plant ↗")

    uri =
      view
      |> element(link, "Create a new plant")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("href")
      |> List.first()
      |> URI.parse()

    assert uri.path == "/admin/taxonomy/new"
    URI.decode_query(uri.query)
  end

  defp item(package, name) do
    Enum.find(Import.list_queue_items(package), &(&1.subject["name_as_written"] == name))
  end

  describe "the sections" do
    test "Host plants and Which taxon is it, from a gall batch", %{conn: conn} do
      %{package: package} = gall_package!()
      host = item(package, "Q. lobata")
      torymus = item(package, "Torymus")
      {:ok, view, _html} = step(conn, package)

      assert has_element?(view, "#section-hosts h2", "Host plants")
      assert has_element?(view, "#section-hosts #item-#{host.id}")
      assert has_element?(view, "#section-which_taxon h2", "Which taxon is it")
      assert has_element?(view, "#section-which_taxon #item-#{torymus.id}")
      refute has_element?(view, "#section-not_held")
    end

    test "Where Ashmead 1897 and the tree differ, from a synonym", %{conn: conn} do
      %{package: package, item: item} = synonym_package!("Fixtandricus wisliceni")
      {:ok, view, _html} = step(conn, package)

      assert has_element?(view, "#section-differ h2", "Where Ashmead 1897 and the tree differ")
      assert has_element?(view, "#section-differ #item-#{item.id}")
    end
  end

  describe "a synonym question" do
    test "says what the tree holds, with the answer's identity and alias lines",
         %{conn: conn} do
      %{package: package, item: item, held: held} = synonym_package!("Fixtandricus wisliceni")
      {:ok, view, _html} = step(conn, package)
      open_row(view, item)

      assert has_element?(
               view,
               "#item-#{item.id}-detail [data-role=question]",
               "Ashmead 1897 treats “Fixtandricus wisliceni” as a valid species. Gallformers " <>
                 "holds it as a synonym of Fixtrhytis clarkei."
             )

      assert has_element?(
               view,
               "#item-#{item.id}-detail [data-role=scope]",
               "No Source is recorded for Gallformers' synonymy"
             )

      choices = "#item-#{item.id}-choices"
      assert has_element?(view, choices, "Follow Gallformers: it's Fixtrhytis clarkei")

      assert has_element?(
               view,
               "#{choices} [data-role=alias][data-kind=yes]",
               "✓ Already holds “Fixtandricus wisliceni” as a synonym"
             )

      assert has_element?(view, "#{choices} [data-role=identity]", "No Galls in Gallformers")

      assert has_element?(
               view,
               "#{choices} [data-role=identity] a[href='/admin/taxonomy/#{held.id}'][target=_blank]",
               "Open ↗"
             )

      assert has_element?(view, "#{choices} [data-role=also-holds]", "Zzfixtus wisliceni")
    end

    test "Ashmead is right: a species of its own again", %{conn: conn} do
      %{package: package, item: item, andricus: andricus} =
        synonym_package!("Fixtandricus wisliceni")

      {:ok, view, _html} = step(conn, package)
      open_row(view, item)
      choose(view, item, "Ashmead 1897 is right: change the tree")

      assert has_element?(view, "#item-#{item.id}-decide[disabled]")
      assert has_element?(view, "#item-#{item.id}-effect", "Choose what the name becomes.")

      view |> element("#item-#{item.id}-picker-tree-own") |> render_click()

      assert has_element?(
               view,
               "#item-#{item.id}-effect",
               "Fixtandricus wisliceni becomes a species of its own again, no longer a synonym " <>
                 "of Fixtrhytis clarkei, in every Source."
             )

      view |> element("#item-#{item.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."

      assert %QueueItem{status: :decided, decision: %{"split" => true, "taxon_id" => id}} =
               Import.get_queue_item!(item.id)

      assert Taxa.get_taxon!(id).parent_id == andricus.id
    end

    test "Ashmead is right: a synonym of another species, picked", %{conn: conn} do
      %{package: package, item: item, other: other} = synonym_package!("Fixtandricus wisliceni")
      {:ok, view, _html} = step(conn, package)
      open_row(view, item)
      choose(view, item, "Ashmead 1897 is right: change the tree")
      view |> element("#item-#{item.id}-picker-tree-move") |> render_click()

      assert has_element?(view, "#item-#{item.id}-effect", "Pick the species it belongs to.")

      view
      |> with_target("#item-row-#{item.id}")
      |> render_hook("search_taxon", %{"value" => "Fixtandricus dim"})

      view
      |> element("#item-#{item.id}-picker-results button", "Fixtandricus dimorphus")
      |> render_click()

      assert has_element?(
               view,
               "#item-#{item.id}-effect",
               "becomes a synonym of Fixtandricus dimorphus instead of Fixtrhytis clarkei"
             )

      view |> element("#item-#{item.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."

      assert %QueueItem{status: :decided, decision: %{"synonym_of" => id}} =
               Import.get_queue_item!(item.id)

      assert id == other.id
    end

    test "a refused change says why in the row", %{conn: conn} do
      %{package: package, item: item} = synonym_package!("Zzfixtus wisliceni")
      {:ok, view, _html} = step(conn, package)
      open_row(view, item)
      choose(view, item, "Ashmead 1897 is right: change the tree")
      view |> element("#item-#{item.id}-picker-tree-own") |> render_click()
      view |> element("#item-#{item.id}-decide") |> render_click()

      assert has_element?(view, "#item-#{item.id}-error", "The decision was refused")
      assert has_element?(view, "#item-#{item.id}-error", "Zzfixtus")
      assert Import.get_queue_item!(item.id).status == :open
    end
  end

  # A gall batch by Ashmead 1897 whose Inducer, `name`, the tree doesn't hold.
  defp new_name_package!(name) do
    load_vocab!()

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "Galls of the oaks")
      |> put_in(["source", "authors"], ["Ashmead, W. H."])
      |> put_in(["source", "authored"], %{"date" => "1897", "as_written" => "1897"})
      |> put_in(["taxa", Access.at(0), "name_as_written"], name)

    package(gall: gall) |> with_review() |> deliver!()
  end

  describe "creating a new taxon" do
    test "a new species goes under the genus the tree holds, picked to start with",
         %{conn: conn} do
      genus = taxon_fixture(name: "Fixtnovandricus", rank: :genus, kingdom: "Animalia")
      package = new_name_package!("Fixtnovandricus novus")
      item = item(package, "Fixtnovandricus novus")
      {:ok, view, _html} = step(conn, package)
      open_row(view, item)
      choose(view, item, "It's new: create Fixtnovandricus novus")

      assert has_element?(view, "#item-#{item.id}-picker-selected", "Fixtnovandricus")

      assert has_element?(
               view,
               "#item-#{item.id}-effect",
               "Adds a new species to the tree. It goes under Fixtnovandricus."
             )

      refute has_element?(view, "#item-#{item.id}-effect", "taxonomy admin")

      view |> element("#item-#{item.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."

      assert Import.get_queue_item!(item.id).decision == %{
               "new" => true,
               "parent_id" => genus.id
             }

      assert has_element?(
               view,
               "#item-#{item.id}-row [data-role=answer]",
               "Created under Fixtnovandricus"
             )
    end

    test "a new genus's place is searched among the ranks above it; none picked, unplaced",
         %{conn: conn} do
      family = taxon_fixture(name: "Fixtorymidae", rank: :family, kingdom: "Animalia")
      _genus = taxon_fixture(name: "Fixtorymella", rank: :genus, kingdom: "Animalia")
      %{package: package} = gall_package!()
      torymus = item(package, "Torymus")
      {:ok, view, _html} = step(conn, package)
      open_row(view, torymus)
      choose(view, torymus, "It's new: create Torymus")

      refute has_element?(view, "#item-#{torymus.id}-picker-selected")
      refute has_element?(view, "#item-#{torymus.id}-decide[disabled]")

      assert has_element?(
               view,
               "#item-#{torymus.id}-effect",
               "so it is added unplaced: place it in the tree from the taxonomy admin after."
             )

      view
      |> with_target("#item-row-#{torymus.id}")
      |> render_hook("search_parent", %{"value" => "Fixtorym"})

      results = "#item-#{torymus.id}-picker-results"
      assert has_element?(view, "#{results} button", "Fixtorymidae")
      refute has_element?(view, "#{results} button", "Fixtorymella")

      view |> element("#{results} button", "Fixtorymidae") |> render_click()
      assert has_element?(view, "#item-#{torymus.id}-effect", "It goes under Fixtorymidae.")

      view |> element("#item-#{torymus.id}-decide") |> render_click()
      assert render(view) =~ "Decision recorded."

      assert Import.get_queue_item!(torymus.id).decision == %{
               "new" => true,
               "parent_id" => family.id
             }
    end
  end

  describe "Which taxon is it" do
    test "leaving a name out says what it drops", %{conn: conn} do
      %{package: package} = gall_package!()
      torymus = item(package, "Torymus")
      {:ok, view, _html} = step(conn, package)
      open_row(view, torymus)

      assert has_element?(
               view,
               "#item-#{torymus.id}-choices",
               "Drops 1 statement: the parasitoid of the large stem galls."
             )
    end

    test "at most three candidates; the search lists the others first", %{conn: conn} do
      %{package: package, batch: batch} = gall_package!()

      [a, b, c, d] =
        for n <- ~w(alpha beta gamma delta),
            do: taxon_fixture(name: "Candidus #{n}", kingdom: "Animalia")

      item =
        %QueueItem{}
        |> QueueItem.create_changeset(%{
          package_id: package.id,
          batch_id: batch.id,
          kind: :ambiguous_match,
          statement_ref: "t3",
          subject: %{"name_as_written" => "Torymus", "rank" => "genus"},
          proposal: %{"candidate_ids" => [a.id, b.id, c.id, d.id]}
        })
        |> Repo.insert!()

      {:ok, view, _html} = step(conn, package)
      open_row(view, item)

      for n <- ~w(alpha beta gamma),
          do: assert(has_element?(view, "#item-#{item.id}-choices", "Candidus #{n}"))

      refute has_element?(view, "#item-#{item.id}-choices label", "It's Candidus delta")

      assert has_element?(
               view,
               "#item-#{item.id}-more",
               "1 more possible match: choose “Another taxon” to see them all"
             )

      choose(view, item, "Another taxon…")

      assert has_element?(view, "#item-#{item.id}-picker-results button", "Candidus delta")
    end

    test "Accept firm matches lists each and accepts only the firm ones", %{conn: conn} do
      %{package: package, batch: batch} = gall_package!()
      wasp = taxon_fixture(name: "Candidus firmus", kingdom: "Animalia")

      firm =
        %QueueItem{}
        |> QueueItem.create_changeset(%{
          package_id: package.id,
          batch_id: batch.id,
          kind: :ambiguous_match,
          statement_ref: "t9",
          subject: %{"name_as_written" => "CYNIPS FIRMUS", "rank" => "species"},
          proposal: %{"candidate_ids" => [wasp.id], "proposed" => wasp.id}
        })
        |> Repo.insert!()

      torymus = item(package, "Torymus")
      {:ok, view, _html} = step(conn, package)

      view
      |> element("#bulk-which_taxon", "Accept firm matches (1)")
      |> render_click()

      assert has_element?(
               view,
               "#bulk-confirm-which_taxon",
               "Accept 1 firm match: CYNIPS FIRMUS → Candidus firmus."
             )

      view |> element("#bulk-accept-which_taxon") |> render_click()

      assert Import.get_queue_item!(firm.id).decision == %{"taxon_id" => wasp.id}
      assert Import.get_queue_item!(torymus.id).status == :open
    end
  end

  describe "a Host" do
    test "its row, opened, says what WCVP holds; with nothing, links to POWO and IPNI",
         %{conn: conn} do
      %{package: package} = gall_package!()
      host = item(package, "Q. lobata")
      {:ok, view, _html} = step(conn, package)

      refute has_element?(view, "#item-#{host.id}-wcvp")
      open_row(view, host)
      render_async(view)

      panel = "#item-#{host.id}-wcvp"
      assert has_element?(view, panel, "doesn't hold “Q. lobata” or a near spelling")

      assert has_element?(
               view,
               "#{panel} a[href='https://powo.science.kew.org/results?q=Q.+lobata'][target=_blank]",
               "POWO"
             )

      assert has_element?(view, "#{panel} a[href='https://www.ipni.org/?q=Q.+lobata']", "IPNI")
    end

    test "an unnamed oak: a section of the genus first, picked from its sections",
         %{conn: conn} do
      quercus = plant_fixture(name: "Quercus", rank: :genus)
      lobatae = plant_fixture(name: "Lobatae", rank: :section, parent: quercus)
      white = plant_fixture(name: "Quercus", rank: :section, parent: quercus)
      plant_fixture(name: "Quercus fixtvelutina", parent: lobatae)
      plant_fixture(name: "Quercus fixtalba", parent: white)
      {:ok, _} = Taxa.add_common_name(test_actor(), quercus, "Oaks")
      {:ok, _} = Taxa.add_common_name(test_actor(), lobatae, "Red Oaks")

      %{package: package} = gall_package!("an unknown oak", common_name: true)
      host = item(package, "an unknown oak")
      {:ok, view, _html} = step(conn, package)
      open_row(view, host)

      labels =
        view
        |> element("#item-#{host.id}-choices")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("label > span:first-of-type")
        |> Enum.map(&String.trim(LazyHTML.text(&1)))

      assert labels == [
               "A section of Quercus",
               "Another plant…",
               "Only the genus: Quercus",
               "Leave this Host out"
             ]

      choose(view, host, "A section of Quercus")
      sections = "#item-#{host.id}-picker-sections"
      assert has_element?(view, sections, "Lobatae")
      assert has_element?(view, sections, "Red Oaks")
      assert has_element?(view, "#{sections} input#item-#{host.id}-picker-sections-Quercus")
      assert has_element?(view, "#item-#{host.id}-decide[disabled]")
      assert has_element?(view, "#item-#{host.id}-effect", "Choose the section from the list.")

      view |> element("##{"item-#{host.id}-picker-sections-Lobatae"}") |> render_click()

      assert has_element?(
               view,
               "#item-#{host.id}-effect",
               "Ashmead 1897's Host statements go on sect. Lobatae, not a species."
             )

      view |> element("#item-#{host.id}-decide") |> render_click()
      assert Import.get_queue_item!(host.id).decision == %{"taxon_id" => lobatae.id}
    end

    test "in neither Gallformers nor WCVP: a link to create the plant in a new tab, prefilled",
         %{conn: conn} do
      genus = plant_fixture(name: "Fixtrubus#{System.unique_integer([:positive])}", rank: :genus)
      written = "#{Taxa.accepted_name(genus)} villosus var. frondosus"
      %{package: package} = gall_package!(written)
      host = item(package, written)
      {:ok, view, _html} = step(conn, package)
      open_row(view, host)
      render_async(view)

      panel = "#item-#{host.id}-wcvp"
      assert has_element?(view, panel, "Not in Gallformers or WCVP?")

      expected = %{
        "name" => written,
        "rank" => "variety",
        "kingdom" => "Plantae",
        "parent_id" => "#{genus.id}"
      }

      assert new_plant_query(view, panel) == expected

      choose(view, host, "Another plant…")
      follow = "#item-#{host.id}-choices [data-role=new-plant]"
      assert has_element?(view, follow, "(opens in a new tab), then search for it here.")
      assert new_plant_query(view, follow) == expected
    end

    test "the link writes out an abbreviated genus with the batch's", %{conn: conn} do
      %{package: package} = gall_package!("A. fixtlobata")
      host = item(package, "A. fixtlobata")
      {:ok, view, _html} = step(conn, package)
      open_row(view, host)
      render_async(view)

      assert %{"name" => "Andricus fixtlobata", "rank" => "species"} =
               new_plant_query(view, "#item-#{host.id}-wcvp")
    end

    test "the plant search finds a plant created after the page opened", %{conn: conn} do
      %{package: package} = gall_package!("Fixtrubus villosus var. frondosus")
      host = item(package, "Fixtrubus villosus var. frondosus")
      {:ok, view, _html} = step(conn, package)
      open_row(view, host)
      choose(view, host, "Another plant…")

      plant = plant_fixture(name: "Fixtrubus frondosus")

      view
      |> with_target("#item-row-#{host.id}")
      |> render_hook("search_plant", %{"value" => "Fixtrubus fron"})

      view
      |> element("#item-#{host.id}-picker-results button", "Fixtrubus frondosus")
      |> render_click()

      view |> element("#item-#{host.id}-decide") |> render_click()
      assert Import.get_queue_item!(host.id).decision["taxon_id"] == plant.id
    end

    test "a name WCVP holds says so, its status, and that Gallformers doesn't hold it",
         %{conn: conn} do
      %{package: package} = gall_package!("Wcvptestus alpinus")
      host = item(package, "Wcvptestus alpinus")
      {:ok, view, _html} = step(conn, package)
      open_row(view, host)
      render_async(view)

      assert has_element?(
               view,
               "#item-#{host.id}-wcvp",
               "holds Wcvptestus alpinus Test (Accepted), which Gallformers doesn't hold yet."
             )
    end
  end
end
