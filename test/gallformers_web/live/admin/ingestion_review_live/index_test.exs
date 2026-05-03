defmodule GallformersWeb.Admin.IngestionReviewLive.IndexTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
  alias Gallformers.Sources
  alias Gallformers.Storage.SourceArtifacts

  defmodule StorageBackendStub do
    @behaviour Gallformers.Storage.SourceArtifacts.Backend

    @impl true
    def upload(bucket, path, content, content_type) do
      send(test_pid(), {:upload, bucket, path, content, content_type})

      Agent.get_and_update(state_pid(), fn state ->
        objects = Map.put(state.objects, path, %{body: content})
        {{:ok, %{}}, %{state | objects: objects}}
      end)
    end

    @impl true
    def get_object(bucket, path) do
      send(test_pid(), {:get_object, bucket, path})

      Agent.get(state_pid(), fn %{objects: objects} ->
        case Map.fetch(objects, path) do
          {:ok, %{body: body}} -> {:ok, %{body: body}}
          :error -> {:error, :not_found}
        end
      end)
    end

    @impl true
    def list_objects(bucket, prefix, continuation_token) do
      send(test_pid(), {:list_objects, bucket, prefix, continuation_token})

      Agent.get(state_pid(), fn %{objects: objects} ->
        keys =
          objects
          |> Map.keys()
          |> Enum.filter(&String.starts_with?(&1, prefix))
          |> Enum.sort()

        {:ok, %{keys: keys, next_continuation_token: nil, is_truncated: false}}
      end)
    end

    @impl true
    def delete_objects(bucket, keys) do
      send(test_pid(), {:delete_objects, bucket, keys})

      Agent.get_and_update(state_pid(), fn state ->
        objects = Map.drop(state.objects, keys)
        {{:ok, %{}}, %{state | objects: objects}}
      end)
    end

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp state_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.IndexTest, [])
      |> Keyword.fetch!(:state_pid)
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.IndexTest, [])
      |> Keyword.fetch!(:test_pid)
    end
  end

  defmodule WorkerStub do
    def enqueue(ingestion_id) do
      send(test_pid(), {:worker_enqueue, ingestion_id})

      Agent.get(state_pid(), fn %{worker_result: worker_result} ->
        worker_result || {:ok, %{id: ingestion_id}}
      end)
    end

    defp state_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.IndexTest, [])
      |> Keyword.fetch!(:state_pid)
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.IndexTest, [])
      |> Keyword.fetch!(:test_pid)
    end
  end

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)
    previous_ingestions_config = Application.get_env(:gallformers, Ingestions)
    previous_test_config = Application.get_env(:gallformers, __MODULE__)

    {:ok, state_pid} =
      Agent.start_link(fn ->
        %{
          objects: %{},
          worker_result: nil
        }
      end)

    Application.put_env(:gallformers, __MODULE__, state_pid: state_pid, test_pid: self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)
    Application.put_env(:gallformers, Ingestions, worker_module: WorkerStub)

    on_exit(fn ->
      if Process.alive?(state_pid) do
        Agent.stop(state_pid)
      end

      restore_env(SourceArtifacts, previous_storage_config)
      restore_env(Ingestions, previous_ingestions_config)
      restore_env(__MODULE__, previous_test_config)
    end)

    :ok
  end

  describe "queue rendering and filters" do
    test "renders persisted rows and links them to the detail path", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      row = review_queue_row_fixture(current_db_user)
      conn = superadmin_conn(conn, current_db_user)

      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ "Source Ingestion Review"
      assert html =~ row.display_title
      assert html =~ "1 of 2 reviewed"
      assert html =~ "1 of 2 galls remaining"
      assert html =~ current_db_user.display_name

      assert has_element?(
               view,
               "a[href='/admin/ingestion-review/#{row.id}']",
               row.display_title
             )
    end

    test "default filter hides complete items", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      needs_review =
        source_ingestion_fixture(%{
          uploaded_by_id: current_db_user.id,
          title: "Needs Review",
          status: "needs_review",
          processing_stage: "review"
        })

      source_ingestion_fixture(%{
        uploaded_by_id: current_db_user.id,
        title: "Complete Submission",
        status: "complete",
        processing_stage: "complete"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ needs_review.title
      refute html =~ "Complete Submission"
    end

    test "include complete filter reveals completed items", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      source_ingestion_fixture(%{
        uploaded_by_id: current_db_user.id,
        title: "Complete Submission",
        status: "complete",
        processing_stage: "complete"
      })

      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review")

      refute html =~ "Complete Submission"

      html = render_click(view, "toggle_include_complete")

      assert html =~ "Complete Submission"
      assert html =~ "Complete"
    end

    test "default active queue hides duplicate-confirmed rows", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      source_ingestion_fixture(%{
        uploaded_by_id: current_db_user.id,
        title: "Confirmed Duplicate",
        status: "duplicate_confirmed",
        processing_stage: "duplicate_review"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review")

      refute html =~ "Confirmed Duplicate"
    end

    test "uploader filter switches between me and all", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      other_db_user = db_user_fixture("Other Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      mine =
        source_ingestion_fixture(%{
          uploaded_by_id: current_db_user.id,
          title: "My Submission",
          status: "needs_review",
          processing_stage: "review"
        })

      other =
        source_ingestion_fixture(%{
          uploaded_by_id: other_db_user.id,
          title: "Other Submission",
          status: "processing",
          processing_stage: "extract"
        })

      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ mine.title
      refute html =~ other.title

      html =
        view
        |> form("#queue-filter-form", %{"uploaded_by_scope" => "all"})
        |> render_change()

      assert html =~ mine.title
      assert html =~ other.title
    end

    test "duplicate-review rows render a distinct badge", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      source_ingestion_fixture(%{
        uploaded_by_id: current_db_user.id,
        title: "Duplicate Candidate",
        status: "needs_duplicate_review",
        processing_stage: "duplicate_review"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ "Duplicate Candidate"
      assert html =~ "Duplicate review"
      assert html =~ "Needs duplicate review"
    end

    test "failed rows can be cleared from the queue", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: current_db_user.id,
          title: "Failed Upload",
          status: "failed",
          processing_stage: "failed",
          error_stage: "upload"
        })

      artifact_path = "source-ingestions/#{ingestion.id}/input/source.pdf"
      put_storage_object(artifact_path, "%PDF-1.4 failed\n")

      conn = superadmin_conn(conn, current_db_user)
      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ "Failed Upload"

      html =
        view
        |> element("#clear-failed-ingestion-#{ingestion.id}")
        |> render_click()

      assert html =~ "Failed ingestion cleared"
      refute html =~ "Failed Upload"
      assert_received {:delete_objects, _, [^artifact_path]}
      assert Ingestions.get_source_ingestion(ingestion.id) == nil
    end
  end

  describe "submissions" do
    test "selecting a pdf shows the chosen filename in the form", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      upload =
        file_input(view, "#pdf-submission-form", :pdf, [
          %{
            name: "chosen.pdf",
            content: "%PDF-1.4 fixture\n",
            type: "application/pdf"
          }
        ])

      html = render_upload(upload, "chosen.pdf")

      assert html =~ "chosen.pdf"
      assert html =~ "100%"
    end

    test "submits with Auth0 attribution when no database profile exists yet", %{conn: conn} do
      auth0_user = auth0_user_fixture("Auth0 Only Submitter")
      conn = superadmin_auth0_conn(conn, auth0_user)

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      view
      |> form("#url-submission-form", %{
        "url_submission" => %{"url" => "https://example.com/auth0-only"}
      })
      |> render_submit()

      db_user = Accounts.get_user_by_auth0_id(auth0_user.id)
      ingestion = latest_ingestion_for(db_user.id)
      ingestion_id = ingestion.id

      assert db_user.display_name == auth0_user.name
      assert ingestion.uploaded_by_id == db_user.id
      assert_redirect(view, "/admin/ingestion-review/#{ingestion_id}")
    end

    test "submits a pdf and redirects to the persisted detail path", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      upload =
        file_input(view, "#pdf-submission-form", :pdf, [
          %{
            name: "test.pdf",
            content: "%PDF-1.4 fixture\n",
            type: "application/pdf"
          }
        ])

      render_upload(upload, "test.pdf")
      render_submit(element(view, "#pdf-submission-form"))

      ingestion = latest_ingestion_for(current_db_user.id)
      ingestion_id = ingestion.id
      input_path = "source-ingestions/#{ingestion.id}/input/source.pdf"

      assert_received {:upload, _, ^input_path, "%PDF-1.4 fixture\n", "application/pdf"}
      assert_received {:worker_enqueue, ^ingestion_id}
      assert_redirect(view, "/admin/ingestion-review/#{ingestion_id}")
    end

    test "submits a url and redirects to the persisted detail path", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      view
      |> form("#url-submission-form", %{
        "url_submission" => %{"url" => "https://example.com/galls"}
      })
      |> render_submit()

      ingestion = latest_ingestion_for(current_db_user.id)
      ingestion_id = ingestion.id
      input_path = "source-ingestions/#{ingestion.id}/input/source.url"

      assert_received {:upload, _, ^input_path, "https://example.com/galls", "text/plain"}
      assert_received {:worker_enqueue, ^ingestion_id}
      assert_redirect(view, "/admin/ingestion-review/#{ingestion_id}")
    end

    test "submits text and redirects to the persisted detail path", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      view
      |> form("#text-submission-form", %{
        "text_submission" => %{"text" => "Rounded woolly gall on oak twigs."}
      })
      |> render_submit()

      ingestion = latest_ingestion_for(current_db_user.id)
      ingestion_id = ingestion.id
      input_path = "source-ingestions/#{ingestion.id}/input/source.txt"

      assert_received {:upload, _, ^input_path, "Rounded woolly gall on oak twigs.", "text/plain"}
      assert_received {:worker_enqueue, ^ingestion_id}
      assert_redirect(view, "/admin/ingestion-review/#{ingestion_id}")
    end

    test "submission failure stays on the page and shows an error", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)
      set_worker_result({:error, worker_error_changeset()})

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      html =
        view
        |> form("#url-submission-form", %{
          "url_submission" => %{"url" => "https://example.com/fails"}
        })
        |> render_submit()

      assert html =~ "Source Ingestion Review"
      assert html =~ "Failed to enqueue ingestion"
    end
  end

  defp superadmin_conn(conn, %Accounts.User{} = db_user) do
    user = %Auth0User{
      id: db_user.auth0_id,
      email: "superadmin@test.com",
      name: db_user.display_name,
      nickname: db_user.nickname,
      picture: nil,
      roles: ["admin", "superadmin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
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
        auth0_id: "auth0|ingestion-review-#{System.unique_integer([:positive])}",
        display_name: display_name,
        nickname: String.replace(String.downcase(display_name), " ", "-")
      })

    user
  end

  defp auth0_user_fixture(display_name) do
    %Auth0User{
      id: "auth0|ingestion-review-auth0-only-#{System.unique_integer([:positive])}",
      email: "auth0-only@test.com",
      name: display_name,
      nickname: String.replace(String.downcase(display_name), " ", "-"),
      picture: nil,
      roles: ["admin", "superadmin"]
    }
  end

  defp source_ingestion_fixture(attrs) do
    merged_attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:input_type, "pdf")
      |> Map.put_new(:status, "processing")
      |> Map.put_new(:processing_stage, "submitted")

    {:ok, source_ingestion} = Ingestions.create_source_ingestion(merged_attrs)
    source_ingestion
  end

  defp review_queue_row_fixture(current_db_user) do
    source = source_fixture()

    ingestion =
      source_ingestion_fixture(%{
        input_type: "url",
        uploaded_by_id: current_db_user.id,
        status: "needs_review",
        processing_stage: "review",
        source_id: source.id
      })

    {:ok, _pending_entry} =
      Ingestions.create_source_ingestion_species(%{
        source_ingestion_id: ingestion.id,
        position: 0,
        extracted_name: "Pending Gall"
      })

    {:ok, _mapped_entry} =
      Ingestions.create_source_ingestion_species(%{
        source_ingestion_id: ingestion.id,
        position: 1,
        extracted_name: "Mapped Gall",
        status: "mapped"
      })

    Ingestions.list_source_ingestion_queue_rows(
      uploaded_by_id: current_db_user.id,
      include_complete: true
    )
    |> Enum.find(&(&1.id == ingestion.id))
  end

  defp latest_ingestion_for(uploaded_by_id) do
    Ingestions.list_source_ingestion_queue_rows(
      uploaded_by_id: uploaded_by_id,
      include_complete: true
    )
    |> hd()
    |> then(&Ingestions.get_source_ingestion!(&1.id))
  end

  defp source_fixture do
    {:ok, source} =
      Sources.create_source(%{
        title: "Queued Source #{System.unique_integer([:positive])}",
        author: "Author",
        pubyear: "2026",
        link: "https://example.com/source",
        citation: "Author. 2026. Queued Source.",
        license: "CC-BY",
        licenselink: "https://creativecommons.org/licenses/by/4.0/"
      })

    source
  end

  defp set_worker_result(result) do
    Agent.update(state_pid(), fn state -> %{state | worker_result: result} end)
  end

  defp put_storage_object(path, body) do
    Agent.update(state_pid(), fn state ->
      %{state | objects: Map.put(state.objects, path, %{body: body})}
    end)
  end

  defp state_pid do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.fetch!(:state_pid)
  end

  defp worker_error_changeset do
    {%{}, %{ingestion_id: :integer}}
    |> Ecto.Changeset.cast(%{ingestion_id: nil}, [:ingestion_id])
    |> Ecto.Changeset.validate_required([:ingestion_id])
  end

  defp restore_env(module, nil), do: Application.delete_env(:gallformers, module)
  defp restore_env(module, value), do: Application.put_env(:gallformers, module, value)
end
