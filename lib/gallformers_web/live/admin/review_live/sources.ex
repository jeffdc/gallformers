defmodule GallformersWeb.Admin.ReviewLive.Sources do
  @moduledoc """
  The Sources to review (`/admin/review`, `6611` Task 6): each Source with
  a package under review, its packages grouped under it
  (`GallformersWeb.Admin.ReviewLive.Loader.sources/0`), with how many
  questions are left, how many have a proposed answer, what holds
  approval and its status. Each opens the Source's page. While any Gall
  rename proposal is open, a row for them (`Loader.renames_row/0`) opens
  their page, `/admin/review/renames`.

  The filter (`filter`: `work`, needs decisions — the default; `ready`,
  ready to approve; `all`) and the sort (`sort`: `close`, closest to done —
  the default; `most`, most to decide; `oldest`, oldest Source first) are
  in the URL.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents

  alias GallformersWeb.Admin.ReviewLive.Loader

  @filters ~w(work ready all)
  @sorts ~w(close most oldest)

  @impl true
  def mount(_params, _session, socket) do
    sources = List.wrap(Loader.renames_row()) ++ Loader.sources()
    {:ok, assign(socket, page_title: "Sources to review", sources: sources)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     assign(socket,
       filter: pick(params["filter"], @filters),
       sort: pick(params["sort"], @sorts)
     )}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket),
    do: {:noreply, push_patch(socket, to: review_path(socket.assigns, filter: filter))}

  def handle_event("sort", %{"sort" => sort}, socket),
    do: {:noreply, push_patch(socket, to: review_path(socket.assigns, sort: sort))}

  defp pick(value, allowed), do: if(value in allowed, do: value, else: hd(allowed))

  defp review_path(assigns, changes) do
    query =
      assigns
      |> Map.take([:filter, :sort])
      |> Map.merge(Map.new(changes))
      |> Enum.reject(fn {key, value} -> value == default(key) end)
      |> Enum.sort()

    case query do
      [] -> ~p"/admin/review"
      query -> ~p"/admin/review?#{query}"
    end
  end

  defp default(:filter), do: "work"
  defp default(:sort), do: "close"

  defp shown(sources, filter, sort) do
    sources
    |> Enum.filter(fn s ->
      case filter do
        "work" -> not s.ready
        "ready" -> s.ready
        "all" -> true
      end
    end)
    |> Enum.sort_by(&sort_key(&1, sort))
  end

  defp sort_key(s, "close"), do: {s.to_decide, s.title}
  defp sort_key(s, "most"), do: {-s.to_decide, s.title}
  defp sort_key(s, "oldest"), do: {s.year || 9999, s.title}

  defp holding_text([]), do: "Nothing holds approval"

  defp holding_text(holding),
    do: Enum.map_join(holding, "; ", fn {n, title} -> "#{n} × #{title}" end)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :rows, shown(assigns.sources, assigns.filter, assigns.sort))

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-block">
        <.page_header>
          <:title>Sources to review</:title>
          <:description>
            Each Source is checked on its own page. Approve it when nothing holds it.
          </:description>
        </.page_header>

        <div class="flex flex-wrap items-center gap-2">
          <.button
            :for={
              {value, label} <- [
                {"work", "Needs decisions"},
                {"ready", "Ready to approve"},
                {"all", "All"}
              ]
            }
            id={"filter-#{value}"}
            phx-click="filter"
            phx-value-filter={value}
            size="sm"
            variant={if @filter == value, do: "primary", else: "secondary"}
          >
            {label}
          </.button>
          <span class="flex-1"></span>
          <.form for={%{}} id="review-sort" phx-change="sort" class="flex items-center gap-2">
            <label for="review-sort-select" class="text-meta text-muted">Sort</label>
            <select id="review-sort-select" name="sort" class="gf-select w-auto">
              <option
                :for={
                  {value, label} <- [
                    {"close", "Closest to done"},
                    {"most", "Most to decide"},
                    {"oldest", "Oldest Source first"}
                  ]
                }
                value={value}
                selected={@sort == value}
              >
                {label}
              </option>
            </select>
          </.form>
        </div>

        <.data_table
          id="review-sources"
          rows={@rows}
          row_id={& &1.id}
          row_click={&JS.navigate(&1.path)}
        >
          <:col :let={s} label="Source" grow full>
            <.link navigate={s.path} class="font-semibold">{s.title}</.link>
            <div :if={s.citation && s.citation != s.title} class="text-meta text-muted">
              {s.citation}
            </div>
            <div class="mt-1 flex flex-wrap gap-1.5">
              <.review_tag :if={s.kind}>{s.kind}</.review_tag>
              <.review_tag :if={s.notes}>{s.packages} notes</.review_tag>
            </div>
          </:col>
          <:col :let={s} label="To decide" full>
            <span data-role="to-decide" class="text-subsection font-semibold tabular-nums">
              {s.to_decide}
            </span>
            <div class="text-meta text-muted">{s.proposed} with a proposed answer</div>
            <div :if={s.set_aside > 0} data-role="set-aside" class="text-meta text-muted">
              {s.set_aside} set aside
            </div>
            <.review_progress done={0} proposed={s.proposed} total={s.to_decide} class="mt-1 w-36" />
          </:col>
          <:col :let={s} label="Holding approval" full>
            <span data-role="holding" class="text-meta text-ink-2">{holding_text(s.holding)}</span>
          </:col>
          <:col :let={s} label="Status">
            <.chip variant={if s.ready, do: :ok, else: :warn}>{s.status}</.chip>
          </:col>
          <:empty>No Sources here.</:empty>
        </.data_table>
      </div>
    </Layouts.admin>
    """
  end
end
