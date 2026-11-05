defmodule GallformersWeb.Admin.VocabularyLiveTest do
  @moduledoc """
  The superadmin vocabulary page (`/admin/vocabulary`, matter `d213`, Task
  D; it replaces 6611's vocabulary requests): the Source terms by Trait,
  with status, category, how each was placed and how many Galls use it;
  moving a term (its attributions move with it), marking it ambiguous or
  not; adding a category; the terms that fit no category, placed from
  there; and the placements made by agreement, and those the producer
  suggested another category for, to spot-check.

  Not async: the Catalog vocabularies are loaded, and packages create
  Sources (unique titles).
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Import

  @path "/admin/vocabulary"

  defp term_row(trait, term), do: "#term-#{Catalog.get_term(trait, term).id}"

  describe "a superadmin" do
    setup %{conn: conn} do
      {conn, _user} = log_in_admin(conn, "Sue Senior", ["superadmin"])
      load_vocab!()
      %{conn: conn}
    end

    setup :audit_test_metadata

    test "sees the terms by Trait, with status, category, placing and Galls", %{conn: conn} do
      gall = gall_fixture(name: "An ovoid gall")
      source = source_fixture("Shapes", "1990")

      {:ok, _} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: gall.id, trait: "shape", value: "globular"},
          confirm(source, %{term: "ovoid"})
        )

      {:ok, view, html} = live(conn, @path)
      assert html =~ "Vocabulary"

      row = term_row("shape", "ovoid")
      assert has_element?(view, row, "ovoid")
      assert has_element?(view, row, "globular")
      assert has_element?(view, row, "Placed")
      assert has_element?(view, row, "Seeded")
      assert has_element?(view, "#{row} [data-role=galls]", "1")
    end

    test "filters the terms by Trait and by search", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      view |> form("#term-filters", %{"trait" => "texture", "q" => ""}) |> render_change()
      assert has_element?(view, term_row("texture", "rough"))
      refute has_element?(view, term_row("shape", "ovoid"))

      view |> form("#term-filters", %{"trait" => "", "q" => "ovo"}) |> render_change()
      assert has_element?(view, term_row("shape", "ovoid"))
      refute has_element?(view, term_row("texture", "rough"))
    end

    test "moves a term to another category, its Facts' attributions with it", %{conn: conn} do
      gall = gall_fixture(name: "A rough gall")
      source = source_fixture("Textures", "1990")
      key = %{gall_id: gall.id, trait: "texture", value: "mealy"}
      {:ok, _} = Catalog.assert_trait(test_actor(), key, confirm(source, %{term: "rough"}))

      {:ok, view, _html} = live(conn, @path)
      row = term_row("texture", "rough")
      view |> element("#{row} button", "Change…") |> render_click()

      view
      |> form("#{row}-move", %{"category" => "bumpy"})
      |> render_submit()

      assert %{status: :placed, categories: ["bumpy"], placed_by: :superadmin} =
               Catalog.get_term("texture", "rough")

      {:ok, fact_id} = Catalog.find_fact(:trait, %{key | value: "bumpy"})
      assert [%{source_id: id, term: "rough"}] = Facts.list_attributions(fact_id)
      assert id == source.id
      assert Catalog.gall_summary(gall.id).traits["texture"] == ["bumpy"]
      assert render(view) =~ "Moved “rough” to bumpy"
    end

    test "marks a term ambiguous, and back", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      row = term_row("shape", "ovoid")
      view |> element("#{row} button", "Change…") |> render_click()

      view
      |> form("#{row}-ambiguous", %{"candidates" => ["globular", "sphere"]})
      |> render_submit()

      assert %{status: :ambiguous, candidates: candidates} = Catalog.get_term("shape", "ovoid")
      assert Enum.sort(candidates) == ["globular", "sphere"]
      assert has_element?(view, row, "Used in more than one sense")

      view |> element("#{row} button", "Change…") |> render_click()
      view |> form("#{row}-unambiguous", %{"category" => "globular"}) |> render_submit()

      assert %{status: :placed, categories: ["globular"]} = Catalog.get_term("shape", "ovoid")
    end

    test "adds a category, a definition required", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      html =
        view
        |> form("#add-category", %{
          "trait" => "shape",
          "value" => "lenticular",
          "definition" => ""
        })
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Catalog.get_trait_value("shape", "lenticular") == nil

      view
      |> form("#add-category", %{
        "trait" => "shape",
        "value" => "lenticular",
        "definition" => "Round and flattened, like a lens."
      })
      |> render_submit()

      assert %{definition: "Round and flattened, like a lens."} =
               Catalog.get_trait_value("shape", "lenticular")

      assert [%{key: %{"trait" => "shape", "value" => "lenticular"}}] =
               Enum.filter(Import.list_replay_entries(), &(&1.kind == :trait_value_added))
    end

    test "places a term that fits no category from its list", %{conn: conn} do
      {:ok, _} = Catalog.mark_term_no_fit(test_actor(), "texture", "lumpy", :curator)
      {:ok, view, _html} = live(conn, @path)

      assert has_element?(view, "#no-fit", "lumpy")
      view |> form("#no-fit-texture-lumpy", %{"category" => "bumpy"}) |> render_submit()

      assert %{status: :placed, categories: ["bumpy"], placed_by: :superadmin} =
               Catalog.get_term("texture", "lumpy")

      refute has_element?(view, "#no-fit", "lumpy")
    end

    test "spot-checks a placement made by agreement", %{conn: conn} do
      {:ok, _} =
        Import.record_term_edit(test_actor(), {:place, "color", "pale tan", "tan", :agreement})

      {:ok, view, _html} = live(conn, @path)
      row = "#agreement-color-pale-tan"
      assert has_element?(view, row, "pale tan")
      assert has_element?(view, row, "tan")

      view |> element("#{row} button", "Looks right") |> render_click()
      assert %{spot_checked_at: %DateTime{}} = Catalog.get_term("color", "pale tan")
      refute has_element?(view, row)
    end

    test "lists the Facts whose producer suggested another category", %{conn: conn} do
      plant_fixture(name: "Quercus lobata")
      taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
      taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")

      fact = %{
        "id" => "f6",
        "stance" => "confirm",
        "kind" => "trait",
        "gall" => "g1",
        "trait" => "color",
        "term" => "tan",
        "category" => %{"value" => "white"},
        "evidence" => [%{"item" => "#/texts/1", "quote" => "pale tan when mature"}]
      }

      gall =
        batch()
        |> unique_batch_id()
        |> Map.put("format_version", 4)
        |> put_in(["source", "title"], "Pale galls")
        |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
        |> put_in(["galls", Access.at(0), "new"], true)
        |> Map.update!("facts", &(&1 ++ [fact]))

      package = package(gall: gall) |> with_review() |> deliver!()
      {:ok, _} = Import.approve_package(test_actor(), package)
      assert [_] = Import.list_term_spot_checks()

      {:ok, view, _html} = live(conn, @path)
      row = "#suggested-color-tan"
      assert has_element?(view, row, "tan")
      assert has_element?(view, row, "white")

      view |> element("#{row} button", "Looks right") |> render_click()
      refute has_element?(view, row)
    end
  end

  describe "seed terms (Task F)" do
    setup %{conn: conn} do
      {conn, _user} = log_in_admin(conn, "Sue Senior", ["superadmin"])
      load_vocab!()

      root = Path.join(System.tmp_dir!(), "seed_terms_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(root) end)

      # "rounded": globular twice, set aside once; "pear-shaped": globular
      # twice; "lens-like": no category; "pale": tan.
      write_seed_package!(Path.join(root, "pkg-a"), [
        {"g1", "shape", "rounded", "globular", "a rounded gall"},
        {"g2", "shape", "rounded", "globular", "rounded above"},
        {"g3", "shape", "rounded", nil, "roughly rounded"},
        {"g1", "shape", "pear-shaped", "globular", "pear-shaped"},
        {"g2", "shape", "pear-shaped", "globular", "pear-shaped too"},
        {"g3", "shape", "lens-like", nil, "flat and lens-like"},
        {"g1", "color", "pale", "tan", "pale when old"}
      ])

      {:ok, _} = Import.gather_term_candidates(test_actor(), [root])
      %{conn: conn}
    end

    setup :audit_test_metadata

    defp write_seed_package!(dir, uses) do
      facts =
        for {{gall, trait, term, category, quote}, i} <- Enum.with_index(uses) do
          %{
            "id" => "f#{i}",
            "stance" => "confirm",
            "kind" => "trait",
            "gall" => gall,
            "trait" => trait,
            "term" => term,
            "category" => category && %{"value" => category},
            "evidence" => [%{"item" => "#/texts/1", "quote" => quote}]
          }
        end

      File.mkdir_p!(dir)

      File.write!(
        Path.join(dir, "gall.json"),
        Jason.encode!(%{
          "format_version" => 4,
          "galls" => for(g <- ~w(g1 g2 g3), do: %{"ref" => g, "name_as_written" => "Gall #{g}"}),
          "facts" => facts
        })
      )
    end

    defp seed_row(trait, term) do
      candidate =
        Enum.find(
          Import.list_term_candidates(decided: true),
          &(&1.trait == trait and &1.normalized_term == term)
        )

      "#seed-#{candidate.id}"
    end

    test "lists the candidates by Trait, most used first, with their suggestions", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      rounded = seed_row("shape", "rounded")
      assert has_element?(view, rounded, "rounded")
      assert has_element?(view, "#{rounded} [data-role=uses]", "3")
      assert has_element?(view, rounded, "globular 2")
      assert has_element?(view, rounded, "set aside 1")
      assert has_element?(view, "#seed-terms-shape", "rounded")
      assert has_element?(view, "#seed-terms-color", "pale")

      html = view |> element("#seed-terms-shape") |> render()
      assert :binary.match(html, "rounded") < :binary.match(html, "lens-like")

      view |> element("#{rounded}-row") |> render_click()
      assert has_element?(view, "#{rounded}-detail", "roughly rounded")
    end

    test "places a term under its single suggestion", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      row = seed_row("shape", "pear-shaped")

      view |> element("#{row} button", "Place under globular") |> render_click()

      assert %{status: :placed, categories: ["globular"], placed_by: :superadmin} =
               Catalog.get_term("shape", "pear-shaped")

      refute has_element?(view, row)
      assert has_element?(view, term_row("shape", "pear-shaped"))
    end

    test "a term whose uses disagree has no default placement; places under another category",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      row = seed_row("shape", "rounded")

      refute has_element?(view, "#{row} button", "Place under globular")
      view |> element("#{row}-row") |> render_click()
      view |> form("#{row}-place", %{"category" => "sphere"}) |> render_submit()

      assert %{status: :placed, categories: ["sphere"]} = Catalog.get_term("shape", "rounded")
      refute has_element?(view, row)
    end

    test "marks a term ambiguous, the suggestions ticked", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      row = seed_row("shape", "rounded")
      view |> element("#{row}-row") |> render_click()

      assert has_element?(view, "#{row}-ambiguous input[value=globular][checked]")

      view
      |> form("#{row}-ambiguous", %{"candidates" => ["globular", "sphere"]})
      |> render_submit()

      assert %{status: :ambiguous, candidates: candidates} = Catalog.get_term("shape", "rounded")
      assert Enum.sort(candidates) == ["globular", "sphere"]
      refute has_element?(view, row)
    end

    test "marks a term as fitting no category", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      row = seed_row("shape", "lens-like")

      view |> element("#{row} button", "Fits no category") |> render_click()

      assert %{status: :no_fit} = Catalog.get_term("shape", "lens-like")
      refute has_element?(view, row)
    end

    test "skips a term for now, changing nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      row = seed_row("color", "pale")

      view |> element("#{row} button", "Skip for now") |> render_click()

      refute has_element?(view, row)
      assert Catalog.get_term("color", "pale") == nil

      assert %{total: 1} =
               Enum.find(Import.list_term_candidates(), &(&1.normalized_term == "pale"))
    end

    test "decided candidates are shown on asking", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      row = seed_row("color", "pale")
      view |> element("#{row} button", "Place under tan") |> render_click()
      refute has_element?(view, row)

      view |> element("#seed-show-decided") |> render_click()
      assert has_element?(view, row, "Placed under tan")
    end

    test "places the ticked rows whose uses agree, after confirming the count", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      egg = seed_row("shape", "pear-shaped")
      pale = seed_row("color", "pale")
      rounded = seed_row("shape", "rounded")

      for row <- [egg, pale, rounded], do: view |> element("#{row}-tick") |> render_click()

      view |> element("#seed-bulk-place") |> render_click()
      assert has_element?(view, "#seed-bulk-confirm", "Place 2 terms")
      assert Catalog.get_term("shape", "pear-shaped") == nil

      view |> element("#seed-bulk-confirm button", "Place 2 terms") |> render_click()

      assert %{status: :placed, categories: ["globular"]} =
               Catalog.get_term("shape", "pear-shaped")

      assert %{status: :placed, categories: ["tan"]} = Catalog.get_term("color", "pale")
      assert Catalog.get_term("shape", "rounded") == nil
      assert has_element?(view, rounded)
      refute has_element?(view, egg)

      places =
        for %{kind: :trait_term_edit, key: %{"op" => "place", "term" => term}} <-
              Import.list_replay_entries(),
            do: term

      assert Enum.sort(places) == ["pale", "pear-shaped"]
    end
  end

  describe "an admin who is not a superadmin" do
    setup %{conn: conn} do
      {conn, _user} = log_in_admin(conn, "Ada Admin", ["admin"])
      %{conn: conn}
    end

    test "can't reach it", %{conn: conn} do
      assert conn |> get(@path) |> html_response(403)
    end
  end

  test "mounts through the superadmin on_mount hook" do
    %{phoenix_live_view: {_view, _action, _opts, live_session}} =
      Phoenix.Router.route_info(GallformersWeb.Router, "GET", @path, "localhost")

    assert {GallformersWeb.Live.UserAuth, :require_superadmin} in Enum.map(
             live_session.extra.on_mount,
             & &1.id
           )
  end
end
