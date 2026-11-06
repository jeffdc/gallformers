defmodule GallformersWeb.Admin.GlossaryLive.Index do
  @moduledoc """
  The glossary admin's list (design system, matter bc0d; the admin list
  pattern): every entry, filtered by its word, each linked to its form and
  to where it shows on the site; New entry. Updates live as entries change.
  Deleting is on an entry's form.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Glossaries

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Glossaries.subscribe()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Glossary")
      |> assign(:search_query, "")
      |> load_glossary()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Glossary")
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> load_glossary()

    {:noreply, socket}
  end

  @impl true
  def handle_info({event, _entry}, socket)
      when event in [:glossary_created, :glossary_updated, :glossary_deleted] do
    {:noreply, load_glossary(socket)}
  end

  defp load_glossary(socket) do
    entries =
      case socket.assigns.search_query do
        "" -> Glossaries.list_glossary()
        query -> Glossaries.search_glossary(query)
      end

    assign(socket, :entries, entries)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Glossary</:title>
          <:meta label="Entries">{length(@entries)}</:meta>
          <:description>
            Terms linked automatically wherever they appear in descriptions and notes across the site.
          </:description>
          <:action>
            <.button navigate={~p"/admin/glossary/new"} variant="primary" icon="ph-plus">
              New entry
            </.button>
          </:action>
        </.page_header>

        <form id="glossary-search-form" phx-change="search" phx-submit="search" class="max-w-md">
          <.search_field
            id="glossary-search"
            name="query"
            value={@search_query}
            label="Filter the glossary"
            placeholder="Filter the terms"
          />
        </form>

        <.data_table id="glossary-entries" rows={@entries} row_id={&"entry-#{&1.id}"} compact>
          <:col :let={entry} label="Word">
            <.link navigate={~p"/admin/glossary/#{entry.id}"} class="font-semibold">
              {entry.word}
            </.link>
          </:col>
          <:col :let={entry} label="Definition" grow>
            <span class="text-ink-2">{entry.definition}</span>
          </:col>
          <:col :let={entry} label="On the site">
            <.link
              href={"/glossary##{String.downcase(entry.word)}"}
              title="Where it shows on the site"
            >
              View ↗
            </.link>
          </:col>
          <:empty>No entries match.</:empty>
        </.data_table>
      </div>
    </Layouts.admin>
    """
  end
end
