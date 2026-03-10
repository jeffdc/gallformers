defmodule GallformersWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard showing overview statistics and quick actions.
  """

  use GallformersWeb, :live_view

  alias Gallformers.{Galls, Images, Sources}
  alias Gallformers.Plants

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign_stats()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <%!-- Quick Actions Toolbar --%>
      <div class="relative">
        <p class="text-sm text-gray-500 absolute right-0 top-0.5">
          <a
            href="https://github.com/jeffdc/gallformers/blob/main/docs/ops/admin-onboarding.md"
            target="_blank"
            class="text-gf-maroon hover:underline"
          >
            Getting Started Guide
          </a>
          ·
          <a
            href="https://discord.com/channels/1178401400821125122/1180224727978094632"
            target="_blank"
            class="text-gf-maroon hover:underline"
          >
            Discord
          </a>
        </p>
        <h2 class="text-sm font-medium text-gray-500 mb-3">
          Quick Actions
        </h2>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <.action_card label="Create a New Gall" href="/admin/galls/new" icon="gf-gall" />
          <.action_card
            label="Add an Undescribed Gall"
            href="/admin/galls/undescribed"
            icon="gf-gall"
          />
          <.action_card label="Create a New Host" href="/admin/hosts/new" icon="gf-host" />
          <.action_card label="Create a New Source" href="/admin/sources/new" icon="gf-source" />
          <.action_card
            label="Manage Gall-Host Associations"
            href="/admin/gallhost"
            icon="ph-arrows-left-right"
            accent="blue"
          />
          <%!-- Gall range review disabled — not ready for production
          <.action_card
            label="Review Gall Ranges"
            href="/admin/gall-range"
            icon="ph-map-trifold"
            accent="blue"
          />
          --%>
          <.action_card
            label="Review Host Ranges"
            href="/admin/host-range"
            icon="ph-map-trifold"
            accent="blue"
          />
          <.action_card
            label="Bulk Add Species Descriptions from Sources"
            href="/admin/species-sources/add"
            icon="gf-source"
            accent="blue"
          />
          <.action_card
            label="Find and Edit Species-Source Mappings"
            href="/admin/species-sources/find"
            icon="ph-magnifying-glass"
            accent="blue"
          />
        </div>
      </div>

      <%!-- Two-column: Taxonomy + Content & Reference --%>
      <div class="mt-8 grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- Taxonomy --%>
        <div>
          <h2 class="text-sm font-medium text-gray-500 mb-3">
            Taxonomy
          </h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <.action_card
              label="Create a New Taxon"
              href="/admin/taxonomy/new"
              icon="gf-taxon"
              accent="amber"
            />
            <.action_card
              label="Section Species"
              href={~p"/admin/section"}
              icon="gf-taxon"
              accent="amber"
            />
          </div>
        </div>

        <%!-- Content & Reference --%>
        <div>
          <h2 class="text-sm font-medium text-gray-500 mb-3">
            Content & Reference
          </h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <.action_card
              label="Create a New Article"
              href="/admin/articles/new"
              icon="ph-article"
              accent="green"
            />
            <.action_card
              label="Create a New Key"
              href="/admin/keys/new"
              icon="ph-tree-structure"
              accent="green"
            />
            <.action_card
              label="Create a New Glossary Entry"
              href="/admin/glossary/new"
              icon="gf-entry"
              accent="green"
            />
            <.action_card
              label="Audit Images"
              href="/admin/image-audit"
              icon="ph-detective"
              accent="green"
              disabled={true}
              disabled_message="Disabled for a bit while Jeff looks into performance issues related to it."
            />
          </div>
        </div>
      </div>

      <%!-- Super Admin --%>
      <%= if Gallformers.Accounts.superadmin?(@current_user) do %>
        <div class="mt-6">
          <h2 class="text-sm font-medium text-gray-500 mb-3">Super Admin</h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.action_card
              label="Manage Users"
              href="/admin/users"
              icon="ph-users-three"
              accent="slate"
              small
            />
            <.action_card
              label="Filter Terms"
              href="/admin/filter-terms"
              icon="ph-funnel"
              accent="slate"
              small
            />
            <.action_card
              label="Live Dashboard"
              href="/admin/dashboard"
              icon="ph-chart-line"
              accent="slate"
              small
            />
          </div>
        </div>
      <% end %>

      <%!-- Stats --%>
      <div class="mt-8 grid grid-cols-2 sm:grid-cols-4 gap-3">
        <.stat_card title="Galls" value={@stats.gall_count} icon="gf-gall" href="/admin/galls" />
        <.stat_card title="Hosts" value={@stats.host_count} icon="gf-host" href="/admin/hosts" />
        <.stat_card
          title="Sources"
          value={@stats.source_count}
          icon="gf-source"
          href="/admin/sources"
        />
        <.stat_card title="Images" value={@stats.image_count} icon="ph-image" href="/admin/images" />
      </div>
    </Layouts.admin>
    """
  end

  # =================================================================
  # Private Components
  # =================================================================

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, required: true
  attr :value, :integer, default: nil

  defp stat_card(assigns) do
    ~H"""
    <a
      href={@href}
      class="flex items-center gap-3 rounded-lg bg-gray-50 border border-gray-200 px-4 py-3 hover:bg-white hover:shadow-md hover:-translate-y-0.5 transition-all group"
    >
      <div class="rounded-lg bg-gf-maroon/10 p-2">
        <.icon name={@icon} class="h-5 w-5 text-gf-maroon" />
      </div>
      <div>
        <div class="text-xs font-medium text-gray-500">{@title}</div>
        <div :if={@value} class="text-xl font-bold text-gray-800">{format_number(@value)}</div>
      </div>
    </a>
    """
  end

  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, required: true

  defp toolbar_button(assigns) do
    ~H"""
    <a
      href={@href}
      class="inline-flex items-center gap-2 rounded-full border border-gray-200 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gf-maroon hover:text-white hover:border-gf-maroon transition-colors group"
    >
      <.icon name={@icon} class="h-4 w-4 text-gf-maroon group-hover:text-white" />
      {@label}
    </a>
    """
  end

  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :accent, :string, default: "maroon"
  attr :small, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :disabled_message, :string, default: "Temporarily disabled"

  @accent_styles %{
    "maroon" => %{
      border: "border-l-gf-maroon/60",
      icon_bg: "bg-gf-maroon/10",
      icon_text: "text-gf-maroon group-hover:text-gf-autumn"
    },
    "blue" => %{
      border: "border-l-blue-400/60",
      icon_bg: "bg-blue-50",
      icon_text: "text-blue-600 group-hover:text-blue-800"
    },
    "amber" => %{
      border: "border-l-amber-400/60",
      icon_bg: "bg-amber-50",
      icon_text: "text-amber-600 group-hover:text-amber-800"
    },
    "green" => %{
      border: "border-l-green-400/60",
      icon_bg: "bg-green-50",
      icon_text: "text-green-600 group-hover:text-green-800"
    },
    "slate" => %{
      border: "border-l-slate-400/60",
      icon_bg: "bg-slate-100",
      icon_text: "text-slate-500 group-hover:text-slate-700"
    }
  }

  defp action_card(%{disabled: true} = assigns) do
    ~H"""
    <div class={[
      "flex items-center rounded-lg border border-gray-200 border-l-4 border-l-gray-300 bg-gray-50",
      "opacity-60 cursor-not-allowed",
      if(@small, do: "gap-2 p-3", else: "gap-3 p-4")
    ]}>
      <div class={["rounded-lg flex-shrink-0 bg-gray-100", if(@small, do: "p-1.5", else: "p-2")]}>
        <.icon name={@icon} class={[if(@small, do: "h-4 w-4", else: "h-5 w-5"), "text-gray-400"]} />
      </div>
      <div class="flex flex-col">
        <span class={["font-medium text-gray-400", if(@small, do: "text-sm", else: "text-lg")]}>
          {@label}
        </span>
        <span class="text-xs text-gray-400">{@disabled_message}</span>
      </div>
    </div>
    """
  end

  defp action_card(assigns) do
    style = @accent_styles[assigns.accent]
    assigns = assign(assigns, :style, style)

    ~H"""
    <a
      href={@href}
      class={[
        "flex items-center rounded-lg border border-gray-200 border-l-4 bg-white",
        "hover:shadow-md hover:-translate-y-0.5 transition-all group",
        @style.border,
        if(@small, do: "gap-2 p-3", else: "gap-3 p-4")
      ]}
    >
      <div class={["rounded-lg flex-shrink-0", @style.icon_bg, if(@small, do: "p-1.5", else: "p-2")]}>
        <.icon name={@icon} class={[if(@small, do: "h-4 w-4", else: "h-5 w-5"), @style.icon_text]} />
      </div>
      <span class={[
        "font-medium text-gray-900 group-hover:text-gf-maroon",
        if(@small, do: "text-sm", else: "text-lg")
      ]}>
        {@label}
      </span>
    </a>
    """
  end

  defp assign_stats(socket) do
    stats = %{
      gall_count: Galls.count_galls(),
      host_count: Plants.count_hosts(),
      source_count: Sources.count_sources(),
      image_count: Images.count_images()
    }

    assign(socket, :stats, stats)
  end
end
