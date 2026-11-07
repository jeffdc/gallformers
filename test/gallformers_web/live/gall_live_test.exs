defmodule GallformersWeb.GallLiveTest do
  @moduledoc """
  LiveView tests for the Gall detail page, which reads
  `Gallformers.Catalog.gall_page/1`.

  Uses the converted seeds (`priv/repo/test_seeds.sql`): Galls 300/301 are
  an agamic/sexgen pair of Andricus seedii (300 has an image, a Gallformers
  note, a default citation of Source 59, a common name and a synonym; 301's
  default Source is its note), 304 an undescribed Andricus gall with a
  Gallformers Code, a former label, a code and a genus Host, 102 a Gall with
  no Hosts; plant 10 is the Host of 300–304.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Catalog
  alias Gallformers.DataCase

  # A Gall merged away (`Gallformers.Import.record_merge/2`) leaves a redirect.
  defp redirect_gall!(from_id, from_code, to_id) do
    {:ok, _} =
      Gallformers.Audit.transaction(DataCase.test_actor(), "test.redirect", fn ->
        Gallformers.Repo.insert!(%Gallformers.Catalog.GallRedirect{
          from_gall_id: from_id,
          from_code: from_code,
          gall_id: to_id
        })
      end)
  end

  describe "Gall page rendering" do
    test "renders the Gall's name, its generation split off", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/300")

      assert html =~ "Andricus seedii"
      assert html =~ "agamic"
    end

    test "an ID that isn't a number is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/gall/invalid") end
    end

    test "a missing ID and an ID that is not a Gall are 404s", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/gall/999999999") end
      assert_error_sent 404, fn -> get(conn, ~p"/gall/10") end
    end

    test "an old ID excluded as a non-gall redirects (301) to the gall-lookalikes Article",
         %{conn: conn} do
      {:ok, 1} =
        Catalog.insert_non_gall_redirects(DataCase.test_actor(), [
          %{species_id: 990_250, name: "Fixturella lookalike"}
        ])

      conn = get(conn, "/gall/990250")

      assert redirected_to(conn, 301) == "/articles/gall-lookalikes"
    end

    test "a merged Gall's old ID and code redirect (301) to the Gall it became", %{conn: conn} do
      redirect_gall!(990_300, "MRGD990300", 300)

      assert redirected_to(get(conn, "/gall/990300"), 301) == "/gall/300"
      assert redirected_to(get(build_conn(), "/gall/mrgd990300"), 301) == "/gall/300"
      assert_error_sent 404, fn -> get(build_conn(), "/gall/NOPE990300") end
    end

    test "live navigation to a merged Gall's old ID goes to the Gall it became", %{conn: conn} do
      redirect_gall!(990_301, "MRGD990301", 300)

      {:ok, view, _html} = live(conn, ~p"/gall/301")

      assert {:error, {:live_redirect, %{to: "/gall/300"}}} =
               live_redirect(view, to: "/gall/990301")
    end

    test "shows the Inducer's taxonomy as a breadcrumb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "a[href='/family/Cynipidae']")
      assert has_element?(view, "a[href='/subfamily/Cynipinae']")
      assert has_element?(view, "a[href='/tribe/Cynipini']")
      assert has_element?(view, "a[href='/genus/Andricus']")
      assert has_element?(view, "h1", "Andricus seedii")
    end

    test "the breadcrumb ends with the Inducer, linked to its species page", %{conn: conn} do
      {:ok, inducer} = Gallformers.Taxa.resolve_name("Andricus seedii", rank: :species)
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "header nav a[href='/species/#{inducer.id}']", "Andricus seedii")
    end

    test "an undescribed Gall's genus Inducer adds no species crumb", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/304")

      refute has_element?(view, "header nav a[href^='/species/']")
    end

    test "shows Traits and abundance", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "#gall-traits div", ~r/^\s*Detachable\s*Detachable\s*$/)
      assert has_element?(view, "#gall-traits div", ~r/^\s*Abundance\s*common\s*$/)
      assert has_element?(view, "#gall-traits", "Not recorded")
    end

    test "displays completion status badge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/300")
      assert html =~ "Complete"

      {:ok, _view, html} = live(conn, ~p"/gall/301")
      assert html =~ "In progress"
    end

    test "shows common names and the Inducer's synonyms", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "header", "seed oak apple")
      assert has_element?(view, "#gall-names", "seed oak apple")
      assert has_element?(view, "#gall-names", "Callirhytis seedii")
    end

    test "shows former labels and codes in the names table, not as common names",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/304")

      refute has_element?(view, "#gall-names", "common name")
      assert has_element?(view, "#gall-names", ~r/Andricus q-seed-old-label\s*\(former label\)/)
      assert has_element?(view, "#gall-names", ~r/q-seed-code\s*\(code\)/)
    end

    test "lists the other generation as a related Gall", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "header", "Other generation")
      assert has_element?(view, "header a[href='/gall/301']")
    end
  end

  describe "the Sources' terms for its Traits (d213)" do
    import Gallformers.CatalogFixtures

    setup do
      load_vocab!()
      %{gall: gall_fixture()}
    end

    defp trait!(gall, {trait, value}, attribution) do
      {:ok, _} =
        Catalog.assert_trait(
          DataCase.test_actor(),
          %{gall_id: gall.id, trait: trait, value: value},
          attribution
        )
    end

    # A waiting term needs the package and batch it came from.
    defp waiting!(gall, source, trait, term) do
      n = System.unique_integer([:positive])
      now = ~U[2026-11-01 00:00:00Z]

      {1, [%{id: package_id}]} =
        Gallformers.Repo.insert_all(
          "import_packages",
          [
            %{
              key: "pkg-#{n}",
              s3_prefix: "import/pkg-#{n}/",
              submitter_name: "test",
              inserted_at: now,
              updated_at: now
            }
          ],
          returning: [:id]
        )

      {1, [%{id: batch_id}]} =
        Gallformers.Repo.insert_all(
          "import_batches",
          [
            %{
              package_id: package_id,
              file: "gall.json",
              batch_type: "gall",
              mode: "add",
              producer_batch_id: "batch-#{n}",
              sha256: "0",
              content: %{},
              inserted_at: now,
              updated_at: now
            }
          ],
          returning: [:id]
        )

      {:ok, _} =
        Catalog.put_pending_term(DataCase.test_actor(), %{
          gall_id: gall.id,
          source_id: source.id,
          package_id: package_id,
          batch_id: batch_id,
          trait: trait,
          term: term
        })
    end

    test "each category shows its Sources' terms; a waiting term shows as text", %{
      conn: conn,
      gall: gall
    } do
      kinsey = source_fixture("Kinsey", "1959")
      weld = source_fixture("Weld", "1959")

      trait!(gall, {"shape", "globular"}, confirm(kinsey, %{term: "ovoid"}))
      trait!(gall, {"shape", "globular"}, confirm(weld, %{term: "oval"}))
      trait!(gall, {"color", "red"}, confirm(kinsey))
      trait!(gall, {"texture", "hairless"}, confirm(kinsey, %{term: "hairless"}))
      waiting!(gall, kinsey, "texture", "reticulate")
      waiting!(gall, kinsey, "walls", "papery")

      {:ok, view, _html} = live(conn, ~p"/gall/#{gall.id}")

      assert has_element?(view, "#gall-traits div", ~r/^\s*Shape\s*globular \(oval, ovoid\)\s*$/)
      assert has_element?(view, "#gall-traits div", ~r/^\s*Color\s*red\s*$/)

      assert has_element?(
               view,
               "#gall-traits div",
               ~r/^\s*Texture\s*hairless; also described as “reticulate”\s*$/
             )

      assert has_element?(view, "#gall-traits div", ~r/^\s*Walls\s*described as “papery”\s*$/)
    end
  end

  describe "the Gall's Facts (ec2c, finding 5)" do
    import Gallformers.CatalogFixtures

    setup do
      load_vocab!()
      %{gall: gall_fixture()}
    end

    test "everyone sees them by category, each with its Sources linked", %{
      conn: conn,
      gall: gall
    } do
      kinsey = source_fixture("Kinsey", "1959")
      weld = source_fixture("Weld", "1960")
      trait!(gall, {"color", "red"}, confirm(kinsey))
      trait!(gall, {"color", "red"}, confirm(weld))

      {:ok, _} =
        Catalog.assert_alias(
          DataCase.test_actor(),
          %{gall_id: gall.id, name: "red knob gall"},
          confirm(weld)
        )

      {:ok, view, _html} = live(conn, ~p"/gall/#{gall.id}")

      assert has_element?(view, "#gall-facts h2", "Facts")
      red = "#gall-facts [data-role=current] [data-category=traits] [data-trait=color]"
      assert has_element?(view, red, "red")
      assert has_element?(view, "#{red} a[href='/source/#{kinsey.id}']", "Weld 1959")
      assert has_element?(view, "#{red} a[href='/source/#{weld.id}']", "Weld 1960")
      assert has_element?(view, "#gall-facts [data-category=aliases]", "red knob gall")

      # Read-only, and the Gall's own name isn't repeated as a header.
      refute has_element?(view, "#gall-facts [data-role=fact-menu]")
      refute has_element?(view, "#gall-facts a[href='/gall/#{gall.id}']")
    end

    test "withdrawn and superseded Facts are collapsed as history, each marked", %{
      conn: conn,
      gall: gall
    } do
      kinsey = source_fixture("Kinsey", "1959")
      weld = source_fixture("Weld", "2001")
      trait!(gall, {"color", "red"}, confirm(kinsey))
      trait!(gall, {"color", "red"}, deny(weld))
      trait!(gall, {"detachable", "integral"}, confirm(kinsey))
      trait!(gall, {"detachable", "detachable"}, confirm(weld))

      {:ok, view, _html} = live(conn, ~p"/gall/#{gall.id}")

      current = "#gall-facts [data-role=current]"
      history = "#gall-facts details[data-role=history]"

      assert has_element?(view, "#{current} [data-trait=detachable]", "detachable")
      refute has_element?(view, "#{current} [data-trait=color]")
      refute has_element?(view, "#{current} [data-trait=detachable]", "integral")

      assert has_element?(view, "#{history} summary", "1 withdrawn, 1 superseded")
      assert has_element?(view, "#{history} [data-trait=color]", "withdrawn")
      assert has_element?(view, "#{history} [data-trait=color]", "red")
      assert has_element?(view, "#{history} [data-trait=color]", "denied by")
      assert has_element?(view, "#{history} [data-trait=color] a[href='/source/#{weld.id}']")
      assert has_element?(view, "#{history} [data-trait=detachable]", "superseded")
    end

    test "a Gall with no Facts has no Facts section", %{conn: conn, gall: gall} do
      {:ok, view, _html} = live(conn, ~p"/gall/#{gall.id}")

      refute has_element?(view, "#gall-facts")
    end
  end

  describe "the admin link" do
    test "an admin gets Edit; a visitor doesn't", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")
      refute has_element?(view, "a[href='/gall/300?edit']")

      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/300")
      assert has_element?(view, "a[href='/gall/300?edit']", "Edit")
    end

    test "an admin's image edit link opens the image manager in Edit mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")
      refute has_element?(view, "#gall-images a[href='/gall/300?edit&photos']")

      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/300")
      assert has_element?(view, "#gall-images a[href='/gall/300?edit&photos']", "Edit photos")
    end

    test "a Gall with no images offers an admin to add them on the Gall page", %{conn: conn} do
      gall = Gallformers.CatalogFixtures.gall_fixture()
      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/#{gall.id}")

      assert has_element?(view, "a[href='/gall/#{gall.id}?edit&photos']", "Add images")
    end

    test "no admin link goes to a deleted old screen", %{conn: conn} do
      {admin_conn, _user} = GallformersWeb.AdminLiveHelpers.log_in_admin(conn)
      {:ok, view, _html} = live(admin_conn, ~p"/gall/300")

      refute has_element?(view, "a[href^='/admin/gallhost']")
      refute has_element?(view, "a[href^='/admin/images']")
    end
  end

  describe "undescribed Galls" do
    test "show the undescribed notice, the Code and its iNaturalist link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/304")

      assert html =~ "The inducer of this gall is unknown or undescribed."
      assert html =~ "iNaturalist"
      assert html =~ "n-densiflorus-seed-gall"
    end

    test "a described Gall shows no undescribed notice", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/300")

      refute html =~ "unknown or undescribed"
    end
  end

  describe "Page title and SEO" do
    test "sets page title to the Gall's name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert page_title(view) =~ "Andricus seedii (agamic)"
    end

    test "describes the Gall from its Traits", %{conn: conn} do
      html = conn |> get(~p"/gall/300") |> html_response(200)

      assert html =~ "Andricus seedii (agamic) - A gall. Detachable."
    end
  end

  describe "Host links" do
    test "a species-rank Host links to its host page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "a[href='/host/10']", "Notholithocarpus densiflorus")
    end

    test "a genus Host links to its genus page, marked genus-level", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/304")

      assert has_element?(view, "a[href='/genus/Notholithocarpus']", "(genus-level)")
      assert has_element?(view, "a[href='/host/10']")
    end
  end

  defp source_titles(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#gall-sources li a[href^='/source/']")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  describe "Range map" do
    test "Enlarge opens the large map in a dialog; closing returns to the card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      view |> element("button", "Enlarge") |> render_click()
      assert has_element?(view, "#range-dialog #gall-range-map-large")
      refute has_element?(view, "#gall-range-map")

      render_click(view, "close_map", %{})
      refute has_element?(view, "#range-dialog")
      assert has_element?(view, "#gall-range-map")
    end

    test "the map frames the native range, not the introduced one", %{conn: conn} do
      import Gallformers.CatalogFixtures

      oak = plant_fixture()
      host_range_fixture(oak, [{"US-CA", "exact"}, {"RO-B", "exact", "introduced"}])
      gall = gall_fixture()

      {:ok, _} =
        Catalog.assert_relationship(
          DataCase.test_actor(),
          %{type: "host_of", subject_taxon_id: oak.id, object_gall_id: gall.id},
          confirm(source_fixture("Weld", "1959"))
        )

      {:ok, view, _html} = live(conn, ~p"/gall/#{gall.id}")
      map = view |> element("#gall-range-map") |> render()

      assert map =~ "RO-B"
      assert [_, bounds] = Regex.run(~r/data-bounds="([^"]*)"/, map)

      assert Jason.decode!(String.replace(bounds, "&quot;", ~s("))) ==
               Gallformers.Places.get_bounds_for_codes(["US-CA"])
               |> Jason.encode!()
               |> Jason.decode!()
    end

    test "shows the Hosts' range with its disclaimer", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "#gall-range-map")
      assert html =~ "not where the gall was found"
    end

    test "a Gall with no Host range data has no map", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/102")

      refute has_element?(view, "#gall-range-map")
      assert html =~ "Range unknown"
    end
  end

  describe "Sources" do
    test "the default citation and the Gallformers note link to their Source pages",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "#gall-sources-section [data-part=count]", "1")

      assert has_element?(
               view,
               "#gall-sources a[href='/source/59']",
               "Cynipid galls of the seed slope"
             )

      assert html =~ "seed citation"
      # The Gallformers note is pinned, in full, above the Sources.
      assert has_element?(view, "#id-notes", "The seed note")
      assert has_element?(view, "#id-notes a[href='/source/58']", "Gallformers ID Notes")
    end

    test "Read opens the ID Notes in the reader, as it does a Source", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      view |> element("#id-notes button", "Read") |> render_click()

      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "The seed note"
    end

    test "the ID Notes and the reader set the text in serif; A+ and A- step its size",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/300")

      assert has_element?(
               view,
               "#id-notes .gf-prose[data-font=serif][data-size=sm]",
               "The seed note"
             )

      view |> element("#id-notes button", "Read") |> render_click()
      assert has_element?(view, "#source-detail-modal .gf-prose[data-font=serif][data-size=base]")

      view
      |> element("#source-detail-modal button[phx-click=increase_font_size]")
      |> render_click()

      assert has_element?(view, "#source-detail-modal .gf-prose[data-size=lg]")

      view
      |> element("#source-detail-modal button[phx-click=decrease_font_size]")
      |> render_click()

      view
      |> element("#source-detail-modal button[phx-click=decrease_font_size]")
      |> render_click()

      assert has_element?(view, "#source-detail-modal .gf-prose[data-size=sm]")
    end

    test "run by year, oldest first; Newest first reverses them", %{conn: conn} do
      for {title, year} <- [{"Later fixture source", "2024"}, {"Earlier fixture source", "1990"}] do
        source =
          Gallformers.Repo.insert!(%Gallformers.Sources.Source{
            title: title,
            author: "Fixture",
            pubyear: year,
            link: "",
            citation: title,
            license: "Public Domain"
          })

        {:ok, 1} =
          Catalog.insert_legacy_citations(DataCase.test_actor(), [
            %{gall_id: 100, source_id: source.id, description: title, useasdefault: false}
          ])
      end

      {:ok, view, _html} = live(conn, ~p"/gall/100")
      titles = fn -> view |> render() |> source_titles() end

      assert titles.() == ["Earlier fixture source", "Later fixture source"]

      view |> element("button[phx-click=sources_order][phx-value-order=desc]") |> render_click()
      assert titles.() == ["Later fixture source", "Earlier fixture source"]
    end

    test "a Gall with none says so", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gall/302")

      assert html =~ "No further information available"
    end
  end

  describe "Source deep-linking via ?source= param" do
    setup do
      source =
        Gallformers.Repo.insert!(%Gallformers.Sources.Source{
          title: "Test Source for Deep Link",
          author: "Test Author",
          pubyear: "2024",
          link: "https://example.com",
          citation: "Test citation",
          license: "Public Domain"
        })

      {:ok, 1} =
        Catalog.insert_legacy_citations(DataCase.test_actor(), [
          %{
            gall_id: 100,
            source_id: source.id,
            description: "Deep link test description",
            useasdefault: false
          }
        ])

      %{source: source}
    end

    test "opens a legacy citation when ?source= matches", %{conn: conn, source: source} do
      {:ok, view, _html} = live(conn, "/gall/100?source=#{source.id}")

      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "Deep link test description"
    end

    test "opens the Gallformers note when ?source= is its Source", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/300?source=58")

      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "The seed note"
    end

    test "ignores invalid source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100?source=invalid")

      refute has_element?(view, "#source-detail-modal")
    end

    test "ignores non-existent source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100?source=999999")

      refute has_element?(view, "#source-detail-modal")
    end

    test "page loads normally without source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/gall/100")

      refute has_element?(view, "#source-detail-modal")
    end
  end

  describe "Image display" do
    test "displays the Gall's image with its credit", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/gall/300")

      assert has_element?(view, "#gall-images img[alt]")
      assert html =~ "Seed Photographer"
    end

    test "says when the Gall has no photos, without arrows or thumbnails", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/gall/301")

      assert has_element?(view, "#gall-images [data-part=empty]", "No photos yet.")
      refute has_element?(view, "#gall-images [data-thumbs]")
      refute has_element?(view, "#gall-images a[href$='#images']")
    end
  end
end
