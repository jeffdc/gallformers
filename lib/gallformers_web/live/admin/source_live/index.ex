defmodule GallformersWeb.Admin.SourceLive.Index do
  @moduledoc """
  The Source editor's list (matter a856, Task 10; on the design system's
  admin list pattern, matter bc0d): the Sources by title,
  searched by title or author and paginated, each linking to its editor.
  Sources are created by imports; there is no "new" and no delete.

  Each Source shows when it was ingested and last updated
  (`Gallformers.Import.source_dates/1`; a Source from the old data says
  so), and, while a package of it is under review, a link to its review
  with the questions left (`GallformersWeb.Admin.ReviewLive.Loader.reviews_by_source/0`,
  read once on mount) (matter `f14c`).
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents, only: [review_in_progress_link: 1]

  alias Gallformers.Import
  alias Gallformers.Sources
  alias GallformersWeb.Admin.ReviewLive.Loader

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sources")
     |> assign(:query, "")
     |> assign(:page, 1)
     |> assign(:page_size, @page_size)
     |> assign(:reviews, Loader.reviews_by_source())
     |> load_sources()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(query: query, page: 1) |> load_sources()}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page = page |> max(1) |> min(total_pages(socket.assigns.total, @page_size))
    {:noreply, socket |> assign(:page, page) |> load_sources()}
  end

  defp load_sources(socket) do
    %{entries: sources, total: total} =
      Sources.list_sources_page(
        query: socket.assigns.query,
        page: socket.assigns.page,
        page_size: @page_size
      )

    assign(socket,
      sources: sources,
      total: total,
      dates: sources |> Enum.map(& &1.id) |> Import.source_dates()
    )
  end

  defp date_text(nil), do: nil
  defp date_text(datetime), do: format_date(datetime, :short)

  defp total_pages(total, page_size), do: max(1, ceil(total / page_size))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Sources</:title>
          <:meta label="Sources">{@total}</:meta>
          <:description>
            Sources arrive with imports. Here you can correct a Source's details, or mark it retracted by a retraction notice (and undo that).
          </:description>
        </.page_header>

        <form id="source-search-form" phx-change="search" phx-submit="search" class="max-w-md">
          <.search_field
            id="source-search"
            name="query"
            value={@query}
            label="Search the Sources"
            placeholder="Title or author"
          />
        </form>

        <div id="sources-table">
          <.data_table id="sources" rows={@sources} row_id={&"source-#{&1.id}"} compact>
            <:col :let={source} label="Title" grow>
              <.link navigate={~p"/admin/sources/#{source.id}"} class="font-semibold">
                {source.title}
              </.link>
            </:col>
            <:col :let={source} label="Author" hide_below={:md}>
              <span class="text-ink-2">{source.author}</span>
            </:col>
            <:col :let={source} label="Year">
              <span class="text-ink-2">{source.pubyear}</span>
            </:col>
            <:col :let={source} label="Kind" hide_below={:lg}>
              <span class="text-ink-2">{source.kind}</span>
            </:col>
            <:col :let={source} label="Ingested" hide_below={:lg}>
              <% dates = @dates[source.id] %>
              <span data-role="ingested" class="text-meta text-muted">
                {if dates.legacy?, do: legacy_source_text(), else: date_text(dates.ingested)}
              </span>
            </:col>
            <:col :let={source} label="Updated" hide_below={:md}>
              <span data-role="updated" class="text-meta text-muted">
                {date_text(@dates[source.id].updated)}
              </span>
            </:col>
            <:col :let={source} label="Status">
              <span class="flex items-center gap-2">
                <span :if={@reviews[source.id]} class="text-meta">
                  <.review_in_progress_link review={@reviews[source.id]} />
                </span>
                <.chip :if={source.retracted_by_id} variant={:warn} size="sm">Retracted</.chip>
                <.chip
                  :if={!source.retracted_by_id && source.datacomplete}
                  variant={:ok}
                  size="sm"
                >
                  Complete
                </.chip>
              </span>
            </:col>
            <:empty>No sources found. Try a different search term.</:empty>
            <:footer>
              <.pagination
                :if={total_pages(@total, @page_size) > 1}
                page={@page}
                total_pages={total_pages(@total, @page_size)}
                total_items={@total}
                page_size={@page_size}
                on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
              />
              <span :if={total_pages(@total, @page_size) <= 1}>Showing {@total} sources</span>
            </:footer>
          </.data_table>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
