defmodule GallformersWeb.AboutController do
  use GallformersWeb, :controller

  alias Gallformers.{Accounts, Catalog, Images, Sources, Taxa, Version}

  def show(conn, _params) do
    stats = get_site_stats()
    administrators = Accounts.list_users_for_about_page()

    conn
    |> assign(:page_title, "About")
    |> assign(
      :page_description,
      "About Gallformers - Learn about the team behind the comprehensive database of plant galls and their causative organisms."
    )
    |> assign(:page_url, "/about")
    |> assign(:stats, stats)
    |> assign(:administrators, administrators)
    |> assign(
      :gen_time,
      DateTime.utc_now() |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
    )
    |> assign(:app_version, Version.app_version())
    |> assign(:api_version, Version.api_version())
    |> render(:show)
  end

  # Galls and the families and genera of their Inducers; plants and the
  # families and genera holding them.
  defp get_site_stats do
    galls = Catalog.gall_counts()
    plants = Taxa.plant_counts()

    %{
      galls: galls.galls,
      undescribed: galls.undescribed,
      gall_families: galls.families,
      gall_genera: galls.genera,
      hosts: plants.plants,
      host_families: plants.families,
      host_genera: plants.genera,
      sources: Sources.count_sources(),
      images: Images.count_images()
    }
  end
end
