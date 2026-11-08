defmodule GallformersWeb.Admin.ObservationLiveTest do
  @moduledoc """
  Add from observation with no Gall given (`/admin/observation`, the
  command palette's "Add from observation…"; matter `87a1`, its question 9):
  one field; reading the observation opens the Gall it suggests in Edit
  mode with the Fact inspector on the observation
  (`/gall/:id?edit&observation=<id>`); with several Galls they are listed
  to choose; with none it says so. iNaturalist is stubbed (`Req.Test`).

  Not async: the fixtures make the Gallformers Source (one per database).
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import GallformersWeb.CurationWebFixtures
  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.INaturalist

  @obs_id 7171

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ada Curator")
    actor = Actor.user(user.id, "Ada Curator")
    ctx = curated_gall!(actor)
    Map.merge(ctx, %{conn: conn, actor: actor})
  end

  defp observation(taxon_name) do
    %{
      "id" => @obs_id,
      "taxon" => %{"id" => 1, "name" => taxon_name, "rank" => "species"},
      "user" => %{"login" => "jdoe", "name" => "J. Doe"},
      "observed_on" => "2025-07-14",
      "quality_grade" => "research",
      "place_guess" => "Berkeley, CA, USA",
      "place_ids" => [1, 14],
      "description" => nil,
      "ofvs" => [],
      "photos" => []
    }
  end

  defp stub_inat!(obs) do
    Req.Test.stub(INaturalist, fn
      %{request_path: "/v1/observations/" <> _} = conn ->
        Req.Test.json(conn, %{"results" => [obs]})

      %{request_path: "/v1/places/" <> _} = conn ->
        Req.Test.json(conn, %{
          "results" => [
            %{"id" => 1, "name" => "United States", "admin_level" => 0},
            %{"id" => 14, "name" => "California", "admin_level" => 10}
          ]
        })
    end)
  end

  defp url, do: "https://www.inaturalist.org/observations/#{@obs_id}"

  defp read(view), do: view |> form("#observation-form", %{"url" => url()}) |> render_submit()

  test "an observation of a taxon with one Gall opens that Gall, the inspector on it", ctx do
    stub_inat!(observation("Andricus webcuratus"))
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/observation")

    path = ~p"/gall/#{ctx.gall.id}?edit&observation=#{@obs_id}"
    assert {:error, {:live_redirect, %{to: ^path}}} = read(view)

    {:ok, gall_view, _html} = live(ctx.conn, path)
    assert has_element?(gall_view, "#fact-inspector [data-part=kind]", "Add from observation")
    assert has_element?(gall_view, "#fact-inspector [data-part=card]", "Observation #{@obs_id}")
  end

  test "several Galls of its taxon are listed to choose, each opening the inspector", ctx do
    other = gall_fixture(name: "Andricus webcuratus other gall")

    {:ok, _} =
      Catalog.assert_relationship(
        ctx.actor,
        %{type: "inducer_of", subject_taxon_id: ctx.wasp.id, object_gall_id: other.id},
        confirm(ctx.weld)
      )

    stub_inat!(observation("Andricus webcuratus"))
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/observation")
    read(view)

    for gall <- [ctx.gall, other] do
      assert has_element?(
               view,
               "#observation-galls a[href='/gall/#{gall.id}?edit&observation=#{@obs_id}']"
             )
    end
  end

  test "no Gall of its taxon: says so", ctx do
    stub_inat!(observation("Nothingus unknownii"))
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/observation")
    read(view)

    assert has_element?(view, "#observation-none", "No Gall in Gallformers")
  end

  test "a link that isn't an observation's says so", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/admin/observation")
    view |> form("#observation-form", %{"url" => "not a link"}) |> render_submit()

    assert has_element?(view, "[data-part=error]", "isn't an iNaturalist observation")
  end
end
