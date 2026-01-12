defmodule GallformersWeb.AdminDashboardLive do
  @moduledoc """
  Admin dashboard showing overview statistics and quick actions.
  """

  use GallformersWeb, :live_view

  alias Gallformers.Repo

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Admin Dashboard")
      |> assign_stats()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Dashboard">
      <%!-- Stats Grid --%>
      <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
        <.stat_card
          title="Species"
          value={@stats.species_count}
          icon="hero-bug-ant"
          href="/admin/species"
        />
        <.stat_card title="Hosts" value={@stats.host_count} icon="hero-leaf" href="/admin/hosts" />
        <.stat_card
          title="Sources"
          value={@stats.source_count}
          icon="hero-book-open"
          href="/admin/sources"
        />
        <.stat_card title="Images" value={@stats.image_count} icon="hero-photo" href="/admin/images" />
      </div>

      <%!-- Quick Actions --%>
      <div class="mt-8">
        <h2 class="text-lg font-medium text-gray-900 mb-4">Quick Actions</h2>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.action_card
            title="Add New Species"
            description="Create a new gall-forming species entry"
            href="/admin/species/new"
            icon="hero-plus-circle"
          />
          <.action_card
            title="Add New Host"
            description="Add a new host plant to the database"
            href="/admin/hosts/new"
            icon="hero-plus-circle"
          />
          <.action_card
            title="Add New Source"
            description="Add a new reference or citation"
            href="/admin/sources/new"
            icon="hero-plus-circle"
          />
          <.action_card
            title="Upload Images"
            description="Upload images for species or hosts"
            href="/admin/images/upload"
            icon="hero-arrow-up-tray"
          />
          <.action_card
            title="Manage Taxonomy"
            description="Edit taxonomic classifications"
            href="/admin/taxonomy"
            icon="hero-folder-tree"
          />
          <.action_card
            title="Edit Glossary"
            description="Add or edit glossary terms"
            href="/admin/glossary"
            icon="hero-book-open"
          />
        </div>
      </div>

      <%!-- Recent Activity placeholder --%>
      <div class="mt-8">
        <h2 class="text-lg font-medium text-gray-900 mb-4">Welcome</h2>
        <div class="bg-white rounded-lg border border-gray-200 p-6">
          <p class="text-gray-600">
            Welcome to the Gallformers admin panel. Use the sidebar navigation or quick actions above
            to manage species, hosts, sources, and other content.
          </p>
          <p class="text-gray-600 mt-4">
            <strong>Note:</strong> Admin functionality is being migrated from v1. Some features may
            not yet be available.
          </p>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <a
      href={@href}
      class="block bg-white rounded-lg border border-gray-200 p-5 hover:shadow-md transition-shadow"
    >
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <div class="rounded-md bg-gf-maroon/10 p-3">
            <.icon name={@icon} class="h-6 w-6 text-gf-maroon" />
          </div>
        </div>
        <div class="ml-5 w-0 flex-1">
          <dl>
            <dt class="text-sm font-medium text-gray-500 truncate">{@title}</dt>
            <dd class="text-2xl font-semibold text-gray-900">{format_number(@value)}</dd>
          </dl>
        </div>
      </div>
    </a>
    """
  end

  defp action_card(assigns) do
    ~H"""
    <a
      href={@href}
      class="block bg-white rounded-lg border border-gray-200 p-5 hover:shadow-md transition-shadow group"
    >
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <.icon name={@icon} class="h-6 w-6 text-gf-maroon group-hover:text-gf-autumn" />
        </div>
        <div class="ml-4">
          <h3 class="text-base font-medium text-gray-900 group-hover:text-gf-maroon">{@title}</h3>
          <p class="mt-1 text-sm text-gray-500">{@description}</p>
        </div>
      </div>
    </a>
    """
  end

  defp assign_stats(socket) do
    stats = %{
      species_count: count_table("species"),
      host_count: count_table("host"),
      source_count: count_table("source"),
      image_count: count_table("image")
    }

    assign(socket, :stats, stats)
  end

  defp count_table(table_name) do
    query = "SELECT COUNT(*) FROM #{table_name}"

    case Repo.query(query) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(_), do: "0"
end
