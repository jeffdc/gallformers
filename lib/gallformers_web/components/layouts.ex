defmodule GallformersWeb.Layouts do
  @moduledoc """
  Layout components for Gallformers.

  Includes header with navigation, footer with links, and the main app layout.
  """
  use GallformersWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  @doc """
  The site shell: the public page frame (docs/design-system/components.md,
  `site_shell`).

  A 56px sticky header, the page content in the page column at Reading
  density, and a footer at the end of the page (never fixed).

  ## Examples

      <Layouts.app flash={@flash} current_user={@current_user}>
        <.page_header><:title>Glossary</:title></.page_header>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map,
    default: nil,
    doc: "the currently logged in user, if any"

  slot :subheader,
    doc: "optional content rendered between header and main (e.g., region scope widget)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-paper">
      <.site_header current_user={@current_user} />

      {render_slot(@subheader)}

      <main class="flex-1">
        <div class="mx-auto w-full max-w-page px-4 py-6 sm:px-page-x">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.site_footer />
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @browse_links [
    %{href: "/galls", label: "Galls"},
    %{href: "/hosts", label: "Hosts"},
    %{href: "/places", label: "Places"}
  ]

  @resource_links [
    %{href: "/filterguide", label: "Filter Terms"},
    %{href: "/glossary", label: "Glossary"},
    %{href: "/articles", label: "Articles"},
    %{href: "/keys", label: "Keys"},
    %{href: "/analytics", label: "Analytics"}
  ]

  @doc """
  The site header: wordmark, navigation, search and the account link.
  """
  attr :current_user, :map, default: nil, doc: "the currently logged in user, if any"

  def site_header(assigns) do
    assigns =
      assigns
      |> assign(:browse_links, @browse_links)
      |> assign(:resource_links, @resource_links)

    ~H"""
    <header class="sticky top-0 z-50 bg-sky" data-sticky-chrome>
      <nav class="mx-auto flex h-16 max-w-page items-center gap-4 px-4 sm:px-page-x lg:gap-6">
        <a href="/" class="flex shrink-0 items-center" aria-label="Gallformers home">
          <img
            src="/branding/Wide Logo Versions/gallformers_logo_wide_color.png"
            alt="Gallformers logo: an oak gall wasp with a spherical oak gall and a white oak leaf"
            class="gf-only-light h-12 w-auto"
          />
          <img
            src="/branding/Wide Logo Versions/gallformers_logo_wide_white.png"
            alt="Gallformers logo: an oak gall wasp with a spherical oak gall and a white oak leaf"
            class="gf-only-dark h-12 w-auto"
          />
        </a>

        <div class="ml-auto hidden items-center gap-1 font-brand text-body md:flex">
          <a
            href="/id"
            class="mr-2 inline-flex h-9 items-center gap-1.5 rounded-ctl bg-brand-fill px-3 font-semibold text-on-fill hover:bg-brand-hover hover:text-on-fill hover:no-underline"
          >
            <.icon name="ph-magnifying-glass-plus" class="size-4" /> Identify
          </a>
          <.menu id="browse-menu" label="Browse" trigger_class={nav_trigger()}>
            <:item :for={link <- @browse_links} navigate={link.href}>{link.label}</:item>
          </.menu>
          <.menu id="resources-menu" label="Resources" trigger_class={nav_trigger()}>
            <:item :for={link <- @resource_links} navigate={link.href}>{link.label}</:item>
          </.menu>
        </div>

        <.palette_trigger class="hidden w-56 md:flex lg:w-72" />

        <div class="hidden md:block">
          <.account current_user={@current_user} />
        </div>

        <.palette_trigger compact class="ml-auto md:hidden" />
        <.theme_switch class="md:ml-0" />

        <button
          type="button"
          phx-click={JS.toggle(to: "#mobile-menu")}
          class="inline-flex size-10 items-center justify-center rounded-ctl text-ink md:hidden"
          aria-controls="mobile-menu"
          aria-expanded="false"
          aria-label="Open menu"
        >
          <.icon name="ph-list" class="size-6" />
        </button>
      </nav>

      <div id="mobile-menu" class="hidden border-t border-line bg-surface px-4 pb-4 md:hidden">
        <div class="mt-2 flex flex-col font-brand text-body">
          <a href="/id" class="py-2 font-semibold text-brand">Identify a gall</a>
          <span class="pt-3 text-meta font-semibold text-muted">
            Browse
          </span>
          <a :for={link <- @browse_links} href={link.href} class="py-2 text-ink">{link.label}</a>
          <span class="pt-3 text-meta font-semibold text-muted">
            Resources
          </span>
          <a :for={link <- @resource_links} href={link.href} class="py-2 text-ink">{link.label}</a>
          <div class="mt-3 border-t border-line pt-3">
            <.account current_user={@current_user} stacked />
          </div>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  The conn the root layout renders the command palette with: outside the
  page's live session. A request routed to a `live` page carries that
  live session's on_mount hooks (`conn.private[:phoenix_live_view]`), so
  `live_render/3` would run them for the palette too, and a page's access
  check (a superadmin's, say) would stop the palette on the 403 it renders.
  """
  def outside_live_session(%Plug.Conn{} = conn),
    do: %{conn | private: Map.delete(conn.private, :phoenix_live_view)}

  @doc """
  Opens the command palette (`GallformersWeb.PaletteLive`): a button that
  looks like a search field ("Search Gallformers" and its key), or with
  `compact` a search icon (phones). It dispatches `gf:open-palette`.
  """
  attr :compact, :boolean, default: false
  attr :class, :any, default: nil, doc: "layout only"

  def palette_trigger(assigns) do
    ~H"""
    <button
      type="button"
      data-palette-trigger
      phx-click={JS.dispatch("gf:open-palette")}
      aria-label="Search Gallformers"
      class={[
        if(@compact,
          do: "inline-flex size-10 items-center justify-center rounded-ctl text-ink",
          else:
            "h-ctl items-center gap-2 rounded-ctl border border-line-strong bg-surface px-3 text-ui text-muted hover:border-brand"
        ),
        @class
      ]}
    >
      <.icon name="ph-magnifying-glass" class={if(@compact, do: "size-6", else: "size-4")} />
      <span :if={!@compact} class="flex-1 text-left">Search Gallformers</span>
      <kbd :if={!@compact} class="gf-kbd">/</kbd>
    </button>
    """
  end

  @theme_options [
    {"system", "gf-contrast", "Match my device"},
    {"light", "gf-sun", "Light"},
    {"dark", "gf-moon", "Dark"}
  ]

  @doc """
  The theme switch: an icon button (showing the current choice, from
  `data-theme-choice` on `<html>`) opening System, Light and Dark. A choice
  dispatches `gf:set-theme`; `assets/js/theme.js` saves and applies it and
  checks its option. LiveView leaves it alone (`phx-update="ignore"`), so
  the checked option survives re-renders.
  """
  attr :class, :any, default: nil, doc: "layout only"

  def theme_switch(assigns) do
    assigns = assign(assigns, :options, @theme_options)

    ~H"""
    <div
      id="theme-menu"
      class={["relative", @class]}
      phx-update="ignore"
      phx-window-keydown={hide_theme_menu()}
      phx-key="Escape"
    >
      <button
        type="button"
        aria-label="Theme"
        title="Theme"
        aria-haspopup="true"
        aria-expanded="false"
        aria-controls="theme-menu-list"
        phx-click={
          JS.toggle(to: "#theme-menu-list")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#theme-menu > button")
        }
        class="inline-flex size-10 items-center justify-center rounded-ctl text-ink hover:bg-surface/40"
      >
        <span :for={{choice, icon, _} <- @options} class="gf-theme-icon" data-for={choice}>
          <.icon name={icon} class="size-5" />
        </span>
      </button>
      <div
        id="theme-menu-list"
        class="gf-menu hidden mt-1 right-0"
        role="menu"
        aria-label="Theme"
        phx-click-away={hide_theme_menu()}
      >
        <button
          :for={{choice, icon, label} <- @options}
          type="button"
          role="menuitemradio"
          aria-checked="false"
          data-theme-option={choice}
          phx-click={JS.dispatch("gf:set-theme", detail: %{theme: choice}) |> hide_theme_menu()}
          class="flex items-center gap-2"
        >
          <.icon name={icon} class="size-4" /> {label}
          <.icon name="ph-check" class="gf-theme-check ml-auto size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp hide_theme_menu(js \\ %JS{}) do
    js
    |> JS.hide(to: "#theme-menu-list")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#theme-menu > button")
  end

  defp nav_trigger,
    do:
      "inline-flex items-center gap-1 px-2 font-brand text-body font-medium text-ink cursor-pointer"

  # Log in, or the signed-in user's menu (Admin, profile, Log out).
  attr :current_user, :map, default: nil
  attr :stacked, :boolean, default: false

  defp account(%{current_user: nil} = assigns) do
    ~H"""
    <a href="/auth/auth0" class="font-medium text-link">Log in</a>
    """
  end

  defp account(%{stacked: true} = assigns) do
    ~H"""
    <div class="flex flex-col">
      <a href="/admin" class="py-2 text-ink">Admin</a>
      <a href={profile_path(@current_user)} class="py-2 text-ink">
        {Gallformers.Accounts.Auth0User.display_name(@current_user)}
      </a>
      <a href="/auth/logout" class="py-2 text-ink">Log out</a>
    </div>
    """
  end

  defp account(assigns) do
    ~H"""
    <.menu
      id="account-menu"
      label={Gallformers.Accounts.Auth0User.display_name(@current_user)}
      trigger_class={nav_trigger()}
    >
      <:item href="/admin">Admin</:item>
      <:item href={profile_path(@current_user)}>My profile</:item>
      <:item href="/auth/logout">Log out</:item>
    </.menu>
    """
  end

  defp profile_path(%{nickname: nickname}) when is_binary(nickname), do: "/user/#{nickname}"
  defp profile_path(_user), do: "/admin/profile"

  @doc """
  The site footer: at the end of the page, never fixed.
  """
  def site_footer(assigns) do
    assigns = assign(assigns, :current_year, Date.utc_today().year)

    ~H"""
    <footer class="mt-section border-t border-line bg-surface-2">
      <div class="mx-auto flex max-w-page flex-wrap items-center gap-x-6 gap-y-2 px-4 py-5 text-meta sm:px-page-x">
        <nav class="flex flex-wrap gap-x-5 gap-y-1" aria-label="Footer">
          <a href="https://megachile.shinyapps.io/doycalc/" target="_blank" rel="noopener noreferrer">
            Phenology Tool ↗
          </a>
          <a href="https://www.patreon.com/gallformers" target="_blank" rel="noopener noreferrer">
            Donate ↗
          </a>
          <a href="/privacy">Privacy</a>
          <a href="/about">About</a>
        </nav>
        <span class="text-muted sm:ml-auto">
          &copy; {@current_year} Gallformers ·
          <a
            href="https://creativecommons.org/licenses/by-nc-sa/4.0/"
            target="_blank"
            rel="noopener noreferrer"
          >
            CC BY-NC-SA 4.0
          </a>
        </span>
      </div>
    </footer>
    """
  end

  @doc """
  The admin shell (docs/design-system/components.md, `admin_shell`).

  A sidebar of admin sections, a 44px top bar, and the page at Working
  density. A page not yet on `page_header` passes `page_title` (or the
  `page_title_html` slot) and the shell renders it as the page's `h1`;
  a page with its own `page_header` passes neither.

  ## Examples

      <Layouts.admin flash={@flash} current_user={@current_user}>
        <.page_header><:title>Sources</:title></.page_header>
      </Layouts.admin>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, required: true, doc: "the currently logged in user"
  attr :page_title, :string, default: nil, doc: "the page title, for pages without a page_header"

  attr :counts, :map,
    default: %{},
    doc: "numbers that need the curator, by section: %{review: 358}"

  slot :page_title_html, doc: "rich page title, for pages without a page_header"
  slot :inner_block, required: true

  def admin(assigns) do
    assigns =
      assigns
      |> assign(:sections, admin_sections(assigns.current_user))
      |> assign(:superadmin?, Gallformers.Accounts.superadmin?(assigns.current_user))

    ~H"""
    <div class="gf-density-working flex min-h-screen bg-paper text-body text-ink">
      <aside
        id="admin-sidebar"
        class="gf-sidenav fixed inset-y-0 left-0 z-40 hidden w-53 shrink-0 flex-col overflow-y-auto border-r border-line bg-surface-2 p-3 lg:sticky lg:top-0 lg:flex lg:h-screen"
      >
        <div class="flex items-center gap-2 px-2 pb-4 pt-1">
          <a href="/" aria-label="Gallformers home" title="The public site">
            <img
              src="/branding/Wide Logo Versions/gallformers_logo_wide_color.png"
              alt="Gallformers"
              class="gf-only-light h-7 w-auto"
            />
            <img
              src="/branding/Wide Logo Versions/gallformers_logo_wide_white.png"
              alt="Gallformers"
              class="gf-only-dark h-7 w-auto"
            />
          </a>
          <span class="font-brand text-body font-semibold text-brand">Admin</span>
        </div>
        <nav id="admin-nav" phx-hook="AdminNav" aria-label="Admin" class="flex flex-col text-ui">
          <div :for={{group, i} <- Enum.with_index(@sections)} class="flex flex-col gap-0.5">
            <hr :if={i > 0} class="mx-1 my-2" />
            <a
              :for={link <- group}
              href={link.href}
              data-nav-href={link.href}
              class="flex items-center gap-2 rounded-ctl px-2.5 py-1.5 text-ink-2 hover:bg-surface hover:text-ink hover:no-underline"
            >
              <.icon name={link.icon} class="size-4 shrink-0 text-muted" />
              <span class="flex-1">{link.label}</span>
              <span
                :if={count = @counts[link.key]}
                class="text-caption font-bold tabular-nums text-autumn-ink"
              >
                {count}
              </span>
            </a>
          </div>
          <hr class="mx-1 my-2" />
          <a
            href="/admin/profile"
            class="flex items-center gap-2 rounded-ctl px-2.5 py-1.5 text-muted hover:bg-surface"
          >
            <.icon name="ph-user-circle" class="size-4 shrink-0" /> My profile
          </a>
          <a
            href="/"
            class="flex items-center gap-2 rounded-ctl px-2.5 py-1.5 text-muted hover:bg-surface"
          >
            <.icon name="ph-arrow-square-out" class="size-4 shrink-0" /> View public site
          </a>
        </nav>
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <div
          class="sticky top-0 z-30 flex h-admin-bar items-center gap-3 border-b border-line bg-surface px-4 sm:px-page-x"
          data-sticky-chrome
        >
          <button
            type="button"
            class="inline-flex size-8 items-center justify-center rounded-ctl text-ink lg:hidden"
            phx-click={JS.toggle(to: "#admin-sidebar", display: "flex")}
            aria-controls="admin-sidebar"
            aria-label="Admin menu"
          >
            <.icon name="ph-list" class="size-5" />
          </button>
          <div class="ml-auto flex items-center gap-4 text-meta">
            <.palette_trigger class="flex w-64 max-sm:hidden" />
            <span class="text-ink-2">
              {Gallformers.Accounts.Auth0User.display_name(@current_user)}
            </span>
            <a href="/auth/logout">Log out</a>
            <.theme_switch />
          </div>
        </div>

        <main class="flex flex-1 flex-col gap-section px-4 py-5 sm:px-page-x">
          <.page_header :if={@page_title_html != [] or @page_title}>
            <:title>
              {if @page_title_html != [], do: render_slot(@page_title_html), else: @page_title}
            </:title>
          </.page_header>
          <div>{render_slot(@inner_block)}</div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # The sidebar's groups: the domain screens, the content ones, then the
  # role-restricted tools.
  defp admin_sections(user) do
    superadmin? = Gallformers.Accounts.superadmin?(user)
    operator? = Gallformers.Accounts.operator?(user)

    domain = [
      %{key: :dashboard, href: "/admin", label: "Dashboard", icon: "ph-house"},
      %{key: :review, href: "/admin/review", label: "Review", icon: "ph-check-circle"},
      %{key: :changes, href: "/admin/changes", label: "Changes", icon: "ph-list"},
      %{key: :taxonomy, href: "/admin/taxonomy", label: "Taxonomy", icon: "gf-taxon"},
      %{key: :sources, href: "/admin/sources", label: "Sources", icon: "gf-source"},
      %{key: :host_range, href: "/admin/host-range", label: "Host ranges", icon: "ph-map-trifold"}
    ]

    content =
      [
        %{key: :glossary, href: "/admin/glossary", label: "Glossary", icon: "gf-entry"},
        %{key: :articles, href: "/admin/articles", label: "Articles", icon: "ph-article"},
        %{key: :keys, href: "/admin/keys", label: "Keys", icon: "ph-tree-structure"}
      ] ++
        if(superadmin?,
          do: [
            %{
              key: :vocabulary,
              href: "/admin/vocabulary",
              label: "Vocabulary",
              icon: "ph-book-open"
            }
          ],
          else: []
        )

    tools =
      if(superadmin?,
        do: [
          %{key: :users, href: "/admin/users", label: "Users", icon: "ph-users"},
          %{key: :jobs, href: "/admin/jobs", label: "Jobs", icon: "ph-arrows-clockwise"}
        ],
        else: []
      ) ++
        if(operator?,
          do: [%{key: :ops, href: "/admin/ops", label: "Ops", icon: "ph-shield-check"}],
          else: []
        )

    Enum.reject([domain, content, tools], &(&1 == []))
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
end
