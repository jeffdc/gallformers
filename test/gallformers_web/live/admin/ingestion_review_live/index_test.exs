defmodule GallformersWeb.Admin.IngestionReviewLive.IndexTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
  alias Gallformers.Sources
  alias Gallformers.Storage.SourceArtifacts
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

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

  setup do
    previous_storage_config = Application.get_env(:gallformers, SourceArtifacts)
    previous_test_config = Application.get_env(:gallformers, __MODULE__)

    {:ok, state_pid} =
      Agent.start_link(fn ->
        %{
          objects: %{}
        }
      end)

    Application.put_env(:gallformers, __MODULE__, state_pid: state_pid, test_pid: self())
    Application.put_env(:gallformers, SourceArtifacts, backend: StorageBackendStub)

    on_exit(fn ->
      if Process.alive?(state_pid) do
        Agent.stop(state_pid)
      end

      restore_env(SourceArtifacts, previous_storage_config)
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
      assert html =~ "1 of 2 galls remaining"
      assert html =~ current_db_user.display_name

      # Status conveys the gall-progress count for needs_review rows; the redundant
      # "Species" column has been removed.
      refute html =~ "1 of 2 reviewed"
      refute has_element?(view, "th", "Species")

      assert has_element?(
               view,
               "a[href='/admin/ingestion-review/#{row.id}']",
               row.display_title
             )
    end

    test "rows ready for species review link straight to the workspace", %{conn: conn} do
      current_db_user = db_user_fixture("Workspace Link Reviewer")
      row = review_queue_row_fixture(current_db_user)
      conn = superadmin_conn(conn, current_db_user)

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      assert has_element?(
               view,
               "a[href='/admin/ingestion-review/#{row.id}/review']"
             )
    end

    test "rows that are not yet reviewable do not show the workspace link", %{conn: conn} do
      current_db_user = db_user_fixture("No Workspace Link Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      processing =
        source_ingestion_fixture(%{
          uploaded_by_id: current_db_user.id,
          title: "Processing Submission",
          status: "processing",
          processing_stage: "extract"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      refute has_element?(
               view,
               "a[href='/admin/ingestion-review/#{processing.id}/review']"
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

    test "table columns are sortable", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      source_ingestion_fixture(%{
        uploaded_by_id: current_db_user.id,
        title: "Alpha Submission",
        status: "processing",
        processing_stage: "extract"
      })

      source_ingestion_fixture(%{
        uploaded_by_id: current_db_user.id,
        title: "Zeta Submission",
        status: "needs_review",
        processing_stage: "review"
      })

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      html = render_click(view, "sort", %{"column" => "display_title"})

      alpha_pos = :binary.match(html, "Alpha Submission") |> elem(0)
      zeta_pos = :binary.match(html, "Zeta Submission") |> elem(0)
      assert alpha_pos < zeta_pos

      html = render_click(view, "sort", %{"column" => "display_title"})

      alpha_pos = :binary.match(html, "Alpha Submission") |> elem(0)
      zeta_pos = :binary.match(html, "Zeta Submission") |> elem(0)
      assert zeta_pos < alpha_pos
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

    test "queue shows all uploaders", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")
      other_db_user = db_user_fixture("Other Reviewer")
      conn = superadmin_conn(conn, current_db_user)

      source_ingestion_fixture(%{
        uploaded_by_id: current_db_user.id,
        title: "My Submission",
        status: "needs_review",
        processing_stage: "review"
      })

      source_ingestion_fixture(%{
        uploaded_by_id: other_db_user.id,
        title: "Other Submission",
        status: "processing",
        processing_stage: "extract"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ "My Submission"
      assert html =~ "Other Submission"
    end

    test "any row can be deleted from the queue", %{conn: conn} do
      current_db_user = db_user_fixture("Current Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          uploaded_by_id: current_db_user.id,
          title: "Deletable Upload",
          status: "needs_review",
          processing_stage: "review"
        })

      artifact_path = "source-ingestions/#{ingestion.id}/input/source.pdf"
      put_storage_object(artifact_path, "%PDF-1.4 needs-review\n")

      conn = superadmin_conn(conn, current_db_user)
      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ "Deletable Upload"

      html =
        view
        |> element("#delete-ingestion-#{ingestion.id}")
        |> render_click()

      assert html =~ "Ingestion deleted"
      refute html =~ "Deletable Upload"
      assert_received {:delete_objects, _, [^artifact_path]}
      assert Ingestions.get_source_ingestion(ingestion.id) == nil
    end
  end

  describe "bundle upload" do
    @bundle_root Path.expand("../../../../../services/source-ingestion/output", __DIR__)

    test "renders the bundle upload form", %{conn: conn} do
      current_db_user = db_user_fixture("Bundle Upload Renderer")
      conn = superadmin_conn(conn, current_db_user)

      {:ok, _view, html} = live(conn, ~p"/admin/ingestion-review")

      assert html =~ "Upload Bundle"
      assert html =~ "bundle.tar.gz"
      refute html =~ "Import bundle"
    end

    test "auto-imports a real cuesta bundle when the upload finishes", %{conn: conn} do
      current_db_user = db_user_fixture("Bundle Uploader")
      conn = superadmin_conn(conn, current_db_user)

      bundle_path = Path.join([@bundle_root, "cuesta", "bundle.tar.gz"])
      assert File.exists?(bundle_path), "cuesta bundle missing — run the Python pipeline first"

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      upload =
        file_input(view, "#bundle-upload-form", :bundle, [
          %{
            name: "bundle.tar.gz",
            content: File.read!(bundle_path),
            type: "application/gzip"
          }
        ])

      render_upload(upload, "bundle.tar.gz")

      # No "Import bundle" click — auto-import runs on upload completion.
      ingestion =
        Ingestions.list_source_ingestions()
        |> Enum.find(&(&1.uploaded_by_id == current_db_user.id))

      assert ingestion != nil, "expected a SourceIngestion to be created by the auto-import"
      assert ingestion.status == "needs_review"
      assert ingestion.processing_stage == "review"
    end

    test "reports a clean error for a non-tar upload", %{conn: conn} do
      current_db_user = db_user_fixture("Bad Bundle Uploader")
      conn = superadmin_conn(conn, current_db_user)

      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review")

      upload =
        file_input(view, "#bundle-upload-form", :bundle, [
          %{
            name: "garbage.tar.gz",
            content: "this is not a tar archive",
            type: "application/gzip"
          }
        ])

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          render_upload(upload, "garbage.tar.gz")
        end)

      assert log =~ "Bundle import failed"

      html = render(view)

      assert html =~ "Failed to extract archive" or html =~ "not valid JSON" or
               html =~ "missing"
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

  defp db_user_fixture(display_name) do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|ingestion-review-#{System.unique_integer([:positive])}",
        display_name: display_name,
        nickname: String.replace(String.downcase(display_name), " ", "-")
      })

    user
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

    Presenter.list_source_ingestion_queue_rows(
      uploaded_by_id: current_db_user.id,
      include_complete: true
    )
    |> Enum.find(&(&1.id == ingestion.id))
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

  defp restore_env(module, nil), do: Application.delete_env(:gallformers, module)
  defp restore_env(module, value), do: Application.put_env(:gallformers, module, value)
end
