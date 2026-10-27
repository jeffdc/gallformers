defmodule GallformersWeb.Admin.QueueLive.Index do
  @moduledoc """
  The review queue (`/admin/queue`, matter a856 Task 3): the open queue
  items of every package and the rename proposals, filtered by kind with
  the counts of each, each with its decision controls
  (`GallformersWeb.Admin.QueueLive.ItemDecision`); and the packages,
  newest first, filtered by status. Both lists are paged.

  The filters and pages are in the URL: `kind`, `page` (open items),
  `status`, `packages_page`.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.Admin.QueueLive.Components

  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias GallformersWeb.Admin.QueueLive.ItemDecision

  @items_page_size 20
  @packages_page_size 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Review queue")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(
       kind: parse_enum(params["kind"], QueueItem.kinds()),
       page: parse_page(params["page"]),
       status: parse_enum(params["status"], package_statuses()),
       packages_page: parse_page(params["packages_page"])
     )
     |> load_items()
     |> load_packages()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    status = parse_enum(status, package_statuses())

    {:noreply,
     push_patch(socket, to: queue_path(socket.assigns, status: status, packages_page: 1))}
  end

  @impl true
  def handle_info({ItemDecision, {:decided, decided}}, socket) do
    # The decided item stays in the list, showing its decision, until the
    # page is next loaded.
    items =
      Enum.map(socket.assigns.items, fn item ->
        if item.id == decided.id,
          do: %{decided | package: item.package, batch: item.batch},
          else: item
      end)

    {:noreply,
     socket
     |> assign(
       items: items,
       counts: Import.count_open_queue_items(),
       names: ItemDecision.names(items)
     )
     |> put_flash(:info, "Decision recorded.")}
  end

  defp load_items(socket) do
    %{kind: kind, page: page} = socket.assigns

    %{entries: items, total: total} =
      Import.list_open_queue_items(
        kind: kind,
        limit: @items_page_size,
        offset: (page - 1) * @items_page_size
      )

    assign(socket,
      items: items,
      items_total: total,
      names: ItemDecision.names(items),
      counts: Import.count_open_queue_items()
    )
  end

  defp load_packages(socket) do
    %{status: status, packages_page: page} = socket.assigns

    %{entries: packages, total: total} =
      Import.list_packages(
        status: status,
        limit: @packages_page_size,
        offset: (page - 1) * @packages_page_size
      )

    assign(socket, packages: packages, packages_total: total)
  end

  defp package_statuses,
    do:
      Enum.map(package_status_options(), fn {_label, value} -> String.to_existing_atom(value) end)

  defp parse_enum(value, allowed) when is_binary(value),
    do: Enum.find(allowed, &(Atom.to_string(&1) == value))

  defp parse_enum(_value, _allowed), do: nil

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_value), do: 1

  # The page's URL with `changes` applied; defaults are left out.
  defp queue_path(assigns, changes) do
    query =
      assigns
      |> Map.take([:kind, :page, :status, :packages_page])
      |> Map.merge(Map.new(changes))
      |> Enum.reject(fn {key, value} ->
        is_nil(value) or (key in [:page, :packages_page] and value == 1)
      end)
      |> Enum.sort()

    case query do
      [] -> ~p"/admin/queue"
      query -> ~p"/admin/queue?#{query}"
    end
  end

  defp total_pages(total, size), do: max(1, ceil(total / size))

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        items_page_size: @items_page_size,
        packages_page_size: @packages_page_size,
        kinds: QueueItem.kinds(),
        open_total: assigns.counts |> Map.values() |> Enum.sum()
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Review queue">
      <div class="space-y-8">
        <section class="space-y-4">
          <.header>
            Open items
            <:subtitle>
              What imports could not settle on their own, and Gall rename proposals.
              Items that hold a package's approval are decided here or on the package's page.
            </:subtitle>
          </.header>

          <div id="queue-kinds" class="flex flex-wrap gap-2">
            <.button
              id="kind-filter-all"
              patch={queue_path(assigns, kind: nil, page: 1)}
              shape="pill"
              size="sm"
              variant={if is_nil(@kind), do: "primary", else: "soft"}
            >
              All ({@open_total})
            </.button>
            <.button
              :for={kind <- @kinds}
              id={"kind-filter-#{kind}"}
              patch={queue_path(assigns, kind: kind, page: 1)}
              shape="pill"
              size="sm"
              variant={if @kind == kind, do: "primary", else: "soft"}
            >
              {ItemDecision.kind_label(kind)} ({Map.get(@counts, kind, 0)})
            </.button>
          </div>

          <div id="open-items" class="space-y-3">
            <p :if={@items == []} class="text-gray-500">Nothing is waiting for a decision.</p>
            <.live_component
              :for={item <- @items}
              module={ItemDecision}
              id={"item-decision-#{item.id}"}
              item={item}
              actor={@actor}
              names={@names}
              show_package={true}
            />
          </div>

          <.pagination
            :if={total_pages(@items_total, @items_page_size) > 1}
            page={@page}
            total_pages={total_pages(@items_total, @items_page_size)}
            total_items={@items_total}
            page_size={@items_page_size}
            on_page_change={fn page -> JS.patch(queue_path(assigns, page: page)) end}
          />
        </section>

        <section class="space-y-4">
          <.header>
            Packages
            <:subtitle>Delivered import packages, newest first.</:subtitle>
            <:actions>
              <.form for={%{}} id="package-status-form" phx-change="filter_status">
                <.input
                  type="select"
                  name="status"
                  prompt="All statuses"
                  options={package_status_options()}
                  value={@status && Atom.to_string(@status)}
                />
              </.form>
            </:actions>
          </.header>

          <div class="bg-white shadow rounded-lg overflow-x-auto">
            <.table id="packages" rows={@packages} row_id={&"package-#{&1.id}"}>
              <:col :let={package} label="Package">
                <.link
                  navigate={~p"/admin/queue/packages/#{package.id}"}
                  class="font-medium text-gf-maroon hover:underline"
                >
                  {package.key}
                </.link>
              </:col>
              <:col :let={package} label="Status"><.status_badge status={package.status} /></:col>
              <:col :let={package} label="Submitted by">{package.submitter_name}</:col>
              <:col :let={package} label="Received">
                {format_date(package.inserted_at, :short)}
              </:col>
            </.table>
            <p :if={@packages == []} class="p-4 text-gray-500">No packages.</p>
          </div>

          <.pagination
            :if={total_pages(@packages_total, @packages_page_size) > 1}
            page={@packages_page}
            total_pages={total_pages(@packages_total, @packages_page_size)}
            total_items={@packages_total}
            page_size={@packages_page_size}
            on_page_change={fn page -> JS.patch(queue_path(assigns, packages_page: page)) end}
          />
        </section>
      </div>
    </Layouts.admin>
    """
  end
end
