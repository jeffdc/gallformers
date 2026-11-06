defmodule GallformersWeb.ObservationIntakeTest do
  @moduledoc """
  Add from observation (matter `ec2c`): a curator reads one iNaturalist
  observation (`Gallformers.Curation.from_observation/3`) and confirms its
  proposals into the tray, each with the observation as its evidence; its
  photos import through the iNaturalist image import. From the Gall page
  in Edit mode (the Gall given) and from the command palette (the page
  `/admin/observation`, the Gall chosen). iNaturalist is stubbed
  (`Req.Test`, see config/test.exs).

  Not async: the fixtures make the Gallformers Source (one per database).
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import GallformersWeb.CurationWebFixtures
  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Curation
  alias Gallformers.INaturalist

  @obs_id 5151

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ada Curator")
    actor = Actor.user(user.id, "Ada Curator")
    ctx = curated_gall!(actor)
    Map.merge(ctx, %{conn: conn, actor: actor, california: place_id("US-CA")})
  end

  defp observation(_ctx, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => @obs_id,
        "taxon" => %{"id" => 1, "name" => "Andricus webcuratus", "rank" => "species"},
        "user" => %{"login" => "jdoe", "name" => "J. Doe"},
        "observed_on" => "2025-07-14",
        "place_guess" => "Berkeley, CA, USA",
        "place_ids" => [1, 14],
        "description" => "On Quercus webcurata.",
        "ofvs" => [],
        "photos" => [
          %{
            "id" => 111,
            "url" => "https://inaturalist-open-data.s3.amazonaws.com/photos/111/square.jpg",
            "license_code" => "cc-by-nc"
          }
        ]
      },
      overrides
    )
  end

  @places [
    %{"id" => 1, "name" => "United States", "admin_level" => 0},
    %{"id" => 14, "name" => "California", "admin_level" => 10}
  ]

  defp stub_inat!(obs) do
    Req.Test.stub(INaturalist, fn
      %{request_path: "/v1/observations/" <> _} = conn when is_nil(obs) ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})

      %{request_path: "/v1/observations/" <> _} = conn ->
        Req.Test.json(conn, %{"results" => [obs]})

      %{request_path: "/v1/places/" <> _} = conn ->
        Req.Test.json(conn, %{"results" => @places})
    end)
  end

  defp url, do: "https://www.inaturalist.org/observations/#{@obs_id}"

  defp items(actor) do
    case Curation.open_set(actor) do
      nil -> []
      set -> set.items
    end
  end

  defp read(view, input \\ url()) do
    view |> form("#observation-intake-read", %{"url" => input}) |> render_submit()
  end

  describe "on the Gall page in Edit mode" do
    test "Add from observation… opens it, the Gall given", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")

      view |> element("button", "Add from observation…") |> render_click()

      assert has_element?(view, "#observation-intake-read input[name=url]")
    end

    test "its proposals go into the tray, each with the observation as evidence", ctx do
      stub_inat!(observation(ctx))
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")
      view |> element("button", "Add from observation…") |> render_click()

      read(view)

      assert has_element?(view, "#observation-intake", "J. Doe")
      assert has_element?(view, "#observation-intake [data-part=item]", "recorded in California")

      view |> element("#observation-intake-add") |> render_click()

      assert [item] =
               Enum.filter(items(ctx.actor), &match?({:occurrence, _}, &1.spec.key))

      assert item.spec.gall_id == ctx.gall.id
      assert item.spec.key == {:occurrence, ctx.california}
      assert item.spec.when == "2025-07-14"
      assert [%{provider: "inaturalist", id: "5151"}] = item.evidence.observations
      assert has_element?(view, "#observation-intake", "in your tray")
    end

    test "an item left unticked stays out of the tray", ctx do
      red = plant_fixture(name: "Quercus rubrawebobs")

      host_field = %{
        "name" => "Host Plant ID",
        "datatype" => "taxon",
        "value" => "54779",
        "taxon" => %{"id" => 54_779, "name" => "Quercus rubrawebobs"}
      }

      stub_inat!(observation(ctx, %{"ofvs" => [host_field], "description" => nil}))
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")
      view |> element("button", "Add from observation…") |> render_click()
      read(view)

      view
      |> element("#observation-intake [data-part=item] input[type=checkbox][phx-value-index='0']")
      |> render_click()

      view |> element("#observation-intake-add") |> render_click()

      assert [%{spec: %{key: {:host, id}}}] = items(ctx.actor)
      assert id == red.id
    end

    test "what isn't an observation is said", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")
      view |> element("button", "Add from observation…") |> render_click()

      read(view, "not a link")

      assert has_element?(view, "#observation-intake [role=alert]", "iNaturalist observation")
    end

    test "an observation iNaturalist doesn't have is said", ctx do
      stub_inat!(nil)
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")
      view |> element("button", "Add from observation…") |> render_click()

      read(view)

      assert has_element?(view, "#observation-intake [role=alert]", "no such observation")
    end

    test "its photos are offered for import", ctx do
      stub_inat!(observation(ctx))
      {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")
      view |> element("button", "Add from observation…") |> render_click()
      read(view)

      assert render(view) =~ "photos/111/"
    end
  end

  describe "from the command palette" do
    test "the page reads the observation and the Gall is chosen", ctx do
      stub_inat!(observation(ctx))
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/observation")

      read(view)

      # The Inducer has one Gall: it is chosen.
      assert has_element?(view, "#observation-intake", ctx.gall.name)

      view |> element("#observation-intake-add") |> render_click()

      assert items(ctx.actor) |> Enum.map(& &1.spec.gall_id) |> Enum.uniq() == [ctx.gall.id]
      assert [_] = Enum.filter(items(ctx.actor), &match?({:occurrence, _}, &1.spec.key))
    end

    test "with no Gall known, one is picked by name", ctx do
      stub_inat!(
        observation(ctx, %{"taxon" => %{"id" => 2, "name" => "Unknownus", "rank" => "genus"}})
      )

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/observation")
      read(view)

      refute has_element?(view, "#observation-intake-add:not([disabled])")

      view
      |> with_target("#observation-intake")
      |> render_hook("search_gall", %{"value" => "webcuratus"})

      view |> element("#observation-gall [phx-value-id='#{ctx.gall.id}']") |> render_click()
      view |> element("#observation-intake-add") |> render_click()

      assert items(ctx.actor) |> Enum.map(& &1.spec.gall_id) |> Enum.uniq() == [ctx.gall.id]
    end
  end
end
