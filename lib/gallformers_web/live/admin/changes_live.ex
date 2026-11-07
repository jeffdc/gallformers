defmodule GallformersWeb.Admin.ChangesLive do
  @moduledoc """
  The Changes page (design system, matters bc0d and 15db): every curator
  change (`Gallformers.Catalog.changes/1`), newest first, as `change_entry`s
  with View and Edit on each Gall, taxon and Fact. In the URL: `q` (a Gall,
  taxon, Source or value), `who` (a curator), `kind` (an operation) and
  `period` (7d, 30d or all; 30d by default). Kept up to date through
  `Gallformers.Audit.ChangeLog.subscribe/0`, keeping the search and filters.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Audit.ChangeLog
  alias Gallformers.Catalog

  @periods [{"7d", "7 days", 7}, {"30d", "30 days", 30}, {"all", "Everything", nil}]
  @read 1000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: ChangeLog.subscribe()
    {:ok, assign(socket, page_title: "Changes", current_user: session["current_user"])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "q" => params["q"] || "",
      "who" => params["who"] || "",
      "kind" => params["kind"] || "",
      "period" => if(params["period"] in ~w(7d 30d all), do: params["period"], else: "30d")
    }

    {:noreply, socket |> assign(filters: filters) |> load_changes()}
  end

  # Changes were recorded: read them again, under the same search and filters.
  @impl true
  def handle_info({:change_log, :changed}, socket) do
    ChangeLog.flush()
    {:noreply, load_changes(socket)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ~w(q who kind)))
      |> Map.reject(fn {_key, value} -> value in ["", nil] end)

    {:noreply, push_patch(socket, to: ~p"/admin/changes?#{filters}")}
  end

  defp load_changes(%{assigns: %{filters: filters}} = socket) do
    groups = Catalog.changes(limit: @read, since: since(filters["period"]))

    assign(socket,
      curators: groups |> Enum.map(& &1.who) |> Enum.uniq() |> Enum.sort(),
      kinds:
        groups
        |> Enum.map(&{&1.operation, kind_label(&1)})
        |> Enum.uniq_by(&elem(&1, 0))
        |> Enum.sort_by(&elem(&1, 1)),
      shown: Enum.filter(groups, &matches?(&1, filters))
    )
  end

  defp since(period) do
    case Enum.find(@periods, &(elem(&1, 0) == period)) do
      {_, _, nil} -> nil
      {_, _, days} -> NaiveDateTime.add(NaiveDateTime.utc_now(), -days, :day)
    end
  end

  # A kind's name: its title without a count ("Decided 6 questions" →
  # "Decided questions" would mislead; the title of one is clear).
  defp kind_label(%{operation: op, title: title, count: 1}) when op != "", do: title

  defp kind_label(%{operation: op}),
    do: op |> String.split(".") |> List.last() |> String.replace("_", " ") |> String.capitalize()

  defp matches?(group, filters) do
    (filters["who"] == "" or group.who == filters["who"]) and
      (filters["kind"] == "" or group.operation == filters["kind"]) and
      (filters["q"] == "" or text_matches?(group, String.downcase(filters["q"])))
  end

  defp text_matches?(group, q) do
    [
      group.source && group.source.title,
      group.who
      | Enum.map(group.galls, & &1.name) ++
          Enum.map(group.names ++ group.taxa, & &1.name) ++ Enum.map(group.facts, & &1.what)
    ]
    |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), q)))
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :periods, @periods)

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb href="/admin">Dashboard</:crumb>
          <:title>Changes</:title>
          <:description>
            What curators changed, newest first. See something wrong? Open it on the site, or edit it: Fact history is kept, so nothing is lost.
          </:description>
        </.page_header>

        <div class="flex flex-wrap items-end gap-3">
          <form id="changes-search" phx-change="filter" phx-submit="filter" class="w-80 max-w-full">
            <.search_field
              id="changes-q"
              name="q"
              value={@filters["q"]}
              label="Search"
              placeholder="A Gall, taxon, Source or value"
            />
          </form>
          <.filter_select
            id="changes-who"
            name="who"
            label="Curator"
            prompt="Every curator"
            value={@filters["who"]}
            options={Enum.map(@curators, &{&1, &1})}
            class="w-56"
            phx-change="filter"
          />
          <.filter_select
            id="changes-kind"
            name="kind"
            label="Kind"
            prompt="Every kind"
            value={@filters["kind"]}
            options={Enum.map(@kinds, fn {op, label} -> {label, op} end)}
            class="w-64"
            phx-change="filter"
          />
        </div>

        <.chip_nav label="Period">
          <:chip
            :for={{period, label, _days} <- @periods}
            patch={
              ~p"/admin/changes?#{Map.put(Map.reject(@filters, fn {_k, v} -> v == "" end), "period", period)}"
            }
            current={@filters["period"] == period}
          >
            {label}
          </:chip>
        </.chip_nav>

        <.section title="Changes" count={length(@shown)}>
          <.empty_state :if={@shown == []} title="No changes match" />
          <ol id="changes" class="flex flex-col divide-y divide-line">
            <.change_entry :for={g <- @shown} group={g} />
          </ol>
        </.section>
      </div>
    </Layouts.admin>
    """
  end
end
