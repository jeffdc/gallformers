defmodule GallformersWeb.Router do
  use GallformersWeb, :router

  alias GallformersWeb.Plugs.FetchCurrentUser

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GallformersWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin do
    plug GallformersWeb.Plugs.RequireAdmin
  end

  defp fetch_current_user(conn, _opts) do
    FetchCurrentUser.call(conn, [])
  end

  # Health check for Fly.io (no pipeline needed)
  get "/health", GallformersWeb.HealthController, :check

  # Auth routes (login/logout via Auth0)
  scope "/auth", GallformersWeb do
    pipe_through :browser

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Admin routes (require authentication)
  scope "/admin", GallformersWeb do
    pipe_through [:browser, :admin]

    live "/", AdminDashboardLive
  end

  # Public routes
  scope "/", GallformersWeb do
    pipe_through :browser

    # Home
    live "/", HomeLive

    # Content pages
    live "/about", AboutLive
    live "/filterguide", FilterGuideLive
    live "/resources", ResourcesLive
    live "/glossary", GlossaryLive
    live "/refindex", RefIndexLive
    live "/globalsearch", SearchLive
    live "/explore", ExploreLive

    # ID Tool
    live "/id", IDLive

    # Entity pages
    live "/gall/:id", GallLive
    live "/host/:id", HostLive
    live "/family/:id", FamilyLive
    live "/genus/:id", GenusLive
    live "/source/:id", SourceLive
    live "/section/:id", SectionLive
    live "/place/:id", PlaceLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", GallformersWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:gallformers, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GallformersWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
