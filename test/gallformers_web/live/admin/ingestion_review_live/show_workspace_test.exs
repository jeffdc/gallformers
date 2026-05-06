defmodule GallformersWeb.Admin.IngestionReviewLive.ShowWorkspaceTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gallformers.IngestionPipelineFixtures

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Species.Species

  describe "gall review workspace" do
    test "renders the workspace modal from persisted source_ingestion_species data", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Workspace Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Woolly twig gall",
          extracted_authority: "Osten Sacken",
          description_prose: "Rounded woolly gall on oak twigs.",
          extraction_payload: %{
            "hosts" => [%{"name" => "Quercus alba", "authority" => "L."}],
            "traits" => %{
              "shape" => %{"original" => "globular", "suggested" => ["globular", "oval"]}
            },
            "description_evidence" => [%{"text" => "Rounded woolly gall on oak twigs."}]
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#review-species-entry-#{species_entry.id}")
      |> render_click()

      html = render(view)

      assert has_element?(view, "#gall-review-workspace-modal")
      assert html =~ "Woolly twig gall"
      assert html =~ "Quercus alba"
      assert html =~ "Shape"
      assert html =~ "globular"
      assert html =~ "Rounded woolly gall on oak twigs."
    end

    test "saving a mapped species review persists species_id and review_payload", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Mapped Source"})
      mapped_species = species_fixture("Andricus workspaceus", "gall")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry = source_ingestion_species_fixture(ingestion, 0)

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#review-species-entry-#{species_entry.id}")
      |> render_click()

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

    test "saving host mappings persists host review decisions into review_payload", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Host Review Source"})
      mapped_species = species_fixture("Andricus hostreviewus", "gall")
      mapped_host = species_fixture("Quercus rubra", "plant")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extraction_payload: %{
            "hosts" => [%{"name" => "Quercus rubra", "authority" => "L."}],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#review-species-entry-#{species_entry.id}")
      |> render_click()

      view
      |> element("#workspace-species-picker")
      |> render_hook("select_workspace_species", %{"id" => mapped_species.id})

      view
      |> form("#gall-review-workspace-form", %{
        "workspace" => %{
          "species_review" => %{"decision" => "mapped"},
          "host_reviews" => %{
            "0" => %{"decision" => "mapped"}
          },
          "description_prose" => "Rounded woolly gall on oak twigs."
        }
      })
      |> render_change()

      view
      |> element("#host-review-picker-0")
      |> render_hook("select_workspace_host:0", %{"id" => mapped_host.id})

      view
      |> form("#gall-review-workspace-form", %{
        "workspace" => %{
          "species_review" => %{"decision" => "mapped"},
          "host_reviews" => %{
            "0" => %{"decision" => "mapped"}
          },
          "description_prose" => "Rounded woolly gall on oak twigs."
        }
      })
      |> render_submit()

      updated = Ingestions.get_source_ingestion_species!(species_entry.id)
      [host_review] = updated.review_payload.host_reviews

      assert host_review.extracted_name == "Quercus rubra"
      assert host_review.extracted_authority == "L."
      assert host_review.decision == "mapped"
      assert host_review.species_id == mapped_host.id
    end

    test "trait evidence renders and saving preserves selected values and raw evidence", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Trait Review Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{
              "shape" => %{"original" => "globular", "suggested" => ["globular"]}
            },
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#review-species-entry-#{species_entry.id}")
      |> render_click()

      html = render(view)
      assert html =~ "Evidence: globular"

      render_click(view, "toggle_trait_value", %{"value" => "shape::oval"})

      view
      |> form("#gall-review-workspace-form", %{
        "workspace" => %{
          "species_review" => %{"decision" => "skip"},
          "description_prose" => "Rounded woolly gall on oak twigs."
        }
      })
      |> render_submit()

      updated = Ingestions.get_source_ingestion_species!(species_entry.id)

      assert updated.status == "skipped"
      trait_review = Enum.find(updated.review_payload.trait_reviews, &(&1.name == "shape"))
      assert trait_review.selected_values == ["globular", "oval"]
      assert trait_review.raw_evidence == ["globular"]
    end

    test "editing description prose persists the text and edited review flag", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Description Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry = source_ingestion_species_fixture(ingestion, 0)

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#review-species-entry-#{species_entry.id}")
      |> render_click()

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

    test "status rules only allow complete when all review requirements are satisfied", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Completion Source"})
      mapped_species = species_fixture("Andricus completus", "gall")
      mapped_host = species_fixture("Quercus alba", "plant")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      species_entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extraction_payload: %{
            "hosts" => [%{"name" => "Quercus alba"}],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#review-species-entry-#{species_entry.id}")
      |> render_click()

      view
      |> element("#workspace-species-picker")
      |> render_hook("select_workspace_species", %{"id" => mapped_species.id})

      html =
        render_submit(view, "save_gall_review_workspace", %{
          "workspace" => %{
            "action" => "complete",
            "species_review" => %{"decision" => "mapped"},
            "host_reviews" => %{"0" => %{"decision" => "unresolved"}},
            "description_prose" => "Rounded woolly gall on oak twigs."
          }
        })

      assert html =~ "cannot mark complete while host reviews are unresolved"

      view
      |> form("#gall-review-workspace-form", %{
        "workspace" => %{
          "species_review" => %{"decision" => "mapped"},
          "host_reviews" => %{"0" => %{"decision" => "mapped"}},
          "description_prose" => "Rounded woolly gall on oak twigs."
        }
      })
      |> render_change()

      view
      |> element("#host-review-picker-0")
      |> render_hook("select_workspace_host:0", %{"id" => mapped_host.id})

      render_submit(view, "save_gall_review_workspace", %{
        "workspace" => %{
          "action" => "complete",
          "species_review" => %{"decision" => "mapped"},
          "host_reviews" => %{"0" => %{"decision" => "mapped"}},
          "description_prose" => "Rounded woolly gall on oak twigs."
        }
      })

      updated = Ingestions.get_source_ingestion_species!(species_entry.id)

      assert updated.status == "complete"
      assert updated.review_payload.species_review.decision == "mapped"
      [host_review] = updated.review_payload.host_reviews
      assert host_review.decision == "mapped"
    end

    test "workspace remains inaccessible when the ingestion is not associated with a source", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Workspace Reviewer")
      ingestion = review_ready_ingestion_fixture(%{uploaded_by_id: reviewer.id, source_id: nil})
      species_entry = source_ingestion_species_fixture(ingestion, 0)

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      refute has_element?(view, "#review-species-entry-#{species_entry.id}")

      html = render_click(view, "open_gall_review_workspace", %{"id" => species_entry.id})

      assert html =~ "Associate a source before opening gall review."
      refute has_element?(view, "#gall-review-workspace-modal")
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
        auth0_id: "auth0|show-workspace-#{System.unique_integer([:positive])}",
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
