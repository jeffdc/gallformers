defmodule GallformersWeb.Admin.IngestionReviewLive.ShowCompletionTest do
  use GallformersWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Gallformers.IngestionPipelineFixtures

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.IngestionPipeline.Worker
  alias Gallformers.Ingestions
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Species.Species
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

  defmodule WorkerStub do
    def enqueue(ingestion_id) do
      send(test_pid(), {:worker_enqueue, ingestion_id})
      {:ok, %{id: ingestion_id}}
    end

    defp test_pid do
      :gallformers
      |> Application.get_env(GallformersWeb.Admin.IngestionReviewLive.ShowCompletionTest, [])
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
          objects: %{}
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

  describe "completion flow" do
    test "saving the last unresolved gall review completes the ingestion and removes it from the active queue",
         %{conn: conn} do
      reviewer = db_user_fixture("Completion Reviewer")
      mapped_species = species_fixture("Andricus completionis", "gall")
      source = source_fixture(%{title: "Completion Source"})

      assert {:ok, ingestion} =
               Ingestions.submit_source_ingestion(%{
                 input_type: "url",
                 uploaded_by_id: reviewer.id,
                 url: "https://example.com/completion"
               })

      assert {:ok, ingestion} =
               Ingestions.transition_source_ingestion_status(ingestion, :needs_review)

      first_entry = source_ingestion_species_fixture(ingestion, 0)
      second_entry = source_ingestion_species_fixture(ingestion, 1)

      conn = superadmin_conn(conn, reviewer)
      {:ok, view, _html} = live(conn, ~p"/admin/ingestion-review/#{ingestion.id}")

      view
      |> element("#source-picker")
      |> render_hook("select_source", %{"id" => source.id})

      view
      |> element("#associate-source")
      |> render_click()

      view
      |> element("#review-species-entry-#{first_entry.id}")
      |> render_click()

      view
      |> element("#workspace-species-picker")
      |> render_hook("select_workspace_species", %{"id" => mapped_species.id})

      html =
        view
        |> form("#gall-review-workspace-form", %{
          "workspace" => %{
            "species_review" => %{"decision" => "mapped"},
            "description_prose" => "Rounded woolly gall on oak twigs."
          }
        })
        |> render_submit()

      assert html =~ "Gall review saved"
      assert html =~ "1 of 2 galls remaining"
      assert Ingestions.get_source_ingestion!(ingestion.id).status == "needs_review"

      view
      |> element("#review-species-entry-#{second_entry.id}")
      |> render_click()

      html =
        view
        |> form("#gall-review-workspace-form", %{
          "workspace" => %{
            "species_review" => %{"decision" => "skip"},
            "description_prose" => "Rounded woolly gall on oak twigs."
          }
        })
        |> render_submit()

      completed_ingestion = Ingestions.get_source_ingestion!(ingestion.id)

      assert completed_ingestion.status == "complete"
      assert completed_ingestion.processing_stage == "complete"
      assert html =~ "Source ingestion review complete"
      assert html =~ "Complete"

      {:ok, queue_view, queue_html} = live(conn, ~p"/admin/ingestion-review")

      refute queue_html =~ "Untitled URL submission"

      queue_html = render_click(queue_view, "toggle_include_complete")

      assert queue_html =~ "Untitled URL submission"
      assert queue_html =~ "Complete"
    end

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

      job = Repo.insert!(Worker.new(%{ingestion_id: ingestion.id}))
      mark_job_discarded(job.id)

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

  defp mark_job_discarded(job_id) do
    from(job in "oban_jobs", where: field(job, :id) == ^job_id)
    |> Repo.update_all(
      set: [
        state: "discarded",
        attempt: 3,
        max_attempts: 3,
        discarded_at: DateTime.utc_now()
      ]
    )
  end

  defp restore_env(module, nil), do: Application.delete_env(:gallformers, module)
  defp restore_env(module, value), do: Application.put_env(:gallformers, module, value)
end
