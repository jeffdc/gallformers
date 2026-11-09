defmodule GallformersWeb.Admin.ReviewLive.Renames do
  @moduledoc """
  The Gall rename proposals (`/admin/review/renames`, `6611` Task 8): the
  `:gall_rename` queue items a change in the tree makes
  (`Gallformers.Import.GallRenames`), which belong to no package, so to no
  Source. The Sources list leads here while any is open.

  They are one section of the rows a Source's page has
  (`GallformersWeb.Admin.ReviewLive.ItemRow`): Accept renames the Gall,
  "Keep the name" fixes it. A name another Gall already has is flagged and
  has no proposal; accepting it is refused, with the reason in the row.
  After each decision the page loads again; "Show decided" lists the
  decided ones too.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents

  alias Gallformers.Catalog
  alias GallformersWeb.Admin.Review.Questions
  alias GallformersWeb.Admin.ReviewLive.ItemRow
  alias GallformersWeb.Admin.ReviewLive.Loader

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Gall rename proposals",
       section: Questions.section(:gall_rename, nil),
       show_decided: false,
       closed: false
     )
     |> load()}
  end

  @impl true
  def handle_event("show_decided", _params, socket),
    do: {:noreply, socket |> assign(show_decided: not socket.assigns.show_decided) |> load()}

  def handle_event("toggle_section", _params, socket),
    do: {:noreply, assign(socket, closed: not socket.assigns.closed)}

  @impl true
  def handle_info({ItemRow, {:decided, _item}}, socket),
    do: {:noreply, socket |> put_flash(:info, "Decision recorded.") |> load()}

  def handle_info({ItemRow, {:undone, _item}}, socket),
    do: {:noreply, socket |> put_flash(:info, "Decision undone.") |> load()}

  def handle_info({ItemRow, {:proposal, _item}}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    status = if socket.assigns.show_decided, do: :all, else: :open

    assign(socket,
      entries: Loader.renames(status: status),
      definitions: Catalog.trait_definitions()
    )
  end

  defp count_text([]), do: "· all decided"
  defp count_text(open), do: "· #{length(open)} to decide"

  @impl true
  def render(assigns) do
    open = Enum.filter(assigns.entries, &(&1.item.status == :open))
    assigns = assign(assigns, open: open)

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-block">
        <.page_header>
          <:crumb navigate={~p"/admin/review"}>Sources to review</:crumb>
          <:title>Gall rename proposals</:title>
          <:description>
            Renaming or moving a taxon changes the names of the Galls named after it. They come
            from no Source, so nothing here holds an approval.
          </:description>
        </.page_header>

        <div id="renames-head" class="flex flex-wrap items-center gap-2">
          <span id="progress" class="text-ui">{length(@open)} to decide</span>
          <span class="flex-1"></span>
          <.button
            id="show-decided"
            phx-click="show_decided"
            size="sm"
            variant={if @show_decided, do: "primary", else: "secondary"}
          >
            Show decided
          </.button>
        </div>

        <div id="review-sections">
          <.empty_state :if={@entries == []} title="No Gall rename proposal is waiting." />
          <.review_section
            :if={@entries != []}
            id={"section-#{@section.id}"}
            section={Atom.to_string(@section.id)}
            title={@section.title}
            count={count_text(@open)}
            explanation={@section.explanation}
            holds={@section.holds}
            holds_approval={@section.holds_approval}
            done={@open == []}
            closed={@closed}
            on_toggle="toggle_section"
          >
            <.live_component
              :for={entry <- @entries}
              module={ItemRow}
              id={"item-row-#{entry.item.id}"}
              entry={entry}
              actor={@actor}
              definitions={@definitions}
              source_name="The tree"
            />
          </.review_section>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
