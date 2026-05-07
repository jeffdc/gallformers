defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gallformers.IngestionPipelineFixtures

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Species.Species

  describe "workspace route and mount" do
    test "mounts and renders master sidebar with species entries", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Workspace Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extracted_authority: "Bassett"
      })

      source_ingestion_species_fixture(ingestion, 1, %{
        extracted_name: "Disholcaspis eldoradensis",
        extracted_authority: "Beutenmuller"
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Andricus quercuscalifornicus"
      assert html =~ "Disholcaspis eldoradensis"
      assert has_element?(view, "nav a", "Queue")
    end

    test "auto-selects first unreviewed species entry", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Auto-Select Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      _entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus quercuscalifornicus"
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Andricus quercuscalifornicus"
    end

    test "returns error for invalid ingestion ID", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      conn = superadmin_conn(conn, reviewer)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/admin/ingestion-review/999999/review")
      end
    end
  end

  describe "gall selection" do
    test "clicking a gall in the sidebar loads its workspace data", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Selection Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      _entry_a =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus quercuscalifornicus",
          extracted_authority: "Bassett"
        })

      entry_b =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Disholcaspis eldoradensis",
          extracted_authority: "Beutenmuller"
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Andricus quercuscalifornicus"

      html =
        view
        |> element("#workspace-nav-group-#{entry_b.id}")
        |> render_click()

      assert html =~ "Disholcaspis eldoradensis"
      assert html =~ "Beutenmuller"
    end

    test "master list shows progress counts", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Progress Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall A"})
      source_ingestion_species_fixture(ingestion, 1, %{extracted_name: "Gall B"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "2 remaining"
      assert html =~ "0 reviewed"
    end
  end

  describe "identity resolution" do
    test "detail pane shows extracted name, authority, and species decision radio", %{conn: conn} do
      reviewer = db_user_fixture("Identity Reviewer")
      source = source_fixture(%{title: "Identity Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extracted_authority: "Bassett"
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Andricus quercuscalifornicus"
      assert html =~ "Bassett"
      assert html =~ "Map to existing species"
      assert html =~ "Skip for later"
    end

    test "species typeahead search finds matching gall species", %{conn: conn} do
      reviewer = db_user_fixture("Search Reviewer")
      source = source_fixture(%{title: "Search Source"})
      matching_species = species_fixture("Andricus quercuscalifornicus", "gall")
      other_species = species_fixture("Betula pendula", "plant")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Some gall",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render_hook(view, "search_workspace_species", %{"value" => "Andricus"})

      assert html =~ matching_species.name
      refute html =~ other_species.name
    end

    test "selecting a species updates the workspace state", %{conn: conn} do
      reviewer = db_user_fixture("Select Reviewer")
      source = source_fixture(%{title: "Select Source"})
      mapped_species = species_fixture("Andricus quercuscalifornicus", "gall")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Some gall"
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html =
        view
        |> element("#workspace-species-picker")
        |> render_hook("select_workspace_species", %{"id" => mapped_species.id})

      assert html =~ mapped_species.name
    end
  end

  describe "hosts and traits" do
    test "host rows render with extracted data", %{conn: conn} do
      reviewer = db_user_fixture("Host Reviewer")
      source = source_fixture(%{title: "Host Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Some gall",
        extraction_payload: %{
          "hosts" => [
            %{"name" => "Quercus alba", "authority" => "L."},
            %{"name" => "Quercus rubra", "authority" => "Du Roi"}
          ],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Quercus alba"
      assert html =~ "Quercus rubra"
      assert html =~ "Host Review"
    end

    test "trait review section renders extracted traits with evidence", %{conn: conn} do
      reviewer = db_user_fixture("Trait Reviewer")
      source = source_fixture(%{title: "Trait Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Some gall",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "shape" => %{"original" => "globular", "suggested" => ["globular"]},
            "color" => %{"original" => "brown", "suggested" => ["brown"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Trait Review"
      assert html =~ "Shape"
      assert html =~ "Color"
      assert html =~ "globular"
      assert html =~ "brown"
    end

    test "host decision radio renders with correct options", %{conn: conn} do
      reviewer = db_user_fixture("Host Decision Reviewer")
      source = source_fixture(%{title: "Host Decision Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Some gall",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus alba", "authority" => "L."}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Map to existing host"
      assert html =~ "Leave unresolved"
    end
  end

  describe "description and save actions" do
    test "description textarea renders with current prose", %{conn: conn} do
      reviewer = db_user_fixture("Description Reviewer")
      source = source_fixture(%{title: "Description Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Some gall",
        description_prose: "A rounded woolly gall found on oak twigs."
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Description Review"
      assert html =~ "A rounded woolly gall found on oak twigs."
    end

    test "saving a mapped species review persists species_id and review_payload", %{conn: conn} do
      reviewer = db_user_fixture("Save Reviewer")
      source = source_fixture(%{title: "Save Source"})
      mapped_species = species_fixture("Andricus savestus", "gall")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Some gall",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-species-picker")
      |> render_hook("select_workspace_species", %{"id" => mapped_species.id})

      view
      |> form("#gall-review-workspace-form", %{
        "workspace" => %{
          "species_review" => %{
            "decision" => "mapped",
            "notes" => "Matched against the existing gall species."
          },
          "description_prose" => "Rounded woolly gall on oak twigs."
        }
      })
      |> render_submit()

      updated = Ingestions.get_source_ingestion_species!(species_entry.id)

      assert updated.status == "mapped"
      assert updated.species_id == mapped_species.id
      assert updated.reviewed_by_id == reviewer.id
      assert updated.review_payload.species_review.decision == "mapped"
      assert updated.review_payload.species_review.species_id == mapped_species.id

      assert updated.review_payload.species_review.notes ==
               "Matched against the existing gall species."
    end

    test "editing description prose persists the text and edited review flag", %{conn: conn} do
      reviewer = db_user_fixture("Edit Reviewer")
      source = source_fixture(%{title: "Edit Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Some gall",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> form("#gall-review-workspace-form", %{
        "workspace" => %{
          "species_review" => %{"decision" => "skip"},
          "description_prose" => "Edited description from the review workspace."
        }
      })
      |> render_submit()

      updated = Ingestions.get_source_ingestion_species!(species_entry.id)

      assert updated.description_prose == "Edited description from the review workspace."
      assert updated.review_payload.description_review.edited == true
    end

    test "master list updates after save", %{conn: conn} do
      reviewer = db_user_fixture("Master Update Reviewer")
      source = source_fixture(%{title: "Master Update Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Gall A",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      source_ingestion_species_fixture(ingestion, 1, %{
        extracted_name: "Gall B",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> form("#gall-review-workspace-form", %{
        "workspace" => %{
          "species_review" => %{"decision" => "skip"},
          "description_prose" => "Description."
        }
      })
      |> render_submit()

      html = render(view)

      assert html =~ "1 reviewed"
      assert html =~ "1 remaining"
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
        auth0_id: "auth0|workspace-#{System.unique_integer([:positive])}",
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

  defp species_fixture(name, taxoncode) do
    unique_name = "#{name} #{System.unique_integer([:positive])}"

    {:ok, species} =
      Repo.insert(%Species{
        name: unique_name,
        taxoncode: taxoncode,
        datacomplete: false
      })

    species
  end
end
