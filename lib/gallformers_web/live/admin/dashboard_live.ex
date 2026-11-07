defmodule GallformersWeb.Admin.DashboardLive do
  @moduledoc """
  The admin dashboard (design system, matter bc0d): the Sources to review
  first (the review index's rows, `ReviewLive.Loader`, with the Gall rename
  proposals and the questions merges left), then Your changes (the
  curator's tray, `Gallformers.Curation`, kept up to date), then the
  curators' recent changes (`Gallformers.Catalog.changes/1`, the same
  `change_entry` as the Changes page, kept up to date through
  `Gallformers.Audit.ChangeLog.subscribe/0`). The rail: Create, and Site for a
  superadmin. (Find is gone: the command palette finds anything, and Galls
  and plants are edited on their pages.)
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Accounts, Catalog, Curation}
  alias Gallformers.Audit.ChangeLog
  alias GallformersWeb.Admin.ReviewLive.Loader
  alias GallformersWeb.Live.UserAuth

  @recent 8

  @impl true
  def mount(_params, session, socket) do
    curator = UserAuth.curator(session["current_user"])

    if connected?(socket) do
      if curator, do: Curation.subscribe(curator)
      ChangeLog.subscribe()
    end

    {:ok,
     socket
     |> assign(
       curator: curator,
       page_title: "Dashboard",
       current_user: session["current_user"],
       waiting:
         List.wrap(Loader.renames_row()) ++
           List.wrap(Loader.merge_conflicts_row()) ++
           Enum.sort_by(Loader.sources(), & &1.to_decide, :desc)
     )
     |> load_changes()
     |> load_tray()}
  end

  # The curator's tray changed: Your changes. Changes were recorded (the
  # tray applied, the import job took a package on): Recent changes.
  @impl true
  def handle_info({:change_set, _change}, socket), do: {:noreply, load_tray(socket)}
  def handle_info({:change_log, :changed}, socket), do: {:noreply, load_changes(socket)}

  defp load_changes(socket),
    do: assign(socket, changes: Catalog.changes(limit: 60) |> Enum.take(@recent))

  defp load_tray(socket) do
    items =
      case socket.assigns.curator && Curation.open_set(socket.assigns.curator) do
        nil -> []
        set -> set.items
      end

    assign(socket, tray: items)
  end

  defp subject_path({:gall, id}), do: "/gall/#{id}?edit"
  defp subject_path({:plant, id}), do: "/host/#{id}?edit"

  defp state_chip(assigns) do
    ~H"""
    <.chip :if={@item.state == :in_tray} variant={:info} size="sm">In your tray</.chip>
    <.chip :if={@item.state == :waiting} variant={:warn} size="sm">Waiting to apply</.chip>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Dashboard</:title>
          <:action>
            <.button
              href="https://github.com/jeffdc/gallformers/blob/main/docs/domain/admin-onboarding.md"
              target="_blank"
              variant="ghost"
              size="sm"
              icon="ph-book-open"
            >
              Getting started
            </.button>
            <.button
              href="https://discord.com/channels/1178401400821125122/1180224727978094632"
              target="_blank"
              variant="ghost"
              size="sm"
              icon="ph-chat-circle"
            >
              Discord
            </.button>
          </:action>
        </.page_header>

        <div class="gf-with-rail">
          <div class="flex min-w-0 flex-col gap-section">
            <.section id="review-queue-section" title="Sources to review" count={length(@waiting)}>
              <:aside><.link href="/admin/review">Open the review</.link></:aside>
              <.data_table id="review-queue" rows={@waiting} row_id={&"review-#{&1.id}"}>
                <:col :let={s} label="Source" grow wrap>
                  <.link href={s.path}>{s.title}</.link>
                </:col>
                <:col :let={s} label="Year" numeric hide_below={:md}>{s.year}</:col>
                <:col :let={s} label="To decide" numeric>{s.to_decide}</:col>
                <:col :let={s} label="Status" hide_below={:md}>
                  <.chip variant={if(s.ready, do: :ok, else: :warn)}>{s.status}</.chip>
                </:col>
                <:empty>Nothing waiting for review.</:empty>
              </.data_table>
            </.section>

            <.section id="your-changes-section" title="Your changes" count={length(@tray)}>
              <:aside :if={@tray != []}>
                Review and apply from the tray at the foot of the screen
              </:aside>
              <.data_table id="your-changes" rows={@tray} row_id={&"your-change-#{&1.id}"}>
                <:col :let={i} label="Change" grow wrap>{i.text}</:col>
                <:col :let={i} label="On">
                  <.link href={subject_path(i.subject)}><.taxon_name name={i.subject_name} /></.link>
                </:col>
                <:col :let={i} label="State"><.state_chip item={i} /></:col>
                <:empty>
                  Your tray is empty. Turn on Edit on a Gall's or a plant's page to make a change.
                </:empty>
              </.data_table>
            </.section>

            <.section id="recent-changes-section" title="Recent changes">
              <:aside><.link href="/admin/changes">All changes</.link></:aside>
              <p :if={@changes == []} class="text-ui text-muted">No changes yet.</p>
              <ol id="recent-changes" class="flex flex-col divide-y divide-line">
                <.change_entry :for={g <- @changes} group={g} />
              </ol>
            </.section>
          </div>

          <.rail width={:narrow}>
            <.panel id="create" title="Create">
              <ul class="flex flex-col gap-1.5 text-ui">
                <li><.link href="/admin/taxonomy/new">New taxon</.link></li>
                <li><.link href="/admin/articles/new">New article</.link></li>
                <li><.link href="/admin/keys/new">New key</.link></li>
                <li><.link href="/admin/glossary/new">New glossary entry</.link></li>
              </ul>
            </.panel>
            <.panel :if={Accounts.superadmin?(@current_user)} id="site" title="Site">
              <ul class="flex flex-col gap-1.5 text-ui">
                <li><.link href="/admin/users">Users</.link></li>
                <li><.link href="/admin/vocabulary">Vocabulary</.link></li>
                <li><.link href="/admin/jobs">Jobs</.link></li>
                <li><.link href="/admin/dashboard">Live dashboard</.link></li>
              </ul>
            </.panel>
          </.rail>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
