defmodule GallformersWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use GallformersWeb, :controller
      use GallformersWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  # Directories for Plug.Static's `only:` option (exact first-segment match)
  def static_dirs, do: ~w(assets fonts images branding data)

  # File prefixes for Plug.Static's `only_matching:` option (prefix match)
  # This allows digested files like favicon-abc123.ico to be served
  def static_matching,
    do: ~w(robots favicon apple-touch-icon apple-icon android-icon ms-icon manifest browserconfig)

  # Combined list for Phoenix's ~p sigil validation
  def static_paths, do: static_dirs() ++ static_matching()

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: GallformersWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: GallformersWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components — our form/1 wrapper takes precedence over Phoenix's
      import Phoenix.Component, except: [form: 1]
      import GallformersWeb.CoreComponents
      # Shared UI components (cards, alerts, spinners, etc.)
      import GallformersWeb.UIComponents
      # Form components (buttons, multi-select, etc.)
      import GallformersWeb.FormComponents
      # Data display components (species cards, taxonomy, etc.)
      import GallformersWeb.DataDisplayComponents
      # View helpers (formatting, etc.)
      import GallformersWeb.Helpers

      # Common modules used in templates
      alias GallformersWeb.Layouts
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: GallformersWeb.Endpoint,
        router: GallformersWeb.Router,
        statics: GallformersWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
