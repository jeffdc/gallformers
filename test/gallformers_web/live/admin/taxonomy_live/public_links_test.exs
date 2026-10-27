defmodule GallformersWeb.Admin.TaxonomyLive.PublicLinksTest do
  @moduledoc """
  The public Host and rank pages link admins to the taxon's page in the
  taxonomy admin (matter a856, Task 9), whether or not the old admin
  screens are enabled; other visitors see no link.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  defp uniq, do: System.unique_integer([:positive])

  setup %{conn: conn} do
    {admin, _user} = log_in_admin(conn, "Pia Public")

    family = taxon_fixture(rank: :family, name: "Linkidae#{uniq()}", kingdom: "Animalia")
    tribe = taxon_fixture(rank: :tribe, name: "Linkini#{uniq()}", parent: family)
    genus = taxon_fixture(rank: :genus, name: "Linkgenus#{uniq()}", parent: tribe)
    plant_genus = plant_fixture(rank: :genus, name: "Linkplantgenus#{uniq()}")
    section = plant_fixture(rank: :section, name: "Linksection#{uniq()}", parent: plant_genus)
    plant = plant_fixture(name: "Linkplantgenus#{uniq()} alba", parent: plant_genus)

    pages = [
      {"/host/#{plant.id}", plant},
      {"/family/#{Gallformers.Taxa.accepted_name(family)}", family},
      {"/tribe/#{Gallformers.Taxa.accepted_name(tribe)}", tribe},
      {"/genus/#{Gallformers.Taxa.accepted_name(genus)}", genus},
      {"/section/#{Gallformers.Taxa.accepted_name(section)}", section}
    ]

    %{admin: admin, anonymous: conn, pages: pages}
  end

  test "an admin gets an edit link to the taxonomy admin on each page", %{
    admin: admin,
    pages: pages
  } do
    for {path, taxon} <- pages do
      {:ok, view, _html} = live(admin, path)

      assert has_element?(view, "a[href='/admin/taxonomy/#{taxon.id}'][title='Edit in admin']"),
             "no admin link on #{path}"
    end
  end

  test "a visitor gets none", %{anonymous: conn, pages: pages} do
    for {path, _taxon} <- pages do
      {:ok, view, _html} = live(conn, path)

      refute has_element?(view, "a[href^='/admin/taxonomy']"), "admin link on #{path}"
    end
  end
end
