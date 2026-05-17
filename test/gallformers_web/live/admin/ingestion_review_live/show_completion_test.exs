defmodule GallformersWeb.Admin.IngestionReviewLive.ShowCompletionTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Ingestions
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
    def get_object(_bucket, path) do
      Agent.get(state_pid(), fn %{objects: objects} ->
        case Map.fetch(objects, path) do
          {:ok, %{body: body}} -> {:ok, %{body: body}}
          :error -> {:error, :not_found}
        end
      end)
    end

    @impl true
    def list_objects(_bucket, prefix, _continuation_token) do
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
    def delete_objects(_bucket, keys) do
      Agent.get_and_update(state_pid(), fn state ->
        objects = Map.drop(state.objects, keys)
        {{:ok, %{}}, %{state | objects: objects}}
      end)
    end

    @impl true
    def copy_object(_dest_bucket, _dest_path, _src_bucket, _src_path), do: {:ok, %{}}

    defp state_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.ShowCompletionTest, [])
      |> Keyword.fetch!(:state_pid)
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.ShowCompletionTest, [])
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

  describe "completion flow" do
    # NOTE: The end-to-end completion test (saving last gall completes ingestion)
    # moved to workspace_test.exs — workspace interactions now live on a separate route.

    test "failed ingestions can be cleared from the detail page", %{conn: conn} do
      reviewer = db_user_fixture("Failed Cleanup Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          title: "Failed Detail Submission",
          uploaded_by_id: reviewer.id,
          status: "failed",
          processing_stage: "failed",
          error_stage: "upload"
        })

      artifact_path = "source-ingestions/#{ingestion.id}/input/source.pdf"
      put_storage_object(artifact_path, "%PDF-1.4 failed detail\n")

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#clear-source-ingestion")
      |> render_click()

      assert_redirect(view, "/admin/ingestion-review")
      assert Ingestions.get_source_ingestion(ingestion.id) == nil
      assert storage_objects() == %{}
    end

    test "abandoned processing ingestions can be cleared from the detail page", %{conn: conn} do
      reviewer = db_user_fixture("Abandoned Cleanup Reviewer")

      ingestion =
        source_ingestion_fixture(%{
          input_type: "pdf",
          title: "Abandoned Detail Submission",
          uploaded_by_id: reviewer.id,
          status: "processing",
          processing_stage: "metadata"
        })

      artifact_path = "source-ingestions/#{ingestion.id}/input/source.pdf"
      put_storage_object(artifact_path, "%PDF-1.4 abandoned detail\n")

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      assert html =~ "Clear Abandoned Ingestion"

      view
      |> element("#clear-source-ingestion")
      |> render_click()

      assert_redirect(view, "/admin/ingestion-review")
      assert Ingestions.get_source_ingestion(ingestion.id) == nil
      assert storage_objects() == %{}
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
        auth0_id: "auth0|show-completion-#{System.unique_integer([:positive])}",
        display_name: display_name
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

    {:ok, ingestion} = Ingestions.create_source_ingestion(merged_attrs)
    ingestion
  end

  defp put_storage_object(path, body) do
    Agent.update(state_pid(), fn state ->
      %{state | objects: Map.put(state.objects, path, %{body: body})}
    end)
  end

  defp storage_objects do
    Agent.get(state_pid(), & &1.objects)
  end

  defp state_pid do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.fetch!(:state_pid)
  end

  defp restore_env(module, nil), do: Application.delete_env(:gallformers, module)
  defp restore_env(module, value), do: Application.put_env(:gallformers, module, value)
end
