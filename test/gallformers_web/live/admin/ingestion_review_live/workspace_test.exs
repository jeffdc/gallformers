defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Species.Species

  describe "workspace shell — mount and sidebar" do
    test "mounts and renders flat sidebar with species entries in position order", %{conn: conn} do
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
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Andricus quercuscalifornicus"
      assert html =~ "Disholcaspis eldoradensis"
      assert html =~ "Species in source"
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
      assert html =~ "workspace-detail"
    end

    test "clicking sidebar entry switches selected species", %{conn: conn} do
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
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html =
        view
        |> element("#workspace-nav-#{entry_b.id}")
        |> render_click()

      assert html =~ "border-gf-maroon"
    end

    test "returns error for invalid ingestion ID", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      conn = superadmin_conn(conn, reviewer)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/admin/ingestion-review/999999/review")
      end
    end
  end

  describe "workspace shell — top bar" do
    test "top bar shows source title, breadcrumb, and progress", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Top Bar Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id,
          title: "Top Bar Source",
          authors: ["Smith", "Jones"],
          publication_year: "2025"
        })

      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall A"})
      source_ingestion_species_fixture(ingestion, 1, %{extracted_name: "Gall B"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Ingestions"
      assert html =~ "Top Bar Source"
      assert html =~ "Species review"
      assert html =~ "0/2"
    end

    test "progress counter reflects completed/skipped counts", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Progress Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Gall A",
        status: "complete"
      })

      source_ingestion_species_fixture(ingestion, 1, %{
        extracted_name: "Gall B",
        status: "skipped"
      })

      source_ingestion_species_fixture(ingestion, 2, %{extracted_name: "Gall C"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "2/3"
    end
  end

  describe "workspace shell — drawer toggle" do
    test "drawer toggle button is present and initially not active", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Drawer Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall A"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Source text"
      assert html =~ "bg-gray-100"
      refute html =~ "bg-gf-maroon text-white"
    end

    test "clicking drawer toggle button activates it", %{conn: conn} do
      reviewer = db_user_fixture("Workspace Reviewer")
      source = source_fixture(%{title: "Drawer Toggle Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall A"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render_click(view, "toggle_drawer")

      assert html =~ "bg-gf-maroon"
    end
  end

  describe "source text drawer" do
    test "drawer panel appears when toggled open", %{conn: conn} do
      reviewer = db_user_fixture("Drawer Panel Reviewer")
      source = source_fixture(%{title: "Drawer Panel Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall A"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render_click(view, "toggle_drawer")

      assert html =~ "Extracted source text"
      assert html =~ "workspace-drawer"
    end

    test "drawer is hidden when not toggled", %{conn: conn} do
      reviewer = db_user_fixture("Drawer Hidden Reviewer")
      source = source_fixture(%{title: "Drawer Hidden Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall A"})

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      refute html =~ "translate-x-0"
    end
  end

  describe "workspace shell — section placeholders" do
    test "sections render extracted data even when identity is unresolved", %{conn: conn} do
      reviewer = db_user_fixture("Section Reviewer")
      source = source_fixture(%{title: "Unresolved Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "New gall species",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus alba"}],
          "traits" => %{
            "color" => %{"original" => "brown", "suggested" => ["brown"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Identity"
      assert html =~ "Hosts"
      assert html =~ "Quercus alba"
      refute html =~ "Locked"
    end

    test "description section renders evidence_prose chunks as picker cards", %{conn: conn} do
      # In the new shape, evidence_prose paragraphs become chunk-picker cards
      # inside the description section. At the default :high disclosure level,
      # only chunks marked relevance=high or is_cited=true show.
      reviewer = db_user_fixture("Evidence Prose Reviewer")
      source = source_fixture(%{title: "Evidence Prose Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Druon evidens (agamic)",
        evidence_prose: [
          %{
            "span_id" => "S_0078",
            "page" => 3,
            "char_start" => 0,
            "char_end" => 28,
            "text" => "First paragraph about hosts.",
            "is_mention" => true,
            "is_cited" => false,
            "cited_by_fields" => [],
            "relevance" => "high"
          },
          %{
            "span_id" => "S_0079",
            "page" => 3,
            "char_start" => 30,
            "char_end" => 64,
            "text" => "Second paragraph about morphology.",
            "is_mention" => false,
            "is_cited" => false,
            "cited_by_fields" => [],
            "relevance" => "high"
          },
          %{
            "span_id" => "S_0081",
            "page" => 4,
            "char_start" => 70,
            "char_end" => 104,
            "text" => "Third paragraph about distribution.",
            "is_mention" => false,
            "is_cited" => false,
            "cited_by_fields" => [],
            "relevance" => "high"
          }
        ]
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Each high-relevance chunk is rendered as a card with its text.
      assert html =~ "First paragraph about hosts."
      assert html =~ "Second paragraph about morphology."
      assert html =~ "Third paragraph about distribution."

      # span_id attached as a data attribute on each chunk card.
      assert html =~ ~s(data-span-id="S_0078")
      assert html =~ ~s(data-span-id="S_0081")

      # page rendered on the chunk card.
      assert html =~ "p. 3"
      assert html =~ "p. 4"
    end
  end

  describe "identity section" do
    test "auto-maps identity on exact name match to existing gall", %{conn: conn} do
      reviewer = db_user_fixture("Identity Auto-Map Reviewer")
      source = source_fixture(%{title: "Auto-Map Source"})

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

      assert html =~ "Mapped"
      assert html =~ "Andricus quercuscalifornicus"
      refute html =~ "Locked"
    end

    test "treat as new resolves identity to new", %{conn: conn} do
      reviewer = db_user_fixture("Identity New Reviewer")
      source = source_fixture(%{title: "New Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # No suggested match for "Novelus gallicus", so search state shows directly
      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)
      assert html =~ "Treated as new"
      refute html =~ "Locked"
    end

    test "resolved state shows correct pill and change button", %{conn: conn} do
      reviewer = db_user_fixture("Identity Resolved Reviewer")
      source = source_fixture(%{title: "Resolved Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus"
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Mapped"
      assert html =~ "Change..."
    end

    test "change resets identity to unresolved", %{conn: conn} do
      reviewer = db_user_fixture("Identity Change Reviewer")
      source = source_fixture(%{title: "Change Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus"
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("button[phx-click=change_identity]")
      |> render_click()

      html = render(view)
      assert html =~ "Search gall species"
      refute html =~ "Mapped"
    end

    test "+alias pill shown when mapped name differs from extracted name", %{conn: conn} do
      reviewer = db_user_fixture("Identity Alias Reviewer")
      source = source_fixture(%{title: "Alias Source"})

      gall_species = species_fixture("Andricus quercuscalifornicus", "gall")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Different gall name",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Simulate identity resolution to "existing" with a species whose name differs
      send(
        view.pid,
        {:identity_resolved, :existing,
         %{id: gall_species.id, name: gall_species.name, taxoncode: "gall"}}
      )

      html = render(view)

      assert html =~ "+alias"
      assert html =~ "Different gall name"
    end
  end

  describe "hosts section" do
    test "renders extracted hosts even when identity is unresolved", %{conn: conn} do
      reviewer = db_user_fixture("Hosts Unresolved Reviewer")
      source = source_fixture(%{title: "Hosts Unresolved Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus alba"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Hosts"
      assert html =~ "From source"
      assert html =~ "Quercus alba"
      refute html =~ "Locked"
    end

    test "shows host list when identity resolved to existing", %{conn: conn} do
      reviewer = db_user_fixture("Hosts Unlock Reviewer")
      source = source_fixture(%{title: "Hosts Unlock Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus alba"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render(view)

      assert html =~ "From source"
      assert html =~ "Quercus alba"
      refute html =~ "Locked · resolve identity first"
    end

    test "existing mode shows currently linked hosts", %{conn: conn} do
      reviewer = db_user_fixture("Hosts Existing Reviewer")
      source = source_fixture(%{title: "Hosts Existing Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      # Use seed species which has hosts (Thymus alpinus, Mentha arvensis)
      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus alba"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render(view)

      assert html =~ "Currently linked"
      assert html =~ "Thymus alpinus"
      assert html =~ "Mentha arvensis"
    end

    test "new mode shows only from source group", %{conn: conn} do
      reviewer = db_user_fixture("Hosts New Reviewer")
      source = source_fixture(%{title: "Hosts New Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus alba"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # No suggested match, search state shows — treat as new
      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      assert html =~ "From source"
      assert html =~ "Quercus alba"
      refute html =~ "Currently linked"
    end

    test "accept/decline toggle updates host decision", %{conn: conn} do
      reviewer = db_user_fixture("Hosts Toggle Reviewer")
      source = source_fixture(%{title: "Hosts Toggle Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus alba"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Treat as new to unlock hosts
      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      render(view)

      # Click decline on host 0
      view
      |> element("button[phx-click=host_decline][phx-value-index=\"0\"]")
      |> render_click()

      html = render(view)
      assert html =~ "bg-red-600"
    end

    test "header shows accepted count", %{conn: conn} do
      reviewer = db_user_fixture("Hosts Count Reviewer")
      source = source_fixture(%{title: "Hosts Count Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [
            %{"name" => "Quercus alba"},
            %{"name" => "Quercus rubra"}
          ],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Treat as new to unlock hosts
      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # Auto-matched hosts count as accepted (decision "mapped")
      # The count should show in the header
      assert html =~ "of 2"
    end

    test "auto-matches abbreviated genus host names like 'Q. robur'", %{conn: conn} do
      reviewer = db_user_fixture("Abbrev Auto-Match Reviewer")
      source = source_fixture(%{title: "Abbrev Auto-Match Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      # Seeded host id 9 is "Quercus robur". Source extracts the abbreviated form.
      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Q. robur"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # The host row should show the resolved mapping arrow to "Quercus robur".
      assert html =~ "→ Quercus robur",
             "expected 'Q. robur' to auto-match to Quercus robur"
    end

    test "unmatched host renders the standard typeahead component", %{conn: conn} do
      reviewer = db_user_fixture("Host Typeahead Reviewer")
      source = source_fixture(%{title: "Host Typeahead Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      # "Nonexistus speciesus" is not in test seeds, so it stays unmatched and
      # the search picker is rendered.
      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Nonexistus speciesus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      assert has_element?(view, ~s(#host-picker-0[phx-hook="Typeahead"]))
      assert has_element?(view, ~s(#host-picker-0[data-search-event="host_search_0"]))
    end

    test "clicking Create in the typeahead opens the create-host modal", %{conn: conn} do
      reviewer = db_user_fixture("Host Create Modal Reviewer")
      source = source_fixture(%{title: "Host Create Modal Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Nonexistus speciesus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      send(view.pid, {:request_create_host, 0, "Quercus newgenus"})
      _ = render(view)

      assert has_element?(view, "#create-host-modal")
      assert render(view) =~ "Quercus newgenus"
    end

    test "create-host modal auto-searches WCVP and shows matches", %{conn: conn} do
      reviewer = db_user_fixture("Host WCVP Reviewer")
      source = source_fixture(%{title: "Host WCVP Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Wcvptestus alpinus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      send(view.pid, {:request_create_host, 0, "Wcvptestus alpinus"})
      render_async(view)
      html = render(view)

      # WCVP stub entry "700" has family "Testaceae"
      assert html =~ "Testaceae"
    end

    test "pre-populates the typeahead query with extracted_name for unmatched host", %{conn: conn} do
      reviewer = db_user_fixture("Host Prepop Reviewer")
      source = source_fixture(%{title: "Host Prepop Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      # "Quercus" matches the seeded Quercus species via search prefix but is not
      # an exact match for any, so the host does not auto-match.
      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Quercus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # The typeahead input is pre-populated with the extracted name
      assert html =~ ~s(data-query="Quercus")
      # And the prefix-matched seeded species are visible without typing
      assert html =~ "Quercus alba"
      assert html =~ "Quercus rubra"
    end

    test "does not pre-populate when extracted_name is empty", %{conn: conn} do
      reviewer = db_user_fixture("Host Empty Name Reviewer")
      source = source_fixture(%{title: "Host Empty Name Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => ""}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # No data-query value for the empty host (only the empty default)
      assert html =~ ~s(data-query="")
    end

    test "renders a Create new host button on unmatched host rows", %{conn: conn} do
      reviewer = db_user_fixture("Host Quick Create Reviewer")
      source = source_fixture(%{title: "Host Quick Create Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Nonexistus speciesus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      # Clicking the per-row quick-create button opens the modal with the
      # extracted name pre-filled.
      view
      |> element(~s(button#host-quick-create-0))
      |> render_click()

      _ = render(view)

      assert has_element?(view, "#create-host-modal")
      assert render(view) =~ "Nonexistus speciesus"
    end

    test "clicking Create from this match on a WCVP row persists the host directly",
         %{conn: conn} do
      reviewer = db_user_fixture("Host WCVP One-Click Reviewer")
      source = source_fixture(%{title: "Host WCVP One-Click Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Wcvptestus alpinus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      send(view.pid, {:request_create_host, 0, "Wcvptestus alpinus"})
      render_async(view)

      # Single click on the WCVP result row both fetches details and creates.
      view
      |> element(
        ~s(#workspace-create-host button[phx-click="create_from_wcvp"][phx-value-id="700"])
      )
      |> render_click()

      render_async(view)

      # Modal closed
      refute has_element?(view, "#create-host-modal")

      # Host persisted
      assert %Species{id: host_id} =
               Repo.get_by(Species, name: "Wcvptestus alpinus", taxoncode: "plant")

      # WCVP IDs persisted via host_traits
      traits = Gallformers.Plants.get_host_traits(host_id)
      assert traits.wcvp_id == "700"

      # Host review now mapped to the new species
      html = render(view)
      assert html =~ "→ Wcvptestus alpinus"
    end

    test "Create without WCVP fallback button still creates a host", %{conn: conn} do
      reviewer = db_user_fixture("Host Fallback Create Reviewer")
      source = source_fixture(%{title: "Host Fallback Create Source"})

      # Pre-create a plant taxonomy so the new host can resolve a family
      # without needing WCVP data.
      family =
        Repo.insert!(%Gallformers.Taxonomy.Taxonomy{
          name: "NoWcvpFamily",
          description: "Plant",
          type: "family",
          is_placeholder: false
        })

      _genus =
        Repo.insert!(%Gallformers.Taxonomy.Taxonomy{
          name: "Newhostus",
          description: "test genus",
          type: "genus",
          parent_id: family.id,
          is_placeholder: false
        })

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Newhostus rarus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      send(view.pid, {:request_create_host, 0, "Newhostus rarus"})
      render_async(view)

      html = render(view)
      assert html =~ "Create without WCVP"

      view
      |> element(~s(#workspace-create-host button[phx-click="create_host"]))
      |> render_click()

      render_async(view)

      refute has_element?(view, "#create-host-modal")

      assert %Species{} =
               Repo.get_by(Species, name: "Newhostus rarus", taxoncode: "plant")
    end

    test "Cancel in the create-host modal closes it without creating", %{conn: conn} do
      reviewer = db_user_fixture("Host Cancel Reviewer")
      source = source_fixture(%{title: "Host Cancel Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [%{"name" => "Wcvptestus alpinus"}],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      send(view.pid, {:request_create_host, 0, "Wcvptestus alpinus"})
      render_async(view)

      view
      |> element(~s(#workspace-create-host button[phx-click="cancel"]))
      |> render_click()

      refute has_element?(view, "#create-host-modal")
      refute Repo.get_by(Species, name: "Wcvptestus alpinus", taxoncode: "plant")
    end
  end

  describe "aliases section" do
    test "renders extracted aliases even when identity is unresolved", %{conn: conn} do
      reviewer = db_user_fixture("Aliases Unresolved Reviewer")
      source = source_fixture(%{title: "Aliases Unresolved Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "aliases" => ["Oak apple gall"],
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Aliases"
      assert html =~ "Oak apple gall"
      refute html =~ "Locked"
    end

    test "shows extracted aliases as checkboxes when identity is resolved", %{conn: conn} do
      reviewer = db_user_fixture("Aliases Checkbox Reviewer")
      source = source_fixture(%{title: "Aliases Checkbox Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "aliases" => ["Oak apple gall", "Common oak gall"],
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      assert html =~ "Oak apple gall"
      assert html =~ "Common oak gall"
      assert html =~ "From source"
    end

    test "existing mode shows currently on gall aliases", %{conn: conn} do
      reviewer = db_user_fixture("Aliases Existing Reviewer")
      source = source_fixture(%{title: "Aliases Existing Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      # Species 100 has alias "Oak Apple Gall Wasp" in seeds
      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "aliases" => ["New alias name"],
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render(view)

      assert html =~ "Currently on gall"
      assert html =~ "Oak Apple Gall Wasp"
      assert html =~ "New alias name"
    end

    test "toggle alias checkbox updates state", %{conn: conn} do
      reviewer = db_user_fixture("Aliases Toggle Reviewer")
      source = source_fixture(%{title: "Aliases Toggle Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "aliases" => ["Oak apple gall"],
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      render(view)

      # Toggle off the alias (initially accepted=true)
      view
      |> element("button[phx-click=toggle_alias][phx-value-index=\"0\"]")
      |> render_click()

      html = render(view)
      assert html =~ "0 of 1"
    end
  end

  describe "traits section" do
    test "renders extracted traits even when identity is unresolved", %{conn: conn} do
      reviewer = db_user_fixture("Traits Unresolved Reviewer")
      source = source_fixture(%{title: "Traits Unresolved Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "shape" => %{"original" => "globular", "suggested" => ["globular"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Traits"
      assert html =~ "globular"
      refute html =~ "Locked"
    end

    test "renders as table with Trait, Extracted, Result columns in new mode", %{conn: conn} do
      reviewer = db_user_fixture("Traits Table Reviewer")
      source = source_fixture(%{title: "Traits Table Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
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
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # Table structure with column headers
      assert html =~ "Trait"
      assert html =~ "Extracted"
      assert html =~ "Result"
      # No Current column in new mode (no existing gall)
      refute html =~ ~r/<th[^>]*>Current</
      # Human-readable trait names as row labels
      assert html =~ "Shape"
      assert html =~ "Color"
      refute html =~ "Locked · resolve identity first"
    end

    test "renders Current column in existing mode with gall trait values", %{conn: conn} do
      reviewer = db_user_fixture("Traits Current Reviewer")
      source = source_fixture(%{title: "Traits Current Source"})

      # Insert filter field records so the existing gall has trait values
      color_red = insert_filter_field(:color, "red")
      _color_green = insert_filter_field(:color, "green")
      insert_gall_filter_value(100, :color, color_red.id)

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "color" => %{"original" => "brown and yellow", "suggested" => ["green"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Accept match to resolve as existing
      html = render(view)

      # Current column present in existing mode
      assert html =~ ~r/<th[^>]*>.*Current.*<\/th>/s
      # Current value from existing gall shown as pill
      assert html =~ "red"
    end

    test "extracted values shown as toggleable pills", %{conn: conn} do
      reviewer = db_user_fixture("Traits Extracted Reviewer")
      source = source_fixture(%{title: "Traits Extracted Source"})

      insert_filter_field(:shape, "globular")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "shape" => %{"original" => "round", "suggested" => ["globular"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # Extracted value rendered as selected pill
      assert html =~ "globular"
      assert html =~ "gf-pill-selected"
    end

    test "result column shows additions in styled text", %{conn: conn} do
      reviewer = db_user_fixture("Traits Result Reviewer")
      source = source_fixture(%{title: "Traits Result Source"})

      insert_filter_field(:shape, "globular")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "shape" => %{"original" => "round", "suggested" => ["globular"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # Result shows addition styling (new mode = everything is an addition)
      assert html =~ ~r/trait-added.*globular|globular.*trait-added/s
    end

    test "toggling off extracted value removes it from result", %{conn: conn} do
      reviewer = db_user_fixture("Traits Toggle Reviewer")
      source = source_fixture(%{title: "Traits Toggle Source"})

      insert_filter_field(:color, "brown")
      insert_filter_field(:color, "yellow")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "color" => %{"original" => "brown and yellow", "suggested" => ["brown", "yellow"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      render(view)

      # Toggle off "brown" in extracted
      view
      |> element(
        "button[phx-click=toggle_extracted][phx-value-trait=color][phx-value-value=brown]"
      )
      |> render_click()

      html = render(view)

      # "brown" should be deselected in extracted
      assert html =~
               ~r/phx-value-value="brown"[^>]*gf-pill-unselected|gf-pill-unselected[^>]*phx-value-value="brown"/s

      # "yellow" should still be in result
      assert html =~ "yellow"
    end

    test "existing mode shows removals in result with strikethrough", %{conn: conn} do
      reviewer = db_user_fixture("Traits Removal Reviewer")
      source = source_fixture(%{title: "Traits Removal Source"})

      color_red = insert_filter_field(:color, "red")
      _color_blue = insert_filter_field(:color, "blue")
      insert_gall_filter_value(100, :color, color_red.id)

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "color" => %{"original" => "blue", "suggested" => ["blue"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Toggle off "red" from current
      view
      |> element("button[phx-click=toggle_current][phx-value-trait=color][phx-value-value=red]")
      |> render_click()

      html = render(view)

      # Result should show "red" with strikethrough styling
      assert html =~ ~r/trait-removed.*red|red.*trait-removed/s
    end

    test "vocab picker adds value from controlled vocabulary", %{conn: conn} do
      reviewer = db_user_fixture("Traits Vocab Reviewer")
      source = source_fixture(%{title: "Traits Vocab Source"})

      insert_filter_field(:shape, "globular")
      insert_filter_field(:shape, "conical")

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{
            "shape" => %{"original" => "round", "suggested" => ["globular"]}
          },
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      render(view)

      # Open vocab picker then add "conical"
      view
      |> element("button[phx-click=toggle_vocab][phx-value-trait=shape]")
      |> render_click()

      view
      |> element("button[phx-click=add_from_vocab][phx-value-value=conical]")
      |> render_click()

      html = render(view)

      # "conical" should now appear in result
      assert html =~ "conical"
    end
  end

  describe "description section" do
    test "renders evidence_prose chunks even when identity is unresolved", %{conn: conn} do
      reviewer = db_user_fixture("Desc Unresolved Reviewer")
      source = source_fixture(%{title: "Desc Unresolved Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        evidence_prose: [
          %{
            "span_id" => "S_0001",
            "page" => 1,
            "char_start" => 0,
            "char_end" => 28,
            "text" => "A round woody gall on twigs.",
            "is_mention" => true,
            "is_cited" => false,
            "cited_by_fields" => [],
            "relevance" => "high"
          }
        ]
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "Description"
      # New chunk-picker renders the evidence_prose paragraph as a card and
      # also as part of the auto-selected draft preview.
      assert html =~ "A round woody gall on twigs"
      refute html =~ "Locked"
    end

    test "shows draft preview with selected high-relevance chunks in new mode", %{conn: conn} do
      reviewer = db_user_fixture("Desc New Reviewer")
      source = source_fixture(%{title: "Desc New Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        evidence_prose: [
          %{
            "span_id" => "S_0001",
            "page" => 1,
            "char_start" => 0,
            "char_end" => 20,
            "text" => "A round woolly gall.",
            "is_mention" => true,
            "is_cited" => false,
            "cited_by_fields" => [],
            "relevance" => "high"
          }
        ]
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      html = render(view)

      # The selected high-relevance chunk's text appears in the draft preview
      # and the chunk card.
      assert html =~ "A round woolly gall."
      # In "new" mode (no existing_gall.description) the mode selector is
      # hidden.
      refute html =~ "Keep current"
    end

    test "existing mode shows segmented control", %{conn: conn} do
      reviewer = db_user_fixture("Desc Existing Reviewer")
      source = source_fixture(%{title: "Desc Existing Source"})

      # Create a species_source with a description for species 100
      {:ok, _} =
        Sources.create_species_source(%{
          species_id: 100,
          source_id: source.id,
          description: "An existing gall description."
        })

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        description_prose: "Extracted description text.",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render(view)

      assert html =~ "Keep current"
      assert html =~ "Append"
      assert html =~ "Replace"
    end
  end

  describe "description review persistence round-trip" do
    test "selection, mode, draft, dirty round-trip through save and reload",
         %{conn: conn} do
      reviewer = db_user_fixture("Desc Roundtrip Reviewer")
      source = source_fixture(%{title: "Desc Roundtrip Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Novelus gallicus",
          evidence_prose: roundtrip_prose_fixture(),
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Treat as new so identity resolves and we can save.
      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      # Emit description_updated with specific selection, append mode, draft text.
      send(
        view.pid,
        {:description_updated,
         %{
           selection: ["S_0021", "S_0024"],
           draft: "Curator wrote this.",
           mode: :append,
           dirty: false
         }}
      )

      render(view)

      render_click(view, "save_draft")

      # Reload from the database — the workspace view should carry the new keys.
      workspace_view = Ingestions.source_ingestion_species_review_workspace!(entry.id)

      assert workspace_view.description_review.selected_span_ids == ["S_0021", "S_0024"]
      assert workspace_view.description_review.mode == :append
      assert workspace_view.description_review.draft_dirty == false
      assert workspace_view.description_review.draft == "Curator wrote this."
      assert workspace_view.description_review.edited == true

      # The component on a fresh mount should reflect the persisted state.
      {:ok, _view2, html2} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # On the second mount, the description draft should hydrate to "Curator wrote this.".
      assert html2 =~ "Curator wrote this."
    end

    test "completion gate blocks completing a fresh species (edited == false)",
         %{conn: _conn} do
      reviewer = db_user_fixture("Desc Gate Block Reviewer")
      source = source_fixture(%{title: "Desc Gate Block Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus quercuscalifornicus",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      # Try to commit "complete" without ever engaging the description.
      attrs = %{
        action: "complete",
        species_review: %{decision: "mapped", species_id: 100, accepted_aliases: []},
        host_reviews: %{},
        trait_reviews: %{},
        description_prose: entry.description_prose
      }

      assert {:error, changeset} =
               Ingestions.update_source_ingestion_species_review(entry, attrs, reviewer.id)

      assert {"cannot mark complete until the description is reviewed", _} =
               changeset.errors[:status]
    end

    test "completion gate allows commit once curator has engaged the description picker",
         %{conn: _conn} do
      reviewer = db_user_fixture("Desc Gate Pass Reviewer")
      source = source_fixture(%{title: "Desc Gate Pass Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus quercuscalifornicus",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      attrs = %{
        action: "complete",
        species_review: %{decision: "mapped", species_id: 100, accepted_aliases: []},
        host_reviews: %{},
        trait_reviews: %{},
        description_prose: "Curator-supplied final description.",
        description_review: %{
          selected_span_ids: ["S_0001"],
          mode: "replace",
          draft_dirty: false,
          draft: "Curator-supplied final description."
        }
      }

      assert {:ok, updated} =
               Ingestions.update_source_ingestion_species_review(entry, attrs, reviewer.id)

      assert updated.status == "complete"
      assert updated.review_payload.description_review.edited == true
      assert updated.review_payload.description_review.selected_span_ids == ["S_0001"]
      assert updated.review_payload.description_review.mode == "replace"

      assert updated.review_payload.description_review.draft ==
               "Curator-supplied final description."
    end

    test "mode :replace without existing produces description_prose == draft", %{conn: conn} do
      reviewer = db_user_fixture("Desc Replace No-Existing Reviewer")
      source = source_fixture(%{title: "Desc Replace No-Existing Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Novelus gallicus",
          evidence_prose: roundtrip_prose_fixture(),
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      send(
        view.pid,
        {:description_updated,
         %{
           selection: ["S_0021"],
           draft: "Fresh description.",
           mode: :replace,
           dirty: false
         }}
      )

      render(view)
      render_click(view, "save_draft")

      reloaded = Ingestions.get_source_ingestion_species!(entry.id)
      assert reloaded.description_prose == "Fresh description."
    end

    test "mode :replace with existing description still produces description_prose == draft",
         %{conn: conn} do
      reviewer = db_user_fixture("Desc Replace Existing Reviewer")
      source = source_fixture(%{title: "Desc Replace Existing Source"})

      {:ok, _} =
        Sources.create_species_source(%{
          species_id: 100,
          source_id: source.id,
          description: "Old description."
        })

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus quercuscalifornicus",
          evidence_prose: roundtrip_prose_fixture(),
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      send(
        view.pid,
        {:description_updated,
         %{
           selection: ["S_0021"],
           draft: "New description.",
           mode: :replace,
           dirty: false
         }}
      )

      render(view)
      render_click(view, "save_draft")

      reloaded = Ingestions.get_source_ingestion_species!(entry.id)
      assert reloaded.description_prose == "New description."
    end

    test "mode :append with existing concatenates existing and draft", %{conn: conn} do
      reviewer = db_user_fixture("Desc Append Reviewer")
      source = source_fixture(%{title: "Desc Append Source"})

      {:ok, _} =
        Sources.create_species_source(%{
          species_id: 100,
          source_id: source.id,
          description: "Old text."
        })

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus quercuscalifornicus",
          evidence_prose: roundtrip_prose_fixture(),
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      send(
        view.pid,
        {:description_updated,
         %{
           selection: ["S_0021"],
           draft: "the gall is...",
           mode: :append,
           dirty: false
         }}
      )

      render(view)
      render_click(view, "save_draft")

      reloaded = Ingestions.get_source_ingestion_species!(entry.id)
      assert reloaded.description_prose == "Old text.\n\nthe gall is..."
    end

    test "mode :keep with existing preserves existing description", %{conn: conn} do
      reviewer = db_user_fixture("Desc Keep Reviewer")
      source = source_fixture(%{title: "Desc Keep Source"})

      {:ok, _} =
        Sources.create_species_source(%{
          species_id: 100,
          source_id: source.id,
          description: "Old text."
        })

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Andricus quercuscalifornicus",
          evidence_prose: roundtrip_prose_fixture(),
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      send(
        view.pid,
        {:description_updated,
         %{
           selection: ["S_0021"],
           draft: "ignored draft",
           mode: :keep,
           dirty: false
         }}
      )

      render(view)
      render_click(view, "save_draft")

      reloaded = Ingestions.get_source_ingestion_species!(entry.id)
      assert reloaded.description_prose == "Old text."
    end

    test "mode :keep without existing falls back to draft (compose_description default branch)",
         %{conn: conn} do
      reviewer = db_user_fixture("Desc Keep No-Existing Reviewer")
      source = source_fixture(%{title: "Desc Keep No-Existing Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Novelus gallicus",
          evidence_prose: roundtrip_prose_fixture(),
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      send(
        view.pid,
        {:description_updated,
         %{
           selection: ["S_0021"],
           draft: "Curator draft.",
           mode: :keep,
           dirty: false
         }}
      )

      render(view)
      render_click(view, "save_draft")

      reloaded = Ingestions.get_source_ingestion_species!(entry.id)
      # No existing description, so :keep falls back to draft.
      assert reloaded.description_prose == "Curator draft."
    end
  end

  describe "save, commit, skip flow" do
    test "save draft persists review and shows saved timestamp", %{conn: conn} do
      reviewer = db_user_fixture("Save Draft Reviewer")
      source = source_fixture(%{title: "Save Draft Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      _entry =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Novelus gallicus",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Treat as new to resolve identity
      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      render(view)

      html = render_click(view, "save_draft")

      assert html =~ "Draft saved"
    end

    test "skip sets status to skipped and auto-advances", %{conn: conn} do
      reviewer = db_user_fixture("Skip Reviewer")
      source = source_fixture(%{title: "Skip Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      _entry_a =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Skip Gall A",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      _entry_b =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Skip Gall B",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render_click(view, "skip_species")

      # Should auto-advance to next entry
      assert html =~ "Skip Gall B"
    end

    test "commit button disabled when identity unresolved", %{conn: conn} do
      reviewer = db_user_fixture("Commit Disabled Reviewer")
      source = source_fixture(%{title: "Commit Disabled Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert html =~ "disabled"
      assert html =~ "Commit"
    end

    test "save draft is disabled when no changes have been made", %{conn: conn} do
      reviewer = db_user_fixture("Dirty Initial Reviewer")
      source = source_fixture(%{title: "Dirty Initial Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert has_element?(view, ~s(button[phx-click="save_draft"][disabled]))
    end

    test "save draft becomes enabled after the user mutates the workspace", %{conn: conn} do
      reviewer = db_user_fixture("Dirty After Change Reviewer")
      source = source_fixture(%{title: "Dirty After Change Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      refute has_element?(view, ~s(button[phx-click="save_draft"][disabled]))
    end

    test "commit gall is disabled when resolved but unchanged after save", %{conn: conn} do
      reviewer = db_user_fixture("Commit After Save Reviewer")
      source = source_fixture(%{title: "Commit After Save Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Novelus gallicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      render_click(view, "save_draft")

      # After saving, dirty resets — commit button should be disabled until next mutation
      assert has_element?(view, ~s(button[phx-click="commit_species"][disabled]))
    end

    test "skip is disabled once the species has been saved", %{conn: conn} do
      reviewer = db_user_fixture("Skip Disabled Reviewer")
      source = source_fixture(%{title: "Skip Disabled Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      # Use an extracted name that matches a seeded gall so it auto-maps.
      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "Andricus quercuscalifornicus",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Initially status is "pending" — skip is enabled.
      refute has_element?(view, ~s(button[phx-click="skip_species"][disabled]))

      # Workspace auto-mapped to existing gall on load; save → status becomes "mapped".
      render_click(view, "save_draft")

      # Re-load the workspace; the species's current status should be "mapped".
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      assert has_element?(view, ~s(button[phx-click="skip_species"][disabled]))
    end
  end

  describe "same-name companion entries are independent" do
    test "loading the workspace does not merge data from a same-name companion entry", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Companion Load Reviewer")
      source = source_fixture(%{title: "Companion Load Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      # Two entries with the SAME extracted_name but different generation suffixes
      # and different host/trait/alias data. Loading entry_a must show only A's data.
      entry_a =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Druon evidens (agamic)",
          extraction_payload: %{
            "hosts" => [%{"name" => "Quercus alba"}],
            "traits" => %{
              "shape" => %{"original" => "globular", "suggested" => ["globular"]}
            },
            "aliases" => ["Agamic-only alias"],
            "description_evidence" => []
          }
        })

      _entry_b =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Druon evidens (sexgen)",
          extraction_payload: %{
            "hosts" => [%{"name" => "Quercus rubra"}],
            "traits" => %{
              "color" => %{"original" => "red", "suggested" => ["red"]}
            },
            "aliases" => ["Sexgen-only alias"],
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # The first entry is auto-selected. Verify only A's data is loaded.
      html = render(view)

      assert html =~ "Quercus alba"
      refute html =~ "Quercus rubra"

      assert html =~ "Agamic-only alias"
      refute html =~ "Sexgen-only alias"

      # Switch to entry A explicitly to be sure we're looking at A (auto-selected anyway).
      html =
        view
        |> element("#workspace-nav-#{entry_a.id}")
        |> render_click()

      assert html =~ "Quercus alba"
      refute html =~ "Quercus rubra"
      assert html =~ "Agamic-only alias"
      refute html =~ "Sexgen-only alias"
    end

    test "saving the current entry leaves the same-name companion's status unchanged", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Companion Save Reviewer")
      source = source_fixture(%{title: "Companion Save Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      _entry_a =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Druon evidens (agamic)",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      entry_b =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Druon evidens (sexgen)",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Treat current (entry A) as new, then save the draft.
      view
      |> element("#workspace-section-identity button[phx-click=treat_as_new]")
      |> render_click()

      render_click(view, "save_draft")

      # Entry B's status must still be "pending" — saving A must not fan out to B.
      reloaded_b = Ingestions.get_source_ingestion_species!(entry_b.id)
      assert reloaded_b.status == "pending"
    end

    test "skipping the current entry leaves the same-name companion's status unchanged", %{
      conn: conn
    } do
      reviewer = db_user_fixture("Companion Skip Reviewer")
      source = source_fixture(%{title: "Companion Skip Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      _entry_a =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "Druon evidens (agamic)",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      entry_b =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "Druon evidens (sexgen)",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      render_click(view, "skip_species")

      # Entry B's status must still be "pending" — skipping A must not fan out to B.
      reloaded_b = Ingestions.get_source_ingestion_species!(entry_b.id)
      assert reloaded_b.status == "pending"
    end
  end

  describe "keyboard navigation" do
    test "J key navigates to next species", %{conn: conn} do
      reviewer = db_user_fixture("KeyNav J Reviewer")
      source = source_fixture(%{title: "KeyNav J Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      _entry_a =
        source_ingestion_species_fixture(ingestion, 0, %{
          extracted_name: "KeyNav Gall A",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      _entry_b =
        source_ingestion_species_fixture(ingestion, 1, %{
          extracted_name: "KeyNav Gall B",
          extraction_payload: %{
            "hosts" => [],
            "traits" => %{},
            "description_evidence" => []
          }
        })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      html = render_keydown(view, "keydown", %{"key" => "j"})

      assert html =~ "border-gf-maroon"
    end

    test "Escape closes the drawer", %{conn: conn} do
      reviewer = db_user_fixture("KeyNav Esc Reviewer")
      source = source_fixture(%{title: "KeyNav Esc Source"})

      ingestion =
        review_ready_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          source_id: source.id
        })

      source_ingestion_species_fixture(ingestion, 0, %{
        extracted_name: "KeyNav Gall A",
        extraction_payload: %{
          "hosts" => [],
          "traits" => %{},
          "description_evidence" => []
        }
      })

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}/review")

      # Open the drawer first
      render_click(view, "toggle_drawer")

      # Press Escape to close
      html = render_keydown(view, "keydown", %{"key" => "Escape"})

      refute html =~ "translate-x-0"
    end
  end

  # --- Test helpers ---

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

  @filter_field_schemas %{
    color: {Gallformers.FilterFields.Color, :color},
    shape: {Gallformers.FilterFields.Shape, :shape},
    texture: {Gallformers.FilterFields.Texture, :texture}
  }

  @gall_join_tables %{
    color: {"gall_color", "color_id"},
    shape: {"gall_shape", "shape_id"},
    texture: {"gall_texture", "texture_id"}
  }

  defp insert_filter_field(type, value) do
    {schema, field} = Map.fetch!(@filter_field_schemas, type)
    {:ok, record} = Repo.insert(struct(schema, [{field, value}]))
    record
  end

  defp insert_gall_filter_value(species_id, type, filter_field_id) do
    {table, fk} = Map.fetch!(@gall_join_tables, type)

    Repo.query!(
      "INSERT INTO #{table} (species_id, #{fk}) VALUES ($1, $2)",
      [species_id, filter_field_id]
    )
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

  defp roundtrip_prose_fixture do
    [
      %{
        "span_id" => "S_0021",
        "page" => 1,
        "char_start" => 0,
        "char_end" => 20,
        "text" => "Round woolly gall.",
        "is_mention" => true,
        "is_cited" => false,
        "cited_by_fields" => [],
        "relevance" => "high"
      },
      %{
        "span_id" => "S_0024",
        "page" => 2,
        "char_start" => 50,
        "char_end" => 80,
        "text" => "Found on oak twigs.",
        "is_mention" => false,
        "is_cited" => true,
        "cited_by_fields" => ["hosts[0].scientific_name"],
        "relevance" => "low"
      }
    ]
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
