defmodule GallformersWeb.Admin.DashboardLive do
  @moduledoc """
  The admin dashboard (design system, matter bc0d): the Sources to review
  first (the review index's rows, `ReviewLive.Loader`), then the curators'
  recent changes (`Gallformers.Catalog.changes/1`, the same `change_entry`
  as the Changes page). The rail: Find and Create, and Site for a
  superadmin.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Accounts, Catalog, Sources, Taxa}
  alias GallformersWeb.Admin.ReviewLive.Loader

  @recent 8

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Dashboard",
       current_user: session["current_user"],
       waiting:
         List.wrap(Loader.renames_row()) ++ Enum.sort_by(Loader.sources(), & &1.to_decide, :desc),
       changes: Catalog.changes(limit: 60) |> Enum.take(@recent),
       stats: %{
         galls: Catalog.count_galls(),
         hosts: Taxa.count_plants(),
         sources: Sources.count_sources()
       }
     )}
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

            <.section id="recent-changes-section" title="Recent changes">
              <:aside><.link href="/admin/changes">All changes</.link></:aside>
              <p :if={@changes == []} class="text-ui text-muted">No changes yet.</p>
              <ol id="recent-changes" class="flex flex-col divide-y divide-line">
                <.change_entry :for={g <- @changes} group={g} />
              </ol>
            </.section>
          </div>

          <.rail width={:narrow}>
            <.panel id="find" title="Find">
              <div class="flex flex-col gap-2">
                <.link_tile href="/galls" icon="gf-gall" name="Galls">
                  {format_number(@stats.galls)}
                </.link_tile>
                <.link_tile href="/admin/sources" icon="gf-source" name="Sources">
                  {format_number(@stats.sources)}
                </.link_tile>
                <.link_tile href="/admin/taxonomy" icon="gf-taxon" name="Taxonomy">
                  {format_number(@stats.hosts)} host plants
                </.link_tile>
                <.link_tile href="/admin/host-range" icon="ph-map-trifold" name="Host ranges">
                  Where hosts grow
                </.link_tile>
              </div>
            </.panel>
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
