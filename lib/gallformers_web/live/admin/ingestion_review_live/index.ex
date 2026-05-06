defmodule GallformersWeb.Admin.IngestionReviewLive.Index do
  use GallformersWeb, :live_view

  alias Gallformers.Accounts
  alias Gallformers.IngestionPipeline.PipelineConfigs
  alias Gallformers.Ingestions
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  @pdf_upload_name :pdf

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    current_user_db_id = Accounts.db_user_id(session)
    uploaded_by_scope = default_uploaded_by_scope(current_user_db_id)

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:current_user_db_id, current_user_db_id)
      |> assign(:page_title, "Source Ingestion Review")
      |> assign(:include_complete, false)
      |> assign(:uploaded_by_scope, uploaded_by_scope)
      |> assign(:pdf_form, empty_form(:pdf_submission))
      |> assign(:url_form, empty_form(:url_submission))
      |> assign(:text_form, empty_form(:text_submission))
      |> assign(:pdf_error, nil)
      |> assign(:pipeline_config_options, PipelineConfigs.config_options())
      |> allow_upload(@pdf_upload_name,
        accept: ~w(.pdf),
        max_entries: 1,
        max_file_size: 50_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> load_queue_rows()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_uploader_scope", %{"uploaded_by_scope" => scope}, socket) do
    {:noreply,
     socket
     |> assign(
       :uploaded_by_scope,
       parse_uploaded_by_scope(scope, socket.assigns.current_user_db_id)
     )
     |> load_queue_rows()}
  end

  @impl true
  def handle_event("toggle_include_complete", _params, socket) do
    {:noreply,
     socket
     |> assign(:include_complete, !socket.assigns.include_complete)
     |> load_queue_rows()}
  end

  @impl true
  def handle_event("validate_pdf_submission", _params, socket) do
    {:noreply, assign(socket, :pdf_error, nil)}
  end

  @impl true
  def handle_event("validate_url_submission", %{"url_submission" => params}, socket) do
    {:noreply, assign(socket, :url_form, to_form(params, as: :url_submission))}
  end

  @impl true
  def handle_event("validate_text_submission", %{"text_submission" => params}, socket) do
    {:noreply, assign(socket, :text_form, to_form(params, as: :text_submission))}
  end

  @impl true
  def handle_event("submit_pdf", params, socket) do
    pdf_params = Map.get(params, "pdf_submission", %{})

    case current_user_db_id(socket) do
      {:ok, uploaded_by_id} ->
        case consume_pdf_upload(socket) do
          {:ok, socket, %{filename: filename, content: content}} ->
            socket
            |> submit_ingestion(
              %{
                input_type: "pdf",
                uploaded_by_id: uploaded_by_id,
                filename: filename,
                content: content,
                pipeline_config_id: parse_config_id(pdf_params)
              },
              :pdf_submission
            )

          {:error, socket, error_message} ->
            {:noreply, assign(socket, :pdf_error, error_message)}
        end

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_url", %{"url_submission" => params}, socket) do
    case current_user_db_id(socket) do
      {:ok, uploaded_by_id} ->
        socket
        |> submit_ingestion(
          %{
            input_type: "url",
            uploaded_by_id: uploaded_by_id,
            url: Map.get(params, "url", ""),
            pipeline_config_id: parse_config_id(params)
          },
          :url_submission
        )

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_text", %{"text_submission" => params}, socket) do
    case current_user_db_id(socket) do
      {:ok, uploaded_by_id} ->
        socket
        |> submit_ingestion(
          %{
            input_type: "text",
            uploaded_by_id: uploaded_by_id,
            text: Map.get(params, "text", ""),
            pipeline_config_id: parse_config_id(params)
          },
          :text_submission
        )

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_failed_ingestion", %{"id" => id}, socket) do
    case Ingestions.delete_failed_source_ingestion(String.to_integer(id)) do
      {:ok, _source_ingestion} ->
        {:noreply,
         socket
         |> put_flash(:info, "Failed ingestion cleared")
         |> load_queue_rows()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset, [:status]))}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed ingestion cleanup failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Source Ingestion Review">
      <div class="space-y-6">
        <.card title="Queue Filters" icon="ph-funnel">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <form id="queue-filter-form" phx-change="set_uploader_scope">
              <.radio_group
                id="uploaded-by-scope"
                name="uploaded_by_scope"
                label="Uploaded by"
                value={@uploaded_by_scope}
                options={[
                  %{value: "me", label: "Me"},
                  %{value: "all", label: "All reviewers"}
                ]}
              />
            </form>

            <div class="flex items-center gap-3">
              <.toggle
                id="include-complete"
                name="include_complete"
                checked={@include_complete}
                label="Include complete items"
                phx-click="toggle_include_complete"
              />
            </div>
          </div>
        </.card>

        <div class="grid gap-6 xl:grid-cols-3">
          <.card title="New Source: PDF" icon="ph-file-pdf">
            <.form
              id="pdf-submission-form"
              for={@pdf_form}
              phx-change="validate_pdf_submission"
              phx-submit="submit_pdf"
            >
              <div class="space-y-4">
                <.file_dropzone
                  id="pdf-dropzone"
                  upload={@uploads.pdf}
                  label="Upload PDF (.pdf)"
                />

                <div :if={@uploads.pdf.entries != []} class="space-y-2">
                  <div
                    :for={entry <- @uploads.pdf.entries}
                    class="flex items-center justify-between rounded-md border border-gray-200 px-3 py-2 text-sm"
                  >
                    <span class="font-medium text-gray-700">{entry.client_name}</span>
                    <span class="text-gray-500">{entry.progress}%</span>
                  </div>
                </div>

                <.alert :if={@pdf_error} variant="error">{@pdf_error}</.alert>

                <div :for={error <- upload_errors(@uploads.pdf)}>
                  <.alert variant="error">{upload_error_message(error)}</.alert>
                </div>

                <.pipeline_config_select
                  name="pdf_submission[pipeline_config_id]"
                  options={@pipeline_config_options}
                />

                <.button type="submit" variant="primary">Create From PDF</.button>
              </div>
            </.form>
          </.card>

          <.card title="New Source: URL" icon="ph-link">
            <.form
              id="url-submission-form"
              for={@url_form}
              phx-change="validate_url_submission"
              phx-submit="submit_url"
            >
              <div class="space-y-4">
                <.input
                  field={@url_form[:url]}
                  type="url"
                  label="Source URL"
                  placeholder="https://example.com/article"
                />

                <.pipeline_config_select
                  name="url_submission[pipeline_config_id]"
                  options={@pipeline_config_options}
                />

                <.button type="submit" variant="primary">Create From URL</.button>
              </div>
            </.form>
          </.card>

          <.card title="New Source: Text" icon="ph-text-aa">
            <.form
              id="text-submission-form"
              for={@text_form}
              phx-change="validate_text_submission"
              phx-submit="submit_text"
            >
              <div class="space-y-4">
                <.input
                  field={@text_form[:text]}
                  type="textarea"
                  label="Extracted text"
                  rows="10"
                  placeholder="Paste source text here"
                />

                <.pipeline_config_select
                  name="text_submission[pipeline_config_id]"
                  options={@pipeline_config_options}
                />

                <.button type="submit" variant="primary">Create From Text</.button>
              </div>
            </.form>
          </.card>
        </div>

        <.card title="Review Queue" icon="ph-list-checks">
          <div :if={@queue_rows == []} class="py-8 text-center text-gray-500">
            No source ingestions match the current filters.
          </div>

          <div :if={@queue_rows != []} class="overflow-x-auto">
            <.table id="ingestion-review-queue" rows={@queue_rows} row_id={&"ingestion-row-#{&1.id}"}>
              <:col :let={row} label="Title">
                <div class="space-y-2">
                  <.link
                    navigate={"/admin/ingestion-review/#{row.id}"}
                    class="font-medium text-gf-maroon hover:underline"
                  >
                    {row.display_title}
                  </.link>
                  <.badge :if={duplicate_review_row?(row)} variant="warning">
                    Duplicate review
                  </.badge>
                </div>
              </:col>

              <:col :let={row} label="Species">
                {species_progress_label(row)}
              </:col>

              <:col :let={row} label="Status">
                {Presenter.queue_status_label(row)}
              </:col>

              <:col :let={row} label="Uploaded">
                {format_date(row.inserted_at, :short)}
              </:col>

              <:col :let={row} label="By">
                {row.uploaded_by_name}
              </:col>

              <:action :let={row}>
                <.table_actions :if={failed_queue_row?(row)}>
                  <.action_button
                    id={"clear-failed-ingestion-#{row.id}"}
                    icon="ph-trash"
                    label="Clear Failed Ingestion"
                    variant="danger"
                    confirm="Are you sure you want to clear this failed ingestion? This deletes its saved artifacts and cannot be undone."
                    phx-click="clear_failed_ingestion"
                    phx-value-id={row.id}
                  />
                </.table_actions>
              </:action>
            </.table>
          </div>
        </.card>
      </div>
    </Layouts.admin>
    """
  end

  defp handle_progress(@pdf_upload_name, _entry, socket), do: {:noreply, socket}

  defp load_queue_rows(socket) do
    assign(
      socket,
      :queue_rows,
      Presenter.list_source_ingestion_queue_rows(queue_row_opts(socket))
    )
  end

  defp queue_row_opts(socket) do
    [
      include_complete: socket.assigns.include_complete
    ]
    |> maybe_put_uploaded_by_id(
      socket.assigns.uploaded_by_scope,
      socket.assigns.current_user_db_id
    )
  end

  defp maybe_put_uploaded_by_id(opts, :me, uploaded_by_id) when is_integer(uploaded_by_id) do
    Keyword.put(opts, :uploaded_by_id, uploaded_by_id)
  end

  defp maybe_put_uploaded_by_id(opts, _scope, _uploaded_by_id), do: opts

  defp submit_ingestion(socket, attrs, form_key) do
    case Ingestions.submit_source_ingestion(attrs) do
      {:ok, ingestion} ->
        {:noreply, push_navigate(socket, to: "/admin/ingestion-review/#{ingestion.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, submission_error_socket(socket, changeset, form_key)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Submission failed: #{inspect(reason)}")}
    end
  end

  defp submission_error_socket(socket, changeset, :pdf_submission) do
    if field_errors_for_submission?(changeset, [:filename, :content]) do
      assign(socket, :pdf_error, changeset_error_message(changeset, [:filename, :content]))
    else
      put_flash(socket, :error, "Failed to enqueue ingestion")
    end
  end

  defp submission_error_socket(socket, changeset, :url_submission) do
    socket = assign(socket, :url_form, to_form(changeset, as: :url_submission))

    if field_errors_for_submission?(changeset, [:url]) do
      socket
    else
      put_flash(socket, :error, "Failed to enqueue ingestion")
    end
  end

  defp submission_error_socket(socket, changeset, :text_submission) do
    socket = assign(socket, :text_form, to_form(changeset, as: :text_submission))

    if field_errors_for_submission?(changeset, [:text]) do
      socket
    else
      put_flash(socket, :error, "Failed to enqueue ingestion")
    end
  end

  defp consume_pdf_upload(socket) do
    queued_entries = queued_upload_entries(socket, @pdf_upload_name)

    if queued_entries == [] do
      {:error, socket, "Upload a PDF to continue."}
    else
      [pdf_upload] =
        consume_uploaded_entries(socket, @pdf_upload_name, fn %{path: path}, entry ->
          {:ok, %{filename: entry.client_name, content: File.read!(path)}}
        end)

      {:ok, assign(socket, :pdf_error, nil), pdf_upload}
    end
  end

  defp queued_upload_entries(socket, upload_name) do
    socket.assigns.uploads
    |> Map.fetch!(upload_name)
    |> Map.get(:entries, [])
  end

  defp current_user_db_id(socket) do
    case socket.assigns.current_user_db_id do
      uploaded_by_id when is_integer(uploaded_by_id) ->
        {:ok, uploaded_by_id}

      _ ->
        {:error,
         put_flash(socket, :error, "You need a database-backed profile to submit sources.")}
    end
  end

  defp default_uploaded_by_scope(uploaded_by_id) when is_integer(uploaded_by_id), do: :me
  defp default_uploaded_by_scope(_), do: :all

  defp parse_uploaded_by_scope("me", uploaded_by_id) when is_integer(uploaded_by_id), do: :me
  defp parse_uploaded_by_scope("all", _uploaded_by_id), do: :all
  defp parse_uploaded_by_scope(_, uploaded_by_id), do: default_uploaded_by_scope(uploaded_by_id)

  defp empty_form(form_name), do: to_form(%{}, as: form_name)

  defp duplicate_review_row?(row), do: row.status == "needs_duplicate_review"
  defp failed_queue_row?(row), do: row.status == "failed"

  defp species_progress_label(row) do
    if row.total_species_entries_count > 0 do
      "#{row.resolved_species_entries_count} of #{row.total_species_entries_count} reviewed"
    else
      "No extracted galls yet"
    end
  end

  defp pipeline_config_select(assigns) do
    ~H"""
    <div :if={@options != []} class="mb-3">
      <label class="block text-xs font-medium text-gray-600 mb-1">Pipeline Config</label>
      <select
        name={@name}
        class="w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-gf-maroon focus:ring-gf-maroon"
      >
        <option value="">Default (module defaults)</option>
        <option :for={{id, name} <- @options} value={id}>{name}</option>
      </select>
    </div>
    """
  end

  defp parse_config_id(%{"pipeline_config_id" => ""}), do: nil

  defp parse_config_id(%{"pipeline_config_id" => id}) when is_binary(id),
    do: String.to_integer(id)

  defp parse_config_id(_params), do: nil

  defp upload_error_message(:too_large), do: "File is too large."
  defp upload_error_message(:not_accepted), do: "Only PDF files are accepted."
  defp upload_error_message(:too_many_files), do: "Only one file at a time."
  defp upload_error_message(error), do: "Upload error: #{inspect(error)}"

  defp field_errors_for_submission?(changeset, fields) do
    Enum.any?(fields, &(changeset.errors[&1] != nil))
  end

  defp changeset_error_message(changeset, fields) do
    fields
    |> Enum.flat_map(&translate_errors(changeset.errors, &1))
    |> Enum.join(", ")
  end
end
