defmodule GallformersWeb.Admin.IngestionReviewLive.Index do
  use GallformersWeb, :live_view

  require Logger

  alias Gallformers.Accounts
  alias Gallformers.Ingestions
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  @bundle_upload_name :bundle
  @max_bundle_bytes 200 * 1024 * 1024

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    current_user_db_id = Accounts.db_user_id(session)

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:current_user_db_id, current_user_db_id)
      |> assign(:page_title, "Source Ingestion Review")
      |> assign(:sort_by, :inserted_at)
      |> assign(:sort_dir, :desc)
      |> assign(:bundle_error, nil)
      |> allow_upload(@bundle_upload_name,
        accept: ~w(.gz),
        max_entries: 1,
        max_file_size: @max_bundle_bytes,
        chunk_size: 1_048_576,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> load_queue_rows()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @sortable_columns ~w(display_title status inserted_at uploaded_by_name)a

  @impl true
  def handle_event("sort", %{"column" => column}, socket) do
    column_atom = String.to_existing_atom(column)

    if column_atom in @sortable_columns do
      {:noreply, assign(socket, toggle_sort(socket.assigns, column_atom))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_bundle", _params, socket) do
    {:noreply, assign(socket, :bundle_error, nil)}
  end

  @impl true
  def handle_event("cancel_bundle_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, @bundle_upload_name, ref)}
  end

  @impl true
  def handle_event("submit_bundle", _params, socket) do
    uploaded_by_id = socket.assigns.current_user_db_id

    if uploaded_by_id == nil do
      {:noreply,
       assign(
         socket,
         :bundle_error,
         "You need a database-backed profile to upload bundles."
       )}
    else
      results =
        consume_uploaded_entries(socket, @bundle_upload_name, fn %{path: path}, _entry ->
          {:ok, import_archive(path, uploaded_by_id)}
        end)

      case results do
        [{:ok, ingestion}] ->
          {:noreply,
           socket
           |> put_flash(:info, "Bundle imported (##{ingestion.id}).")
           |> push_navigate(to: ~p"/admin/ingestion-review/#{ingestion.id}")}

        [{:error, reason}] ->
          Logger.warning("Bundle import failed: #{inspect(reason)}")
          {:noreply, assign(socket, :bundle_error, format_import_error(reason))}

        [] ->
          {:noreply, assign(socket, :bundle_error, "Choose a bundle.tar.gz file first.")}
      end
    end
  end

  @impl true
  def handle_event("delete_ingestion", %{"id" => id}, socket) do
    case Ingestions.delete_source_ingestion(String.to_integer(id)) do
      {:ok, _source_ingestion} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ingestion deleted")
         |> load_queue_rows()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset, [:status]))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Ingestion deletion failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Source Ingestion Review">
      <div class="space-y-6">
        <.card title="Review Queue" icon="ph-list-checks">
          <div :if={@queue_rows == []} class="py-8 text-center text-gray-500">
            No source ingestions in the queue.
          </div>

          <div :if={@queue_rows != []} class="overflow-x-auto">
            <.table
              id="ingestion-review-queue"
              rows={sorted_queue_rows(@queue_rows, @sort_by, @sort_dir)}
              row_id={&"ingestion-row-#{&1.id}"}
              sort_by={@sort_by}
              sort_dir={@sort_dir}
            >
              <:col :let={row} label="Title" sort_key={:display_title}>
                <div class="space-y-2">
                  <.link
                    navigate={"/admin/ingestion-review/#{row.id}"}
                    class="font-medium text-gf-maroon hover:underline"
                  >
                    {row.display_title}
                  </.link>
                </div>
              </:col>

              <:col :let={row} label="Status" sort_key={:status}>
                {Presenter.queue_status_label(row)}
              </:col>

              <:col :let={row} label="Uploaded" sort_key={:inserted_at}>
                {format_date(row.inserted_at, :short)}
              </:col>

              <:col :let={row} label="By" sort_key={:uploaded_by_name}>
                {row.uploaded_by_name}
              </:col>

              <:action :let={row}>
                <.link
                  :if={species_review_link_visible?(row)}
                  navigate={"/admin/ingestion-review/#{row.id}/review"}
                  class="text-sm text-gf-maroon hover:underline"
                >
                  Review
                </.link>

                <.table_actions>
                  <.action_button
                    id={"delete-ingestion-#{row.id}"}
                    icon="ph-trash"
                    label="Delete Ingestion"
                    variant="danger"
                    confirm="Are you sure you want to delete this ingestion? This deletes its saved artifacts and cannot be undone."
                    phx-click="delete_ingestion"
                    phx-value-id={row.id}
                  />
                </.table_actions>
              </:action>
            </.table>
          </div>
        </.card>

        <.card title="Upload Bundle" icon="ph-file-arrow-up">
          <.form
            id="bundle-upload-form"
            for={%{}}
            as={:bundle}
            phx-change="validate_bundle"
            phx-submit="submit_bundle"
          >
            <div class="space-y-4">
              <p class="text-sm text-gray-600">
                Upload a <code class="font-mono">bundle.tar.gz</code>
                produced by the Python source-ingestion pipeline.
                Must contain <code class="font-mono">review_artifact.json</code>
                and <code class="font-mono">source.pdf</code>.
              </p>

              <.file_dropzone
                id="bundle-dropzone"
                upload={@uploads.bundle}
                label="Upload bundle (.tar.gz)"
              />

              <div :if={@uploads.bundle.entries != []} class="space-y-2">
                <div
                  :for={entry <- @uploads.bundle.entries}
                  class="flex items-center justify-between rounded-md border border-gray-200 px-3 py-2 text-sm"
                >
                  <span class="font-medium text-gray-700">{entry.client_name}</span>
                  <div class="flex items-center gap-3">
                    <span class="text-gray-500">{entry.progress}%</span>
                    <button
                      type="button"
                      phx-click="cancel_bundle_upload"
                      phx-value-ref={entry.ref}
                      class="text-xs text-red-600 hover:underline"
                    >
                      cancel
                    </button>
                  </div>
                </div>
              </div>

              <.alert :if={@bundle_error} variant="error">{@bundle_error}</.alert>

              <div :for={error <- upload_errors(@uploads.bundle)}>
                <.alert variant="error">{upload_error_message(error)}</.alert>
              </div>

              <.button type="submit" variant="primary" disabled={@uploads.bundle.entries == []}>
                Import bundle
              </.button>
            </div>
          </.form>
        </.card>
      </div>
    </Layouts.admin>
    """
  end

  defp load_queue_rows(socket) do
    assign(socket, :queue_rows, Presenter.list_source_ingestion_queue_rows())
  end

  defp sorted_queue_rows(rows, sort_by, sort_dir) do
    sorted = Enum.sort_by(rows, &sort_key(&1, sort_by))
    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp toggle_sort(%{sort_by: current, sort_dir: dir}, current) do
    [sort_by: current, sort_dir: if(dir == :asc, do: :desc, else: :asc)]
  end

  defp toggle_sort(_assigns, column), do: [sort_by: column, sort_dir: :asc]

  defp sort_key(row, :display_title), do: String.downcase(row.display_title || "")
  defp sort_key(row, :status), do: row.status || ""
  defp sort_key(row, :inserted_at), do: row.inserted_at
  defp sort_key(row, :uploaded_by_name), do: String.downcase(row.uploaded_by_name || "")

  defp species_review_link_visible?(row) do
    row.status in ["needs_review", "complete"] and not is_nil(row.source_id)
  end

  defp changeset_error_message(changeset, fields) do
    fields
    |> Enum.flat_map(&translate_errors(changeset.errors, &1))
    |> Enum.join(", ")
  end

  defp handle_progress(@bundle_upload_name, _entry, socket), do: {:noreply, socket}

  defp import_archive(archive_path, uploaded_by_id) do
    extract_dir = make_extract_dir()

    try do
      with :ok <- extract_bundle(archive_path, extract_dir) do
        bundle_dir = locate_bundle_root(extract_dir)
        Ingestions.import_bundle(bundle_dir, uploaded_by_id: uploaded_by_id)
      end
    after
      File.rm_rf(extract_dir)
    end
  end

  defp make_extract_dir do
    dir =
      Path.join(System.tmp_dir!(), "gallformers-bundle-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp extract_bundle(archive_path, extract_dir) do
    case :erl_tar.extract(String.to_charlist(archive_path), [
           :compressed,
           {:cwd, String.to_charlist(extract_dir)}
         ]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:extract_failed, reason}}
    end
  end

  # The Python pipeline writes the bundle either flat (review_artifact.json at
  # the top level) or nested under a single directory. Detect both.
  defp locate_bundle_root(extract_dir) do
    if File.exists?(Path.join(extract_dir, "review_artifact.json")) do
      extract_dir
    else
      nested_bundle_root(extract_dir)
    end
  end

  defp nested_bundle_root(extract_dir) do
    case File.ls!(extract_dir) do
      [single] ->
        nested = Path.join(extract_dir, single)
        if File.dir?(nested), do: nested, else: extract_dir

      _ ->
        extract_dir
    end
  end

  defp format_import_error({:missing_file, name}), do: "Bundle is missing #{name}."
  defp format_import_error({:invalid_json, _}), do: "review_artifact.json is not valid JSON."

  defp format_import_error({:read_failed, name, _}),
    do: "Failed to read #{name} from the bundle."

  defp format_import_error({:extract_failed, reason}),
    do: "Failed to extract archive: #{inspect(reason)}"

  defp format_import_error(%Ecto.Changeset{} = changeset),
    do: changeset_error_message(changeset, Keyword.keys(changeset.errors))

  defp format_import_error(reason), do: "Import failed: #{inspect(reason)}"

  defp upload_error_message(:too_large), do: "Bundle is too large (max 200 MB)."
  defp upload_error_message(:too_many_files), do: "Only one bundle at a time."
  defp upload_error_message(:not_accepted), do: "File type not accepted; upload a .tar.gz."
  defp upload_error_message(other), do: "Upload error: #{inspect(other)}"
end
