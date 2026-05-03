defmodule GallformersWeb.Admin.IngestionReviewLive.ShowDuplicateReviewTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gallformers.IngestionPipelineFixtures

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.IngestionPipeline.DuplicateResolution
  alias Gallformers.Ingestions

  defmodule WorkerStub do
    def enqueue(ingestion_id) do
      send(test_pid(), {:worker_enqueue, ingestion_id})
      {:ok, %{id: ingestion_id}}
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.ShowDuplicateReviewTest, [])
      |> Keyword.fetch!(:test_pid)
    end
  end

  setup do
    previous_duplicate_resolution_config = Application.get_env(:gallformers, DuplicateResolution)
    previous_test_config = Application.get_env(:gallformers, __MODULE__)

    Application.put_env(:gallformers, __MODULE__, test_pid: self())
    Application.put_env(:gallformers, DuplicateResolution, worker_module: WorkerStub)

    on_exit(fn ->
      restore_env(DuplicateResolution, previous_duplicate_resolution_config)
      restore_env(__MODULE__, previous_test_config)
    end)

    :ok
  end

  describe "duplicate review detail page" do
    test "renders duplicate-review candidates and mapped evidence labels", %{conn: conn} do
      reviewer = db_user_fixture("Duplicate Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          title: "Incoming submission",
          uploaded_by_id: reviewer.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      candidate =
        source_ingestion_fixture(%{
          input_type: "url",
          authors: ["A. Author", "B. Writer"],
          publication_year: 1919
        })

      duplicate_candidate_fixture(ingestion, candidate, %{
        evidence: %{
          "normalized_doi" => "10.1234/example",
          "similarity" => 0.98,
          "unknown_signal" => "ignore me"
        }
      })

      conn = superadmin_conn(conn, reviewer)

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert html =~ "Incoming submission"
      assert html =~ "Untitled URL submission"
      assert html =~ "A. Author, B. Writer"
      assert html =~ "1919"
      assert html =~ "DOI match"
      assert html =~ "10.1234/example"
      assert html =~ "Text similarity"
      assert html =~ "0.98"
      refute html =~ "unknown_signal"
    end

    test "sparse evidence maps render safely", %{conn: conn} do
      reviewer = db_user_fixture("Duplicate Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      candidate = source_ingestion_fixture(%{input_type: "text"})

      duplicate_candidate_fixture(ingestion, candidate, %{
        evidence: %{"unmapped_key" => "ignored"}
      })

      conn = superadmin_conn(conn, reviewer)

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert html =~ "Untitled text submission"
      assert html =~ "No matching evidence details recorded."
      refute html =~ "unmapped_key"
    end

    test "confirm action marks the ingestion duplicate", %{conn: conn} do
      reviewer = db_user_fixture("Duplicate Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      candidate = source_ingestion_fixture(%{input_type: "url", title: "Canonical candidate"})
      duplicate_candidate = duplicate_candidate_fixture(ingestion, candidate)

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#confirm-duplicate-candidate-#{duplicate_candidate.id}")
      |> render_click()

      updated = Ingestions.get_source_ingestion!(ingestion.id)
      updated_candidate = Ingestions.get_duplicate_candidate!(duplicate_candidate.id)

      assert updated.status == "duplicate_confirmed"
      assert updated.processing_stage == "duplicate_review"
      assert updated.duplicate_of_source_ingestion_id == candidate.id
      assert updated_candidate.status == "confirmed"
      updated_id = updated.id
      assert_received {:worker_enqueue, ^updated_id}

      html = render(view)
      assert html =~ "Duplicate confirmed"
    end

    test "duplicate review actions bootstrap reviewer attribution from Auth0", %{conn: conn} do
      uploader = db_user_fixture("Original Uploader")
      auth0_user = auth0_user_fixture("Auth0 Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: uploader.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      candidate = source_ingestion_fixture(%{input_type: "url", title: "Canonical candidate"})
      duplicate_candidate = duplicate_candidate_fixture(ingestion, candidate)

      conn = superadmin_auth0_conn(conn, auth0_user)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#confirm-duplicate-candidate-#{duplicate_candidate.id}")
      |> render_click()

      reviewer = Accounts.get_user_by_auth0_id(auth0_user.id)
      updated_candidate = Ingestions.get_duplicate_candidate!(duplicate_candidate.id)

      assert reviewer.display_name == auth0_user.name
      assert updated_candidate.reviewed_by_id == reviewer.id
    end

    test "reject action updates the candidate and reloads the page state", %{conn: conn} do
      reviewer = db_user_fixture("Duplicate Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      candidate = source_ingestion_fixture(%{input_type: "url", title: "Maybe duplicate"})
      duplicate_candidate = duplicate_candidate_fixture(ingestion, candidate)

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#reject-duplicate-candidate-#{duplicate_candidate.id}")
      |> render_click()

      updated = Ingestions.get_source_ingestion!(ingestion.id)
      updated_candidate = Ingestions.get_duplicate_candidate!(duplicate_candidate.id)

      assert updated.status == "processing"
      assert updated.processing_stage == "duplicate_review"
      assert updated_candidate.status == "rejected"
      updated_id = updated.id
      assert_received {:worker_enqueue, ^updated_id}

      html = render(view)
      refute html =~ "Needs duplicate review"
      assert html =~ "Processing"
    end

    test "promote action rejects all pending candidates", %{conn: conn} do
      reviewer = db_user_fixture("Duplicate Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      first_candidate =
        duplicate_candidate_fixture(ingestion, source_ingestion_fixture(%{input_type: "url"}))

      second_candidate =
        duplicate_candidate_fixture(ingestion, source_ingestion_fixture(%{input_type: "text"}))

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#promote-ingestion-to-unique")
      |> render_click()

      updated = Ingestions.get_source_ingestion!(ingestion.id)

      assert updated.status == "processing"
      assert updated.processing_stage == "duplicate_review"

      assert Ingestions.get_duplicate_candidate!(first_candidate.id).status == "rejected"
      assert Ingestions.get_duplicate_candidate!(second_candidate.id).status == "rejected"
      updated_id = updated.id
      assert_received {:worker_enqueue, ^updated_id}

      html = render(view)
      refute html =~ "Needs duplicate review"
    end

    test "source controls are locked while duplicate review is open", %{conn: conn} do
      reviewer = db_user_fixture("Duplicate Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      duplicate_candidate_fixture(ingestion, source_ingestion_fixture(%{input_type: "url"}))

      conn = superadmin_conn(conn, reviewer)

      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert html =~ "Resolve duplicate review to enable source mapping."
      assert has_element?(view, "#source-review-locked")
      refute has_element?(view, "a[href='/admin/sources/new']")
    end

    test "gall review entry is locked while duplicate review is open", %{conn: conn} do
      reviewer = db_user_fixture("Duplicate Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: reviewer.id,
          status: "needs_duplicate_review",
          processing_stage: "duplicate_review"
        })

      duplicate_candidate_fixture(ingestion, source_ingestion_fixture(%{input_type: "url"}))
      source_ingestion_species_fixture(ingestion, 0, %{extracted_name: "Gall One"})
      source_ingestion_species_fixture(ingestion, 1, %{extracted_name: "Gall Two"})

      conn = superadmin_conn(conn, reviewer)

      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert html =~ "Duplicate review must be resolved before gall review."
      assert html =~ "Gall One"
      assert html =~ "Gall Two"
      assert has_element?(view, "#species-review-locked")
      refute has_element?(view, "#gall-review-workspace")
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

  defp superadmin_auth0_conn(conn, %Auth0User{} = auth0_user) do
    conn
    |> init_test_session(%{})
    |> put_session(:current_user, auth0_user)
    |> put_session(:db_display_name, Auth0User.display_name(auth0_user))
  end

  defp db_user_fixture(display_name) do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|show-duplicate-review-#{System.unique_integer([:positive])}",
        display_name: display_name
      })

    user
  end

  defp auth0_user_fixture(display_name) do
    %Auth0User{
      id: "auth0|show-duplicate-review-auth0-only-#{System.unique_integer([:positive])}",
      email: "auth0-only@test.com",
      name: display_name,
      nickname: String.replace(String.downcase(display_name), " ", "-"),
      picture: nil,
      roles: ["admin", "superadmin"]
    }
  end

  defp restore_env(module, nil), do: Application.delete_env(:gallformers, module)
  defp restore_env(module, value), do: Application.put_env(:gallformers, module, value)
end
