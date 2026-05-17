defmodule GallformersWeb.Admin.IngestionReviewLive.Show do
  use GallformersWeb, :live_view

  require Logger

  alias Gallformers.Accounts
  alias Gallformers.Ingestions
  alias Gallformers.Sources
  alias GallformersWeb.Admin.IngestionReviewLive.Presenter

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:current_user, session["current_user"])
     |> assign(:current_user_db_id, Accounts.db_user_id(session))
     |> assign(:page_title, "Source Ingestion Review")
     |> assign(:review_view, nil)
     |> assign(:selected_source, nil)
     |> assign(:source_search_query, "")
     |> assign(:source_search_results, [])
     |> assign(:source_text, nil)
     |> assign(:source_text_focus, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    ingestion_id = String.to_integer(id)
    {:noreply, load_review_view(socket, ingestion_id)}
  end

  @impl true
  def handle_event("search_sources", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Sources.search_sources(query)
        |> Enum.take(10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:source_search_query, query)
     |> assign(:source_search_results, results)}
  end

  @impl true
  def handle_event("select_source", %{"id" => id}, socket) do
    source =
      id
      |> parse_integer_param()
      |> Sources.get_source!()

    {:noreply,
     socket
     |> assign(:selected_source, source)
     |> assign(:source_search_query, "")
     |> assign(:source_search_results, [])}
  end

  @impl true
  def handle_event("associate_source", _params, socket) do
    case socket.assigns.selected_source do
      %{id: source_id} ->
        source_ingestion = Ingestions.get_source_ingestion!(socket.assigns.review_view.id)

        case Ingestions.associate_source(source_ingestion, source_id) do
          {:ok, _source_ingestion} ->
            {:noreply,
             socket
             |> put_flash(:info, "Source associated")
             |> reload_review_view()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_source_association", _params, socket) do
    if persisted_selected_source?(socket.assigns.review_view, socket.assigns.selected_source) do
      source_ingestion = Ingestions.get_source_ingestion!(socket.assigns.review_view.id)

      case Ingestions.clear_source_association(source_ingestion) do
        {:ok, _source_ingestion} ->
          {:noreply,
           socket
           |> put_flash(:info, "Source association cleared")
           |> reload_review_view()}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}
      end
    else
      {:noreply,
       socket
       |> assign(:selected_source, socket.assigns.review_view.associated_source)
       |> assign(:source_search_query, "")
       |> assign(:source_search_results, [])}
    end
  end

  @impl true
  def handle_event("clear_source_ingestion", _params, socket) do
    case Ingestions.clear_source_ingestion(socket.assigns.review_view.id) do
      {:ok, _source_ingestion} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ingestion cleared")
         |> push_navigate(to: ~p"/admin/ingestion-review")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_error_message(changeset))}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed ingestion cleanup failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div :if={@review_view} class="space-y-6">
        <.ingestion_breadcrumb review_view={@review_view} />

        <.card title="Submission Detail" icon="ph-file-text">
          <div class="space-y-3">
            <div class="flex flex-col gap-2 lg:flex-row lg:items-start lg:justify-between">
              <div class="space-y-1">
                <h2 class="text-2xl font-semibold text-gf-maroon">
                  {@review_view.display_title}
                </h2>
                <div class="flex flex-wrap gap-2">
                  <.badge variant={status_badge_variant(@review_view.status)}>
                    {status_label(@review_view)}
                  </.badge>
                  <.badge variant="info">
                    {@review_view.counts.species_entries_total} extracted gall entries
                  </.badge>
                </div>
              </div>

              <div class="flex items-center gap-3">
                <.button
                  :if={@review_view.clearable?}
                  id="clear-source-ingestion"
                  type="button"
                  variant="danger"
                  phx-click="clear_source_ingestion"
                  data-confirm="Are you sure you want to clear this failed ingestion? This deletes its saved artifacts and cannot be undone."
                >
                  {clear_source_ingestion_label(@review_view)}
                </.button>
              </div>
            </div>

            <.alert :if={@review_view.status == "failed"} variant="warning">
              Pipeline failed at <strong>{@review_view.error_stage}</strong>
              stage: {@review_view.error_message || "unknown error"}
            </.alert>

            <div class="flex gap-6 text-sm">
              <div>
                <span class="font-medium text-gray-500">Input Type</span>
                <span class="ml-1 text-gray-900">{String.upcase(@review_view.input_type)}</span>
              </div>
              <div>
                <span class="font-medium text-gray-500">Uploaded</span>
                <span class="ml-1 text-gray-900">
                  {format_date(@review_view.inserted_at, :short)}
                </span>
              </div>
            </div>
          </div>
        </.card>

        <.card title="Source Review" icon="ph-book-open">
          <div class="space-y-4">
            <div class="space-y-2">
              <h3 class="text-sm font-semibold text-gray-700">Submission Metadata</h3>

              <.list>
                <:item title="Title">{@review_view.display_title}</:item>
                <:item title="Authors">{authors_text(@review_view.authors)}</:item>
                <:item title="Year">{metadata_value(@review_view.publication_year)}</:item>
                <:item title="DOI/URL">{metadata_value(@review_view.doi)}</:item>
              </.list>
            </div>

            <.alert
              :if={!@review_view.source_review_unlocked? && @review_view.status == "processing"}
              variant="info"
            >
              Source review unlocks after automated processing completes.
            </.alert>

            <.alert
              :if={
                !@review_view.source_review_unlocked? && @review_view.status == "duplicate_confirmed"
              }
              variant="warning"
            >
              This submission is a confirmed duplicate, so source review is no longer applicable.
            </.alert>

            <div :if={@review_view.source_review_unlocked?} class="space-y-4 border-t pt-4">
              <div class="flex flex-col gap-3 xl:flex-row xl:items-end xl:justify-between">
                <div class="flex-1">
                  <.typeahead
                    id="source-picker"
                    label="Match To Existing Source"
                    placeholder="Search sources by title or author..."
                    query={@source_search_query}
                    results={@source_search_results}
                    selected={@selected_source}
                    search_event="search_sources"
                    select_event="select_source"
                    clear_event="clear_source_association"
                    display_fn={&source_display/1}
                  >
                    <:result :let={source}>
                      <div class="font-medium text-gray-900">{source.title}</div>
                      <div class="text-sm text-gray-600">
                        {source.author} ({source.pubyear})
                      </div>
                    </:result>
                  </.typeahead>
                </div>

                <.link
                  href={new_source_url(@review_view)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="gf-btn gf-btn-secondary"
                >
                  Create New Source
                </.link>
              </div>

              <div
                :if={@selected_source}
                id="selected-source-summary"
                class="rounded-lg border border-gray-200 bg-gray-50 p-4 space-y-1"
              >
                <div class="font-medium text-gray-900">{source_display(@selected_source)}</div>
                <div class="text-sm text-gray-600">{source_details(@selected_source)}</div>
                <p
                  :if={persisted_selected_source?(@review_view, @selected_source)}
                  class="text-sm text-gray-500"
                >
                  This source association is already persisted.
                </p>
                <p
                  :if={!persisted_selected_source?(@review_view, @selected_source)}
                  class="text-sm text-gray-500"
                >
                  This selection is not persisted yet. Use Associate Source to save it.
                </p>
              </div>

              <div class="flex flex-wrap gap-3">
                <.button
                  :if={show_associate_source_action?(@review_view, @selected_source)}
                  id="associate-source"
                  type="button"
                  variant="primary"
                  phx-click="associate_source"
                >
                  Associate Source
                </.button>
              </div>

              <details
                :if={@source_text}
                id="full-source-text-panel"
                class="rounded-lg border border-gray-200"
              >
                <summary class="cursor-pointer px-4 py-3 text-sm font-medium text-gray-900">
                  Full Extracted Text
                </summary>
                <div class="border-t border-gray-200 px-4 py-4 space-y-3">
                  <div
                    :if={@source_text_focus}
                    class="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-900"
                  >
                    Focused fragment: {@source_text_focus}
                  </div>
                  <pre class="max-h-96 overflow-auto whitespace-pre-wrap text-sm text-gray-700">{@source_text}</pre>
                </div>
              </details>
            </div>
          </div>
        </.card>

        <.card title="Gall Review" icon="gf-gall">
          <div class="space-y-4">
            <div class="flex flex-wrap items-center gap-3">
              <.badge variant="info">
                {@review_view.counts.species_entries_pending} of {@review_view.counts.species_entries_total} galls remaining
              </.badge>
              <.badge variant="info">
                {@review_view.counts.species_entries_resolved} reviewed
              </.badge>
            </div>

            <div :if={@review_view.species_entries == []} class="text-sm text-gray-500">
              No extracted gall entries are ready yet.
            </div>

            <.alert
              :if={@review_view.species_entries != [] && !@review_view.species_review_unlocked?}
              id="species-review-source-locked"
              variant="warning"
            >
              Associate a source to enable gall review.
            </.alert>

            <.table
              :if={@review_view.species_entries != []}
              id="species-review-list"
              rows={@review_view.species_entries}
              row_id={&"species-entry-#{&1.id}"}
              variant="compact"
              zebra={false}
            >
              <:col :let={entry} label="Gall">
                <div class="font-medium">{entry.extracted_name || "Unnamed gall"}</div>
                <div :if={entry.extracted_authority} class="text-xs text-gray-500">
                  {entry.extracted_authority}
                </div>
                <div :if={entry.mapped_species_name} class="text-xs text-gray-500">
                  &rarr; {entry.mapped_species_name}
                </div>
              </:col>
              <:col :let={entry} label="Hosts">
                {entry.extracted_hosts |> Enum.map(& &1.name) |> Enum.join(", ")}
              </:col>
              <:col :let={entry} label="Aliases">
                {Enum.join(entry.extracted_aliases, ", ")}
              </:col>
              <:col :let={entry} label="Traits">
                <span :if={entry.extracted_trait_names != []}>
                  {humanize_list(entry.extracted_trait_names)}
                </span>
              </:col>
              <:col :let={entry} label="Status">
                <.badge variant="info">{entry.status}</.badge>
              </:col>
            </.table>
          </div>
        </.card>
      </div>
    </Layouts.admin>
    """
  end

  defp load_review_view(socket, source_ingestion_id) do
    review_view = Presenter.source_ingestion_review_view!(source_ingestion_id)

    source_text =
      case Ingestions.source_ingestion_full_text(source_ingestion_id) do
        {:ok, text} -> text
        _ -> nil
      end

    socket
    |> assign(:review_view, review_view)
    |> assign(:page_title, review_view.display_title)
    |> assign(:selected_source, review_view.associated_source)
    |> assign(:source_search_query, "")
    |> assign(:source_search_results, [])
    |> assign(:source_text, source_text)
    |> assign(:source_text_focus, nil)
  end

  defp reload_review_view(socket) do
    load_review_view(socket, socket.assigns.review_view.id)
  end

  defp status_label(review_view), do: Presenter.queue_status_label(review_view)
  defp clear_source_ingestion_label(%{clearability: :abandoned}), do: "Clear Abandoned Ingestion"
  defp clear_source_ingestion_label(_review_view), do: "Clear Failed Ingestion"

  defp status_badge_variant("duplicate_confirmed"), do: "warning"
  defp status_badge_variant("failed"), do: "warning"
  defp status_badge_variant("complete"), do: "success"
  defp status_badge_variant(_), do: "info"

  defp new_source_url(review_view) do
    params =
      %{
        title: review_view.title,
        author: authors_for_url(review_view.authors),
        pubyear: review_view.publication_year,
        link: review_view.doi
      }
      |> Enum.reject(fn {_k, v} -> v in [nil, "", []] end)
      |> Map.new()

    ~p"/admin/sources/new?#{params}"
  end

  defp authors_for_url([]), do: nil
  defp authors_for_url(authors) when is_list(authors), do: Enum.join(authors, " and ")

  defp metadata_value(nil), do: "None"
  defp metadata_value(""), do: "None"
  defp metadata_value(value), do: to_string(value)

  defp parse_integer_param(value) when is_integer(value), do: value
  defp parse_integer_param(value) when is_binary(value), do: String.to_integer(value)

  defp authors_text([]), do: "None"
  defp authors_text(authors) when is_list(authors), do: Enum.join(authors, ", ")

  defp source_display(source), do: source.title

  defp source_details(source) do
    [source.author, source.pubyear]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp persisted_selected_source?(review_view, %{id: selected_source_id}) do
    review_view.source_id == selected_source_id
  end

  defp persisted_selected_source?(_, _), do: false

  defp show_associate_source_action?(review_view, %{id: selected_source_id}) do
    review_view.source_review_unlocked? and review_view.source_id != selected_source_id
  end

  defp show_associate_source_action?(_, _), do: false

  defp humanize_list([item]), do: item
  defp humanize_list([a, b]), do: "#{a} and #{b}"

  defp humanize_list(items),
    do: "#{Enum.slice(items, 0..-2//1) |> Enum.join(", ")}, and #{List.last(items)}"

  attr :review_view, :map, required: true

  defp ingestion_breadcrumb(assigns) do
    ~H"""
    <nav class="flex items-center justify-between rounded-lg border border-gray-200 bg-white px-4 py-2.5 shadow-sm">
      <div class="flex items-center gap-1.5 min-w-0 text-sm">
        <.link navigate={~p"/admin/ingestion-review"} class="shrink-0 text-gf-maroon hover:underline">
          Queue
        </.link>
        <.icon name="ph-caret-right" class="size-3.5 shrink-0 text-gray-400" />
        <span class="truncate text-gray-700" title={@review_view.display_title}>
          {@review_view.display_title}
        </span>
      </div>
      <.link
        :if={@review_view.species_review_unlocked?}
        navigate={~p"/admin/ingestion-review/#{@review_view.id}/review"}
        data-role="proceed-to-review"
        class="gf-btn gf-btn-primary shrink-0 ml-4"
      >
        Species Review
      </.link>
    </nav>
    """
  end

  defp changeset_error_message(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, error} -> "#{field} #{translate_error(error)}" end)
  end
end
