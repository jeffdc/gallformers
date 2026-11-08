defmodule GallformersWeb.GallLiveObservationTest do
  @moduledoc """
  Add from observation in the Fact inspector (matter `87a1`, task 10): on a
  Gall's page in Edit mode, "Add from observation…" opens the inspector's
  observation state. A pasted link reads the observation
  (`Gallformers.Curation.from_observation/3`): its card and grade, a
  warning when its taxon isn't the Gall's Inducer, what it shows (each
  ticked, New or Already held, previewed on the page as proposed), a
  missing Host asked for, its photos; one "Add N to your tray", each Fact a
  Gallformers statement with the observation as its evidence, each photo
  an editorial change. iNaturalist is stubbed (`Req.Test`).

  Not async: the fixtures make the Gallformers Source (one per database).
  """
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GallformersWeb.AdminLiveHelpers
  import GallformersWeb.CurationWebFixtures
  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias Gallformers.INaturalist

  @obs_id 6161

  setup %{conn: conn} do
    {conn, user} = log_in_admin(conn, "Ada Curator")
    actor = Actor.user(user.id, "Ada Curator")
    ctx = curated_gall!(actor)
    Map.merge(ctx, %{conn: conn, actor: actor, california: place_id("US-CA")})
  end

  defp observation(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => @obs_id,
        "taxon" => %{"id" => 1, "name" => "Andricus webcuratus", "rank" => "species"},
        "user" => %{"login" => "jdoe", "name" => "J. Doe"},
        "observed_on" => "2025-07-14",
        "quality_grade" => "needs_id",
        "place_guess" => "Berkeley, CA, USA",
        "place_ids" => [1, 14],
        "description" => nil,
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

  defp open(ctx) do
    {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")

    view
    |> element("button[phx-value-group=observation]", "Add from observation…")
    |> render_click()

    view
  end

  defp read(view), do: view |> form("#observation-form", %{"url" => url()}) |> render_submit()

  test "Add from observation… opens the inspector on the observation, not a dialog", ctx do
    view = open(ctx)

    assert has_element?(view, "#fact-inspector [data-part=kind]", "Add from observation")
    assert has_element?(view, "#observation-form input[name=url]")
    refute has_element?(view, "#observation-dialog")
  end

  test "reading it shows its card: the link, identified as, seen, by, and the grade", ctx do
    stub_inat!(observation())
    view = open(ctx)
    read(view)

    card = "#fact-inspector [data-part=card]"
    assert has_element?(view, "#{card} a[href='#{url()}']", "Observation #{@obs_id}")
    assert has_element?(view, card, "Andricus webcuratus")
    assert has_element?(view, card, "2025-07-14")
    assert has_element?(view, card, "Berkeley, CA, USA")
    assert has_element?(view, card, "jdoe - J. Doe")
    assert has_element?(view, card, "Needs ID")
    assert has_element?(view, "#fact-inspector [data-part=grade-notice]", "Not Research Grade")
  end

  test "an observation of another taxon is warned of, naming it and its Gall", ctx do
    aphid =
      Gallformers.TaxaFixtures.taxon_fixture(name: "Aphis webrubifolii", kingdom: "Animalia")

    aphid_gall = gall_fixture(name: "Aphis webrubifolii gall")

    {:ok, _} =
      Catalog.assert_relationship(
        ctx.actor,
        %{type: "inducer_of", subject_taxon_id: aphid.id, object_gall_id: aphid_gall.id},
        confirm(ctx.weld)
      )

    stub_inat!(
      observation(%{"taxon" => %{"id" => 9, "name" => "Aphis webrubifolii", "rank" => "species"}})
    )

    view = open(ctx)
    read(view)

    warning = "#fact-inspector [data-part=taxon-notice]"
    assert has_element?(view, warning, "Not this Gall's Inducer")
    assert has_element?(view, warning, "Aphis webrubifolii")
    assert has_element?(view, "#{warning} a[href='/gall/#{aphid_gall.id}?edit']")
  end

  test "what it shows: ticked, New or Already held, its reason, and previewed on the page", ctx do
    stub_inat!(observation())
    view = open(ctx)
    read(view)

    assert has_element?(view, "#fact-inspector [data-part=proposal]", "recorded in California")
    assert has_element?(view, "#fact-inspector [data-part=proposal]", "New")
    assert has_element?(view, "#gall-range [data-proposed]", "recorded in California")

    view |> element("#fact-inspector [data-part=proposal] input[type=checkbox]") |> render_click()
    refute has_element?(view, "#gall-range [data-proposed]")
  end

  test "a missing Host is asked for in the inspector, through the plant search", ctx do
    stub_inat!(observation())
    view = open(ctx)
    read(view)

    assert has_element?(view, "#fact-inspector [data-part=need-host]")

    view
    |> with_target("#from-observation")
    |> render_hook("search_plant", %{"value" => "webcurata"})

    view |> element("#observation-host [phx-value-id='#{ctx.oak.id}']") |> render_click()

    assert has_element?(view, "#fact-inspector [data-part=proposal]", "Quercus webcurata")
  end

  test "Add N to your tray: each Fact with the observation as evidence, each photo editorial",
       ctx do
    stub_inat!(observation())
    view = open(ctx)
    read(view)

    view |> element("#fact-inspector [data-part=photo] input[type=checkbox]") |> render_click()
    view |> element("#fact-inspector button", "Add 2 to your tray") |> render_click()

    [fact, photo] = ctx.actor |> items() |> Enum.sort_by(& &1.kind)
    assert %{kind: :fact, spec: %{key: {:occurrence, california}}} = fact
    assert california == ctx.california

    assert %{observations: [%{provider: "inaturalist", id: "6161", quality_grade: "needs_id"}]} =
             fact.evidence

    assert %{kind: :photo, key: {:photo, @obs_id, 111}} = photo
    refute has_element?(view, "#fact-inspector")
  end

  test "Add from observation… sits in the page header, beside the Edit toggle", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/gall/#{ctx.gall.id}?edit")

    assert has_element?(
             view,
             "header button[phx-value-group=observation]",
             "Add from observation…"
           )

    refute has_element?(view, "#editorial button", "Add from observation")
  end

  test "a proposal left unticked stays out of the tray", ctx do
    stub_inat!(observation())
    view = open(ctx)
    read(view)

    view |> element("#fact-inspector [data-part=proposal] input[type=checkbox]") |> render_click()
    view |> element("#fact-inspector [data-part=photo] input[type=checkbox]") |> render_click()
    view |> element("#fact-inspector button", "Add 1 to your tray") |> render_click()

    assert [%{kind: :photo}] = items(ctx.actor)
  end

  test "an observation iNaturalist doesn't have says so", ctx do
    Req.Test.stub(INaturalist, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
    end)

    view = open(ctx)
    read(view)

    assert has_element?(
             view,
             "#fact-inspector [data-part=error]",
             "iNaturalist has no such observation."
           )
  end

  test "a link that isn't an observation's says so", ctx do
    view = open(ctx)
    view |> form("#observation-form", %{"url" => "not a link"}) |> render_submit()

    assert has_element?(
             view,
             "#fact-inspector [data-part=error]",
             "isn't an iNaturalist observation"
           )
  end
end
