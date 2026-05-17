defmodule GallformersWeb.Admin.IngestionReviewLive.ShowSourceResolutionTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Species.Species

  describe "source resolution detail page" do
    test "renders persisted submission metadata", %{conn: conn} do
      reviewer = db_user_fixture("Source Reviewer")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          title: "Oak Gall Monograph",
          authors: ["A. Author", "B. Writer"],
          publication_year: 1919,
          doi: "10.1234/oak-galls"
        })

      conn = superadmin_conn(conn, reviewer)

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert html =~ "Submission Metadata"
      assert html =~ "Oak Gall Monograph"
      assert html =~ "A. Author, B. Writer"
      assert html =~ "1919"
      assert html =~ "10.1234/oak-galls"
    end

    test "source typeahead search renders matching persisted sources", %{conn: conn} do
      reviewer = db_user_fixture("Source Reviewer")
      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: reviewer.id})
      matching_source = source_fixture(%{title: "Oak Gall Atlas", author: "Field Author"})
      _other_source = source_fixture(%{title: "Pine Notes", author: "Forest Author"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      html = render_hook(view, "search_sources", %{"value" => "Oak"})

      assert html =~ matching_source.title
      refute html =~ "Pine Notes"
    end

    test "select_source updates transient state and associate_source persists it", %{conn: conn} do
      reviewer = db_user_fixture("Source Reviewer")
      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: reviewer.id})
      source = source_fixture(%{title: "Selected Source"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      html =
        view
        |> element("#source-picker")
        |> render_hook("select_source", %{"id" => source.id})

      assert html =~ "Selected Source"
      assert html =~ "This selection is not persisted yet. Use Associate Source to save it."
      assert has_element?(view, "#associate-source")
      assert Ingestions.get_source_ingestion!(ingestion.id).source_id == nil

      view
      |> element("#associate-source")
      |> render_click()

      updated = Ingestions.get_source_ingestion!(ingestion.id)

      assert updated.source_id == source.id

      html = render(view)
      assert html =~ "Source associated"
      assert html =~ "This source association is already persisted."
      refute has_element?(view, "#associate-source")
    end

    test "clear_source_association removes the persisted source link", %{conn: conn} do
      reviewer = db_user_fixture("Source Reviewer")
      source = source_fixture(%{title: "Persisted Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Locked Gall"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#source-picker [aria-label='Clear selection']")
      |> render_click()

      updated = Ingestions.get_source_ingestion!(ingestion.id)

      assert updated.source_id == nil

      html = render(view)
      assert html =~ "Source association cleared"
      assert html =~ "Associate a source to enable gall review."
      refute has_element?(view, "#review-species-entry-")
    end

    test "gall list renders in persisted position order with mapped species and host counts", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Source Reviewer")
      source = source_fixture(%{title: "Resolved Source"})
      mapped_species = species_fixture("Andricus persistus")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      later_entry =
        source_ingestion_species_fixture(ingestion, 2, %{
          extracted_name: "Later Gall",
          extraction_payload: %{"hosts" => "invalid"}
        })

      first_entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "First Gall",
          species_id: mapped_species.id,
          extraction_payload: %{
            "hosts" => [
              %{"name" => "Quercus alba"},
              %{"name" => "Quercus stellata"}
            ]
          }
        })

      middle_entry =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Middle Gall",
          extraction_payload: %{}
        })

      conn = superadmin_conn(conn, reviewer)

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert row_index(html, first_entry.id) < row_index(html, later_entry.id)
      assert row_index(html, later_entry.id) < row_index(html, middle_entry.id)

      assert html =~ "Andricus persistus"
      assert html =~ "Quercus alba"
      assert html =~ "Quercus stellata"
    end

    test "gall review stays locked until a source is associated, then row actions appear", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Source Reviewer")
      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: reviewer.id})
      source = source_fixture(%{title: "Unlocking Source"})

      species_entry =
        source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall One"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert has_element?(view, "#species-review-source-locked")

      view
      |> element("#source-picker")
      |> render_hook("select_source", %{"id" => source.id})

      view
      |> element("#associate-source")
      |> render_click()

      refute has_element?(view, "#species-review-source-locked")
      html = render(view)
      assert html =~ species_entry.extracted_name
    end

    test "proceed to review link appears only when source is attached", %{conn: conn} do
      reviewer = db_user_fixture("Source Reviewer")
      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: reviewer.id})
      source = source_fixture(%{title: "Gating Source"})
      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall One"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      refute has_element?(view, "[data-role=proceed-to-review]")

      view
      |> element("#source-picker")
      |> render_hook("select_source", %{"id" => source.id})

      view
      |> element("#associate-source")
      |> render_click()

      assert has_element?(view, "[data-role=proceed-to-review]")

      html = render(view)
      assert html =~ ~p"/admin/ingestion-review/#{ingestion.id}/review"
    end

    test "expandable gall rows show extraction summary", %{conn: conn} do
      reviewer = db_user_fixture("Source Reviewer")
      source = source_fixture(%{title: "Summary Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extraction_payload: %{
          "hosts" => [
            %{"name" => "Quercus lobata", "authority" => "Née"},
            %{"name" => "Quercus douglasii", "authority" => "Hook. & Arn."}
          ],
          "traits" => %{
            "shape" => %{"original" => "globular", "suggested" => ["globular"]},
            "color" => %{"original" => "brown", "suggested" => ["brown"]}
          },
          "description_evidence" => [],
          "aliases" => ["Q. californicus gall"]
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert html =~ "Quercus lobata"
      assert html =~ "Quercus douglasii"
      assert html =~ "shape"
      assert html =~ "color"
    end
  end

  defp superadmin_conn(conn, db_user) do
    auth0_user = %Auth0User{
      id: db_user.auth0_id,
      email: "superadmin@test.com",
      name: db_user.display_name,
      nickname: db_user.nickname,
      picture: nil,
      roles: ["admin", "superadmin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, auth0_user)
    |> put_session(:db_display_name, db_user.display_name)
  end

  defp db_user_fixture(display_name) do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|show-source-resolution-#{System.unique_integer([:positive])}",
        display_name: display_name
      })

    user
  end

  defp source_fixture(attrs) do
    merged_attrs =
      Map.merge(
        %{
          title: "Source #{System.unique_integer([:positive])}",
          author: "Author",
          pubyear: "2026",
          link: "https://example.com/source",
          citation: "Author. 2026. Source.",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/"
        },
        attrs
      )

    {:ok, source} = Sources.create_source(merged_attrs)
    source
  end

  defp species_fixture(name) do
    {:ok, species} =
      Repo.insert(%Species{
        name: name,
        taxoncode: "gall",
        datacomplete: false
      })

    species
  end

  defp row_index(html, entry_id) do
    case :binary.match(html, ~s(id="species-entry-#{entry_id}")) do
      {index, _length} -> index
      :nomatch -> flunk("missing row for species entry #{entry_id}")
    end
  end

  defp review_ready_ingestion_fixture(attrs) do
    merged =
      attrs
      |> Map.new()
      |> Map.put_new(:input_type, "pdf")
      |> Map.put_new(:status, "needs_review")
      |> Map.put_new(:processing_stage, "review")

    {:ok, ingestion} = Ingestions.create_source_ingestion(merged)
    ingestion
  end

  defp source_ingestion_species_fixture(source_ingestion, position, attrs) do
    default_payload = %{
      "hosts" => [%{"name" => "Quercus alba", "evidence" => "On Quercus alba twigs"}],
      "traits" => %{
        "shape" => %{"original" => "globular", "suggested" => ["globular"]}
      },
      "description_evidence" => [
        %{"text" => "Rounded woolly gall on oak twigs.", "page" => 3}
      ]
    }

    merged =
      attrs
      |> Map.new()
      |> Map.put_new(:source_ingestion_id, source_ingestion.id)
      |> Map.put_new(:position, position)
      |> Map.put_new(:status, "pending")
      |> Map.put_new(:extracted_name, "Gall #{position}")
      |> Map.put_new(:extracted_authority, "Author")
      |> Map.put_new(:description_prose, "Rounded woolly gall on oak twigs.")
      |> Map.put_new(:extraction_payload, default_payload)

    {:ok, source_ingestion_species} = Ingestions.create_source_ingestion_species(merged)
    source_ingestion_species
  end
end
