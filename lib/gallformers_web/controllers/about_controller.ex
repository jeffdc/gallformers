defmodule GallformersWeb.AboutController do
  use GallformersWeb, :controller

  import Ecto.Query

  alias Gallformers.{Accounts, Galls, Repo, Sources, Version}
  alias Gallformers.Plants
  alias Gallformers.Taxonomy.Taxonomy

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

  defp get_site_stats do
    %{
      galls: Galls.count_galls(),
      hosts: Plants.count_hosts(),
      sources: Sources.count_sources(),
      gall_families: count_families_for_taxoncode("gall"),
      gall_genera: count_genera_for_taxoncode("gall"),
      host_families: count_families_for_taxoncode("plant"),
      host_genera: count_genera_for_taxoncode("plant"),
      undescribed: Galls.count_undescribed_galls()
    }
  end

  defp count_families_for_taxoncode(taxoncode) do
    from(s in Gallformers.Species.Species,
      join: st in "species_taxonomy",
      on: st.species_id == s.id,
      join: g in Taxonomy,
      on: st.taxonomy_id == g.id,
      join: f in Taxonomy,
      on: g.parent_id == f.id,
      where: s.taxoncode == ^taxoncode and g.type == "genus" and f.type == "family",
      select: count(f.name, :distinct)
    )
    |> Repo.one()
  end

  defp count_genera_for_taxoncode(taxoncode) do
    from(s in Gallformers.Species.Species,
      join: st in "species_taxonomy",
      on: st.species_id == s.id,
      join: g in Taxonomy,
      on: st.taxonomy_id == g.id,
      where: s.taxoncode == ^taxoncode and g.type == "genus",
      select: count(g.name, :distinct)
    )
    |> Repo.one()
  end
end
