defmodule GallformersWeb.Layouts do
  @moduledoc """
  Layout components for Gallformers.

  Includes header with navigation, footer with links, and the main app layout.
  """
  use GallformersWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  @doc """
  Renders the Gallformers app layout with header, main content, and footer.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map,
    default: nil,
    doc: "the currently logged in user, if any"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col">
      <.site_header current_user={@current_user} />

      <main class="flex-1 pb-32">
        <div class="px-6 sm:px-10 lg:px-16 py-8">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.site_footer current_user={@current_user} />
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the site header with logo, navigation, and search.

  Named `site_header` to avoid conflict with CoreComponents.header/1.
  """
  attr :current_user, :map, default: nil, doc: "the currently logged in user, if any"
  attr :hide_admin_link, :boolean, default: false, doc: "whether to hide the admin link"

  def site_header(assigns) do
    nav_links = [
      %{href: "/id", label: "Identify"},
      %{href: "/explore", label: "Explore"}
    ]

    resource_links = [
      %{href: "/filterguide", label: "Filter Terms"},
      %{href: "/glossary", label: "Glossary"},
      %{href: "/articles", label: "Articles"},
      %{href: "/keys", label: "Keys"},
      %{href: "/analytics", label: "Analytics"}
    ]

    assigns =
      assigns
      |> assign(:nav_links, nav_links)
      |> assign(:resource_links, resource_links)

    ~H"""
    <header class="sticky top-0 z-50 bg-gf-sky-blue shadow-md">
      <nav class="px-3">
        <div class="flex items-center justify-between py-1">
          <%!-- Logo --%>
          <div class="flex-shrink-0">
            <a href="/" class="flex items-center">
              <img
                src="/branding/Wide Logo Versions/gallformers_logo_wide_color.png"
                alt="Gallformers logo: an oak gall wasp with a spherical oak gall and a white oak leaf"
                class="h-[70px]"
              />
            </a>
          </div>

          <%!-- Desktop Navigation --%>
          <div class="hidden md:flex md:items-center gap-1">
            <%!-- Admin link (when logged in) --%>
            <a
              :if={@current_user && !@hide_admin_link}
              href="/admin"
              class="px-2 text-lg font-medium hover:underline"
            >
              Admin
            </a>

            <a
              :for={link <- @nav_links}
              href={link.href}
              class="px-2 text-lg font-medium hover:underline"
            >
              {link.label}
            </a>

            <%!-- Search Form --%>
            <form action="/globalsearch" method="get" class="flex items-center">
              <input
                type="search"
                name="q"
                placeholder="Search"
                aria-label="Search"
                class="w-36 rounded-l-md border border-gf-maroon bg-white px-2 py-1 text-lg text-gray-900
                       placeholder:text-gray-400 focus:ring-2 focus:ring-gf-maroon focus:outline-none"
              />
              <button
                type="submit"
                class="rounded-r-md border border-gf-maroon bg-transparent px-2 py-1 text-lg
                       font-medium text-gf-maroon hover:bg-gf-maroon hover:text-white"
              >
                Search
              </button>
            </form>

            <%!-- Resources Dropdown --%>
            <div class="relative">
              <button
                type="button"
                phx-click={toggle_resources_menu()}
                class="flex items-center px-2 text-lg font-medium hover:underline"
                aria-expanded="false"
                aria-haspopup="true"
              >
                Resources
                <svg class="ml-1 h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 9l-7 7-7-7"
                  />
                </svg>
              </button>
              <div
                id="resources-menu"
                phx-click-away={hide_resources_menu()}
                class="hidden absolute right-0 z-10 mt-1 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5"
              >
                <a
                  :for={link <- @resource_links}
                  href={link.href}
                  class="block px-4 py-2 text-lg hover:bg-gray-100"
                >
                  {link.label}
                </a>
              </div>
            </div>
          </div>

          <%!-- Mobile menu button --%>
          <div class="flex md:hidden">
            <button
              type="button"
              phx-click={toggle_mobile_menu()}
              class="inline-flex items-center justify-center rounded-md p-2 text-gf-maroon
                     hover:bg-white/50 focus:outline-none focus:ring-2 focus:ring-gf-maroon"
              aria-expanded="false"
              aria-controls="mobile-menu"
            >
              <span class="sr-only">Open main menu</span>
              <%!-- Hamburger icon --%>
              <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"
                />
              </svg>
            </button>
          </div>
        </div>

        <%!-- Mobile menu (hidden by default, toggle with JS) --%>
        <div class="hidden md:hidden" id="mobile-menu">
          <div class="space-y-1 px-2 pb-3 pt-2">
            <%!-- Mobile Admin link (when logged in) --%>
            <a
              :if={@current_user && !@hide_admin_link}
              href="/admin"
              class="block rounded-md px-3 py-2 text-lg font-medium hover:bg-white/50"
            >
              Admin
            </a>

            <a
              :for={link <- @nav_links}
              href={link.href}
              class="block rounded-md px-3 py-2 text-lg font-medium hover:bg-white/50"
            >
              {link.label}
            </a>

            <%!-- Mobile Search --%>
            <form action="/globalsearch" method="get" class="px-3 py-2">
              <div class="flex">
                <input
                  type="search"
                  name="q"
                  placeholder="Search"
                  aria-label="Search"
                  class="flex-1 rounded-l-md border border-gf-maroon bg-white px-3 py-2 text-lg text-gray-900
                         placeholder:text-gray-400 focus:ring-2 focus:ring-gf-maroon focus:outline-none"
                />
                <button
                  type="submit"
                  class="rounded-r-md border border-gf-maroon bg-transparent px-3 py-2 text-lg
                         font-medium text-gf-maroon hover:bg-gf-maroon hover:text-white"
                >
                  Search
                </button>
              </div>
            </form>

            <%!-- Mobile Resources --%>
            <div class="border-t border-gf-maroon/30 pt-2">
              <span class="block px-3 py-2 text-xs font-semibold uppercase tracking-wider text-gf-maroon/70">
                Resources
              </span>
              <a
                :for={link <- @resource_links}
                href={link.href}
                class="block rounded-md px-3 py-2 text-lg font-medium hover:bg-white/50"
              >
                {link.label}
              </a>
            </div>
          </div>
        </div>
      </nav>
    </header>
    """
  end

  defp toggle_mobile_menu do
    JS.toggle(to: "#mobile-menu")
  end

  defp toggle_resources_menu do
    JS.toggle(to: "#resources-menu")
  end

  defp hide_resources_menu do
    JS.hide(to: "#resources-menu")
  end

  @doc """
  Renders the site footer with links and copyright.
  """
  attr :current_user, :map, default: nil, doc: "the currently logged in user, if any"

  def site_footer(assigns) do
    current_year = Date.utc_today().year

    assigns = assign(assigns, :current_year, current_year)

    ~H"""
    <footer class="fixed bottom-0 left-0 right-0 z-40 bg-gray-100 text-gf-maroon">
      <div class="flex items-center justify-between px-4 py-2">
        <%!-- User info or Login - left side (desktop only) --%>
        <%= if @current_user do %>
          <div class="hidden sm:flex items-center gap-2">
            <a
              href={
                if @current_user.nickname,
                  do: "/user/#{@current_user.nickname}",
                  else: "/admin/profile"
              }
              class="flex items-center gap-2 hover:opacity-80"
            >
              <img
                :if={@current_user.picture}
                class="h-6 w-6 rounded-full"
                src={@current_user.picture}
                alt=""
              />
              <span class="text-base font-medium text-gf-maroon">
                {Gallformers.Accounts.Auth0User.display_name(@current_user)}
              </span>
            </a>
            <a
              href="/auth/logout"
              class="text-base font-medium hover:underline"
            >
              Log Out
            </a>
          </div>
        <% else %>
          <a
            href="/auth/auth0"
            class="hidden sm:block text-base font-medium hover:underline"
          >
            Login
          </a>
        <% end %>

        <%!-- Copyright - center --%>
        <span class="hidden sm:block text-sm text-gray-600">
          &copy; {@current_year} Gallformers |
          <a
            href="https://creativecommons.org/licenses/by-nc-sa/4.0/"
            target="_blank"
            rel="noopener noreferrer"
            class="hover:underline"
          >
            CC BY-NC-SA 4.0
          </a>
        </span>

        <%!-- Navigation Links - right side (desktop) --%>
        <nav class="hidden sm:flex items-center gap-x-4" aria-label="Footer navigation">
          <a
            href="https://megachile.shinyapps.io/doycalc/"
            target="_blank"
            rel="noopener noreferrer"
            class="text-base font-medium hover:underline"
          >
            Phenology Tool
          </a>
          <a
            href="https://www.patreon.com/gallformers"
            target="_blank"
            rel="noopener noreferrer"
            class="text-base font-medium hover:underline"
          >
            Donate
          </a>
          <a href="/privacy" class="text-base font-medium hover:underline">
            Privacy
          </a>
          <a href="/about" class="text-base font-medium hover:underline">
            About
          </a>
        </nav>

        <%!-- Mobile menu button --%>
        <button
          type="button"
          phx-click={toggle_footer_menu()}
          class="sm:hidden p-2 text-gf-maroon ml-auto"
          aria-label="Toggle footer menu"
        >
          <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 6h16M4 12h16M4 18h16"
            />
          </svg>
        </button>
      </div>

      <%!-- Mobile footer menu (hidden by default) --%>
      <div
        class="hidden sm:hidden absolute bottom-full left-0 right-0 bg-gray-100 py-3 border-t border-gray-300"
        id="footer-menu"
      >
        <%= if @current_user do %>
          <a
            href={
              if @current_user.nickname, do: "/user/#{@current_user.nickname}", else: "/admin/profile"
            }
            class="flex items-center gap-2 py-1 px-4 mb-2 border-b border-gray-300 pb-2 hover:opacity-80"
          >
            <img
              :if={@current_user.picture}
              class="h-6 w-6 rounded-full"
              src={@current_user.picture}
              alt=""
            />
            <span class="text-base font-medium text-gf-maroon">
              {Gallformers.Accounts.Auth0User.display_name(@current_user)}
            </span>
          </a>
          <a
            href="/auth/logout"
            class="block text-base font-medium hover:underline py-1 px-4"
          >
            Log Out
          </a>
        <% else %>
          <a
            href="/auth/auth0"
            class="block text-base font-medium hover:underline py-1 px-4"
          >
            Login
          </a>
        <% end %>
        <a
          href="https://megachile.shinyapps.io/doycalc/"
          target="_blank"
          rel="noopener noreferrer"
          class="block text-base font-medium hover:underline py-1 px-4"
        >
          Phenology Tool
        </a>
        <a
          href="https://www.patreon.com/gallformers"
          target="_blank"
          rel="noopener noreferrer"
          class="block text-base font-medium hover:underline py-1 px-4"
        >
          Donate
        </a>
        <a href="/privacy" class="block text-base font-medium hover:underline py-1 px-4">
          Privacy
        </a>
        <a href="/about" class="block text-base font-medium hover:underline py-1 px-4">
          About
        </a>
        <%!-- Copyright in mobile menu --%>
        <span class="block text-sm text-gray-600 py-1 px-4 mt-2 border-t border-gray-300 pt-2">
          &copy; {@current_year} Gallformers |
          <a
            href="https://creativecommons.org/licenses/by-nc-sa/4.0/"
            target="_blank"
            rel="noopener noreferrer"
            class="hover:underline"
          >
            CC BY-NC-SA 4.0
          </a>
        </span>
      </div>
    </footer>
    """
  end

  defp toggle_footer_menu do
    JS.toggle(to: "#footer-menu")
  end

  @doc """
  Renders the admin layout with sidebar navigation.

  ## Examples

      <Layouts.admin flash={@flash} current_user={@current_user}>
        <h1>Admin Content</h1>
      </Layouts.admin>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, required: true, doc: "the currently logged in user"
  attr :page_title, :string, default: nil, doc: "the page title for the header"
  attr :public_url, :string, default: nil, doc: "URL to the public page for this item"

  slot :inner_block, required: true

  def admin(assigns) do
    admin_nav_links = [
      %{href: "/admin", label: "Dashboard", icon: "ph-house"},
      %{href: "/admin/galls", label: "Galls", icon: "gf-gall"},
      %{href: "/admin/hosts", label: "Hosts", icon: "gf-host"},
      %{href: "/admin/sources", label: "Sources", icon: "gf-source"},
      %{href: "/admin/images", label: "Images", icon: "ph-image"},
      %{href: "/admin/taxonomy", label: "Taxonomy", icon: "gf-taxon"},
      %{href: "/admin/glossary", label: "Glossary", icon: "gf-entry"},
      %{href: "/admin/articles", label: "Articles", icon: "ph-article"}
    ]

    superadmin_nav_links = [
      %{href: "/admin/places", label: "Places", icon: "gf-place"},
      %{href: "/admin/filter-terms", label: "Filter Terms", icon: "ph-funnel"}
    ]

    is_superadmin = Gallformers.Accounts.superadmin?(assigns.current_user)

    assigns =
      assigns
      |> assign(:admin_nav_links, admin_nav_links)
      |> assign(:superadmin_nav_links, superadmin_nav_links)
      |> assign(:is_superadmin, is_superadmin)

    ~H"""
    <div class="flex min-h-screen flex-col">
      <.site_header current_user={@current_user} hide_admin_link={true} />

      <main class="flex-1 pb-32">
        <%!-- Admin navigation links - always in same position --%>
        <div class="bg-white border-b border-gray-200 px-6 sm:px-10 lg:px-16 py-3">
          <div class="flex flex-wrap gap-4 items-center">
            <a
              :for={link <- @admin_nav_links}
              href={link.href}
              class="flex items-center gap-2 text-lg font-medium text-gf-maroon hover:text-gf-autumn"
            >
              <.icon name={link.icon} class="h-5 w-5" />
              {link.label}
            </a>

            <%!-- Super Admin links --%>
            <a
              :for={link <- @superadmin_nav_links}
              :if={@is_superadmin}
              href={link.href}
              class="flex items-center gap-2 text-lg font-medium text-gf-maroon hover:text-gf-autumn"
            >
              <.icon name={link.icon} class="h-5 w-5" />
              {link.label}
            </a>

            <%!-- My Profile link --%>
            <a
              href="/admin/profile"
              class="flex items-center gap-2 text-lg font-medium text-gf-maroon hover:text-gf-autumn ml-auto"
            >
              <.icon name="ph-user-circle" class="h-5 w-5" /> My Profile
            </a>
          </div>
        </div>

        <%!-- Small page title with view public page link --%>
        <div
          :if={@page_title}
          class="bg-gray-50 border-b border-gray-200 px-6 sm:px-10 lg:px-16 py-2"
        >
          <div class="flex items-center justify-between">
            <h1 class="text-lg font-semibold text-gf-maroon">{@page_title}</h1>
            <a
              :if={@public_url}
              href={@public_url}
              title="View public page"
              class="text-gf-maroon hover:text-gf-autumn transition-colors"
            >
              <.icon name="ph-eye" class="h-5 w-5" />
            </a>
          </div>
        </div>

        <%!-- Page content --%>
        <div class="px-6 sm:px-10 lg:px-16 py-8">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.site_footer current_user={@current_user} />
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} auto_dismiss={5000} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="ph-arrows-clockwise" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="ph-arrows-clockwise" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a back link for admin forms.

  ## Examples

      <Layouts.back_link navigate={~p"/admin/glossary"} label="Back to Glossary" />
  """
  attr :navigate, :string, required: true, doc: "the path to navigate to"
  attr :label, :string, required: true, doc: "the link text"

  def back_link(assigns) do
    ~H"""
    <div class="mb-6">
      <.link navigate={@navigate} class="hover:underline">
        <.icon name="ph-arrow-left" class="h-4 w-4 inline" /> {@label}
      </.link>
    </div>
    """
  end

  @doc """
  Standard layout for admin edit pages (Gall, Host, Source, etc.)

  Provides consistent structure with:
  - Back link
  - Card with gray header bar and maroon title
  - Intro text slot
  - Quick links slot (optional)
  - Main content area

  ## Example

      <Layouts.admin_edit_layout
        back_path={~p"/admin/galls"}
        back_label="Back to Galls"
        title="Edit Gall"
      >
        <:intro>
          This is for all the details about a Gall...
        </:intro>
        <:quick_links>
          <.link navigate={...}>Manage Images</.link>
        </:quick_links>

        <.form ...>
          ... form fields ...
        </.form>
      </Layouts.admin_edit_layout>
  """
  attr :back_path, :any, default: nil, doc: "path for the back link (nil to hide)"
  attr :back_label, :any, default: nil, doc: "text for the back link (without arrow)"
  attr :title, :string, required: true, doc: "card header title"

  slot :intro, doc: "intro text paragraph"
  slot :quick_links, doc: "quick links (shown in a gray box)"
  slot :inner_block, required: true, doc: "main form content"

  def admin_edit_layout(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <div :if={@back_path} class="mb-4">
        <.link navigate={@back_path} class="hover:underline text-sm">
          &larr; {@back_label}
        </.link>
      </div>

      <div class="bg-white border border-gray-200 rounded shadow-sm">
        <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
          <h4 class="text-lg font-semibold text-gf-maroon">{@title}</h4>
        </div>

        <div class="p-4">
          <p :if={@intro != []} class="text-sm text-gray-600 mb-4">
            {render_slot(@intro)}
          </p>

          <div :if={@quick_links != []} class="mb-4 p-3 bg-gray-50 border border-gray-200 rounded">
            <span class="text-sm font-medium text-gray-700 mr-3">Quick Links:</span>
            {render_slot(@quick_links)}
          </div>

          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end
end
