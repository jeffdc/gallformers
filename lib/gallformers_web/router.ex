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
    plug GallformersWeb.Plugs.ContentSecurityPolicy
    plug :fetch_current_user
    plug GallformersWeb.Plugs.Analytics
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug GallformersWeb.Plugs.CORS
    plug GallformersWeb.Plugs.ApiCache
    plug OpenApiSpex.Plug.PutApiSpec, module: GallformersWeb.ApiSpec
  end

  pipeline :admin do
    plug GallformersWeb.Plugs.RequireAdmin
  end

  pipeline :superadmin do
    plug GallformersWeb.Plugs.RequireSuperAdmin
  end

  defp fetch_current_user(conn, _opts) do
    FetchCurrentUser.call(conn, [])
  end

  # Health check for Fly.io (no pipeline needed)
  get "/health", GallformersWeb.HealthController, :check

  # Public routes
  scope "/", GallformersWeb do
    get "/sitemap.xml", SitemapController, :index
    get "/robots.txt", RobotsController, :index
  end

  # Legacy URL redirects (301)
  scope "/", GallformersWeb do
    pipe_through :browser

    get "/refindex", RedirectController, :articles
    get "/ref/:slug", RedirectController, :article
    get "/explore", RedirectController, :explore
    get "/taxonomy/:id", RedirectController, :taxonomy
  end

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

    get "/refresh-session", AuthController, :refresh_session

    live "/", Admin.DashboardLive

    # Gall admin
    live "/galls", Admin.GallLive.Index, :index
    live "/galls/new", Admin.GallLive.Form, :new
    live "/galls/undescribed", Admin.GallLive.Undescribed, :new
    live "/galls/:id", Admin.GallLive.Form, :edit

    # Gall-Host mapping admin
    live "/gallhost", Admin.GallHostLive, :index

    # Gall range review (disabled — not ready for production)
    # live "/gall-range", Admin.GallRangeLive

    # Host admin
    live "/hosts", Admin.HostLive.Index, :index
    live "/hosts/new", Admin.HostLive.Form, :new
    live "/hosts/:id", Admin.HostLive.Form, :edit

    # Taxonomy admin
    live "/taxonomy", Admin.TaxonomyLive.Index, :index
    live "/taxonomy/new", Admin.TaxonomyLive.Form, :new
    live "/taxonomy/:id", Admin.TaxonomyLive.Form, :edit

    # Section admin (species mapping — creation/editing in taxonomy form)
    live "/section", Admin.SectionLive.Form, :index
    live "/section/:id", Admin.SectionLive.Form, :edit

    # Source admin
    live "/sources", Admin.SourceLive.Index, :index
    live "/sources/new", Admin.SourceLive.Form, :new
    live "/sources/:id", Admin.SourceLive.Form, :edit

    # Species-Source mapping admin
    live "/species-sources/add", Admin.SpeciesSourceLive.AddFromSource, :add
    live "/species-sources/find", Admin.SpeciesSourceLive.QuickFind, :find

    # Glossary admin
    live "/glossary", Admin.GlossaryLive.Index, :index
    live "/glossary/new", Admin.GlossaryLive.Form, :new
    live "/glossary/:id", Admin.GlossaryLive.Form, :edit

    # Images admin
    live "/images", Admin.ImagesLive
    live "/image-audit", Admin.ImageAuditLive

    # Articles admin
    live "/articles", Admin.ArticleLive.Index, :index
    live "/articles/new", Admin.ArticleLive.Form, :new
    live "/articles/:id", Admin.ArticleLive.Form, :edit

    # Keys admin
    live "/keys", Admin.KeyLive.Index, :index
    live "/keys/new", Admin.KeyLive.Form, :new
    live "/keys/:id", Admin.KeyLive.Form, :edit

    # User profile
    live "/profile", Admin.ProfileLive
  end

  # Super admin routes (require superadmin role)
  scope "/admin", GallformersWeb do
    pipe_through [:browser, :superadmin]

    # Reconciliation reports (superadmin only)
    live "/reconciliation", Admin.ReconciliationLive

    # Filter terms admin (superadmin only)
    live "/filter-terms", Admin.FilterTermsLive.Index, :index
    live "/filter-terms/new", Admin.FilterTermsLive.Form, :new
    live "/filter-terms/:id", Admin.FilterTermsLive.Form, :edit

    # User management (superadmin only)
    live "/users", Admin.UsersLive, :index
  end

  # Public routes
  scope "/", GallformersWeb do
    pipe_through :browser

    # Controller-rendered pages (no WebSocket needed)
    get "/about", AboutController, :show
    get "/articles", ArticlesController, :index
    get "/articles/:slug", ArticleController, :show
    get "/privacy", PrivacyController, :show
    get "/filterguide", FilterGuideController, :show

    live_session :public,
      on_mount: [
        {GallformersWeb.Live.UserAuth, :fetch_current_user},
        {GallformersWeb.Live.ContinentScope, :default},
        {GallformersWeb.Analytics.TrackPageView, :default}
      ] do
      # Home
      live "/", HomeLive

      # Content pages
      live "/analytics", AnalyticsLive
      live "/glossary", GlossaryLive
      live "/globalsearch", SearchLive
      live "/galls", GallsBrowseLive
      live "/hosts", HostsBrowseLive
      live "/places", PlacesBrowseLive

      # ID Tool
      live "/id", IDLive

      # Identification Keys
      live "/keys", KeysLive
      live "/keys/:slug", KeyLive

      # Entity pages
      live "/gall/:id", GallLive
      live "/host/:id", HostLive
      live "/family/:name", FamilyLive
      live "/genus/:name", GenusLive
      live "/source/:id", SourceLive
      live "/section/:name", SectionLive
      live "/place/:code", PlaceLive

      # Intermediate rank-typed routes (all point to IntermediateLive)
      live "/subfamily/:name", IntermediateLive, :subfamily
      live "/tribe/:name", IntermediateLive, :tribe
      live "/subtribe/:name", IntermediateLive, :subtribe
      live "/infratribe/:name", IntermediateLive, :infratribe
      live "/supertribe/:name", IntermediateLive, :supertribe
      live "/infrafamily/:name", IntermediateLive, :infrafamily

      # User profiles
      live "/user/:nickname", UserProfileLive
    end
  end

  # API documentation routes
  scope "/api" do
    pipe_through :api
    get "/docs/openapi.json", OpenApiSpex.Plug.RenderSpec, spec: GallformersWeb.ApiSpec
  end

  scope "/api/docs" do
    pipe_through :browser
    get "/", OpenApiSpex.Plug.SwaggerUI, path: "/api/docs/openapi.json"
  end

  # API v2 routes
  scope "/api/v2", GallformersWeb.API do
    pipe_through [:api, GallformersWeb.Plugs.RateLimiter]

    # Gall endpoints
    get "/galls", GallController, :index
    get "/galls/:id", GallController, :show
    get "/galls/:id/images", GallController, :images
    get "/galls/:id/sources", GallController, :sources

    # Host endpoints
    get "/hosts", HostController, :index
    get "/hosts/:id", HostController, :show
    get "/hosts/:id/images", HostController, :images
    get "/hosts/:id/galls", HostController, :galls

    # Taxonomy endpoints
    get "/genera", TaxonomyController, :genera
    get "/families", TaxonomyController, :families
    get "/families/:id", TaxonomyController, :family
    get "/genera/:id", TaxonomyController, :genus
    get "/sections", TaxonomyController, :sections
    get "/sections/:id", TaxonomyController, :section
    get "/intermediates/:id", TaxonomyController, :intermediate

    # Source endpoints
    get "/sources", SourceController, :index
    get "/sources/:id", SourceController, :show

    # Glossary endpoints
    get "/glossary", GlossaryController, :index
    get "/glossary/by-word/:word", GlossaryController, :by_word

    # Place endpoints
    get "/places", PlaceController, :index

    # Search
    get "/search", SearchController, :search

    # Stats
    get "/stats", StatsController, :index
  end

  # LiveDashboard — superadmin only in all environments
  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through [:browser, :superadmin]

    live_dashboard "/dashboard",
      metrics: GallformersWeb.Telemetry,
      ecto_repos: [Gallformers.Repo]
  end

  # Swoosh mailbox preview in development only
  if Application.compile_env(:gallformers, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
