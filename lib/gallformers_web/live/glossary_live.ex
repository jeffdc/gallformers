defmodule GallformersWeb.GlossaryLive do
  @moduledoc """
  The glossary page, on the design system (matter bc0d): every term with
  its definition (other terms in it linked) and numbered references, in a
  `data_table` sortable by word and definition, filtered by a name filter.
  Each row is anchored by its lowercase word: search results and the
  glossary tooltips link to `/glossary#word`. A signed-in user gets an edit
  link per term.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Glossaries
  alias Gallformers.Markdown

  @valid_sort_columns ~w(word definition)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Glossary",
       page_description:
         "A glossary of gall-related terminology - definitions of terms commonly used in cecidiology and gall biology.",
       page_url: "/glossary",
       page_image: nil,
       page_json_ld: nil,
       sort_by: :word,
       sort_dir: :asc,
       search_query: ""
     )
     |> load_entries()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Handle hash navigation for direct term links
    {:noreply, assign(socket, highlight_term: params["term"])}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> load_entries()}
  end

  @impl true
  def handle_event("sort", %{"field" => column}, socket) when column in @valid_sort_columns do
    column_atom = String.to_atom(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        # Toggle direction
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        {column_atom, :asc}
      end

    {:noreply, assign(socket, sort_by: new_sort_by, sort_dir: new_sort_dir)}
  end

  defp sorted_entries(entries, sort_by, sort_dir) do
    sorted =
      Enum.sort_by(entries, fn entry ->
        case sort_by do
          :word -> String.downcase(entry.word || "")
          :definition -> String.downcase(entry.definition || "")
          _ -> String.downcase(entry.word || "")
        end
      end)

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp load_entries(socket) do
    entries =
      case socket.assigns.search_query do
        "" -> Glossaries.list_glossary()
        query -> Glossaries.search_glossary(query)
      end

    assign(socket, :entries, entries)
  end

  defp format_refs(urls) when is_nil(urls), do: []

  defp format_refs(urls) do
    urls
    |> String.split("\n")
    |> Enum.filter(&(String.trim(&1) != ""))
    |> Enum.with_index(1)
    |> then(fn refs ->
      Enum.map(refs, fn {url, index} ->
        %{url: String.trim(url), index: index, sep: if(index < length(refs), do: ", ")}
      end)
    end)
  end

  @impl true
  def render(assigns) do
    sorted = sorted_entries(assigns.entries, assigns.sort_by, assigns.sort_dir)
    assigns = assign(assigns, :sorted_entries, sorted)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Glossary</:title>
          <:description>A glossary of gall related terminology.</:description>
        </.page_header>

        <form phx-change="search" phx-submit="search" id="glossary-search-form" class="max-w-md">
          <.search_field
            id="glossary-search"
            name="query"
            value={@search_query}
            label="Filter glossary terms"
            placeholder="Filter glossary terms..."
          />
        </form>

        <.data_table
          id="glossary"
          rows={@sorted_entries}
          row_id={&String.downcase(&1.word)}
          sort={%{field: @sort_by, dir: @sort_dir}}
        >
          <:col :let={entry} label="Word" field={:word} sortable>
            <span class="inline-flex items-center gap-1 font-semibold text-ink">
              {entry.word}
              <.link
                :if={@current_user}
                navigate={~p"/admin/glossary/#{entry.id}"}
                class="text-muted hover:text-ink"
                title="Edit"
              >
                <.icon name="ph-pencil-simple" class="size-4" />
              </.link>
            </span>
          </:col>
          <:col :let={entry} label="Definition" field={:definition} sortable grow full>
            <span class="text-ink-2">
              {Phoenix.HTML.raw(Markdown.linkify_glossary_terms(entry.definition || ""))}
            </span>
          </:col>
          <:col :let={entry} label="Refs">
            <span class="text-meta">
              <span :for={ref <- format_refs(entry.urls)}>
                <.link href={ref.url} target="_blank" rel="noreferrer">{ref.index}</.link>{ref.sep}
              </span>
            </span>
          </:col>
          <:empty>
            <.empty_state title="No glossary entries found." />
          </:empty>
          <:footer>
            <p class="text-meta text-muted">Showing {length(@entries)} entries</p>
          </:footer>
        </.data_table>
      </div>
    </Layouts.app>
    """
  end
end
