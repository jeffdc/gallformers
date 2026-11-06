defmodule Gallformers.Curation.FromObservationTest do
  @moduledoc """
  Add from observation (`Gallformers.Curation.from_observation/3`, matter
  `ec2c`): one iNaturalist observation read into proposed change-set items
  — a recorded occurrence for its state or province, dated as seen; the
  Host from its "Host Plant ID" field and its description; the Gall given
  or chosen among the Inducer's — with the observation as their evidence,
  for the curator to confirm into the tray. iNaturalist is stubbed
  (`Req.Test`): no test reaches the network.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Accounts
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias Gallformers.INaturalist

  @obs_id 4242

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|from-obs-#{System.unique_integer([:positive])}",
        display_name: "Ada"
      })

    ada = Actor.user(user.id, "Ada")
    :ok = put_test_actor(ada)

    weld = source_fixture("Weld", "1959")
    genus = plant_fixture(name: "Obsquercus", rank: :genus)
    oak = plant_fixture(name: "Obsquercus alba", parent: genus)
    maple_genus = plant_fixture(name: "Obsacer", rank: :genus)
    maple = plant_fixture(name: "Obsacer rubrum", parent: maple_genus)
    wasp = taxon_fixture(name: "Andricus obsus", kingdom: "Animalia")
    gall = gall_fixture(name: "Andricus obsus gall")
    inducer!(ada, weld, wasp, gall)

    %{
      ada: ada,
      weld: weld,
      oak: oak,
      maple: maple,
      wasp: wasp,
      gall: gall,
      california: place_id("US-CA")
    }
  end

  defp inducer!(actor, source, taxon, gall) do
    {:ok, _} =
      Catalog.assert_relationship(
        actor,
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )
  end

  defp observation(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => @obs_id,
        "taxon" => %{"id" => 1, "name" => "Andricus obsus", "rank" => "species"},
        "user" => %{"login" => "jdoe", "name" => "J. Doe"},
        "observed_on" => "2025-07-14",
        "place_guess" => "Berkeley, CA, USA",
        "place_ids" => [1, 14, 2001],
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

  defp host_field(name, taxon_id \\ 54_779) do
    %{
      "name" => "Host Plant ID",
      "datatype" => "taxon",
      "value" => to_string(taxon_id),
      "taxon" => %{"id" => taxon_id, "name" => name}
    }
  end

  @places [
    %{"id" => 1, "name" => "United States", "admin_level" => 0},
    %{"id" => 14, "name" => "California", "admin_level" => 10},
    %{"id" => 2001, "name" => "Alameda", "admin_level" => 20}
  ]

  defp stub_inat!(obs, places \\ @places) do
    Req.Test.stub(INaturalist, &respond(&1, obs, places))
  end

  defp respond(%{request_path: "/v1/observations/" <> _id} = conn, nil, _places),
    do: conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})

  defp respond(%{request_path: "/v1/observations/" <> _id} = conn, obs, _places),
    do: Req.Test.json(conn, %{"results" => [obs]})

  defp respond(%{request_path: "/v1/places/" <> _ids} = conn, _obs, places),
    do: Req.Test.json(conn, %{"results" => places})

  defp needs(proposal, kind), do: for(%{kind: ^kind, text: text} <- proposal.needs, do: text)

  defp url, do: "https://www.inaturalist.org/observations/#{@obs_id}"

  defp keys(proposal, role), do: for(%{role: ^role} = i <- proposal.items, do: i.spec.key)

  describe "the recorded occurrence" do
    test "for the observation's state, dated as seen, on the given Gall", ctx do
      stub_inat!(observation())

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)

      assert [occurrence] = for(%{role: :occurrence} = i <- proposal.items, do: i)

      assert occurrence.spec == %{
               kind: :fact,
               gall_id: ctx.gall.id,
               action: :add,
               key: {:occurrence, ctx.california},
               when: "2025-07-14"
             }

      assert occurrence.selected == true
      assert occurrence.text =~ "recorded in California"
      assert occurrence.why =~ "California"
      assert occurrence.why =~ "2025-07-14"

      assert proposal.evidence == %{
               text: nil,
               observations: [%{provider: "inaturalist", id: "#{@obs_id}"}],
               source_id: nil
             }

      assert proposal.gall.gall_id == ctx.gall.id
      assert proposal.observation.id == @obs_id
      assert proposal.observation.observed_on == ~D[2025-07-14]
    end

    test "the proposed item goes into the tray as proposed, with its date", ctx do
      stub_inat!(observation())
      {:ok, proposal} = Curation.from_observation(ctx.ada, "#{@obs_id}", ctx.gall.id)
      [occurrence] = for(%{role: :occurrence} = i <- proposal.items, do: i)

      assert {:ok, item} = Curation.add_item(ctx.ada, occurrence.spec)
      assert item.spec.when == "2025-07-14"
      assert item.text == occurrence.text
      assert {:ok, _set} = Curation.set_item_evidence(ctx.ada, item.id, proposal.evidence)
    end

    test "a place we do not hold: the curator is told, no occurrence", ctx do
      stub_inat!(observation(), [
        %{"id" => 1, "name" => "United States", "admin_level" => 0},
        %{"id" => 14, "name" => "Atlantis", "admin_level" => 10}
      ])

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)
      assert keys(proposal, :occurrence) == []
      assert [text] = needs(proposal, :place)
      assert text =~ "Atlantis"
    end
  end

  describe "the Host" do
    test "from the Host Plant ID field, matched through intake's plant resolution", ctx do
      stub_inat!(observation(%{"ofvs" => [host_field("Obsquercus alba")]}))

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)
      assert [host] = for(%{role: :host} = i <- proposal.items, do: i)

      assert host.spec == %{
               kind: :fact,
               gall_id: ctx.gall.id,
               action: :add,
               key: {:host, ctx.oak.id}
             }

      assert host.selected == true
      assert host.why =~ "Host Plant ID"
      assert host.text =~ "Obsquercus alba"
      assert needs(proposal, :host) == []
      assert {:ok, _item} = Curation.add_item(ctx.ada, host.spec)
    end

    test "from plant names in the description, abbreviations included", ctx do
      stub_inat!(
        observation(%{
          "description" =>
            "Under Obsquercus trees. The galls were on Obsacer rubrum, beside an O. alba. " <>
              "Andricus obsus emerged later."
        })
      )

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)

      assert Enum.sort(keys(proposal, :host)) ==
               Enum.sort([{:host, ctx.maple.id}, {:host, ctx.oak.id}])

      assert [_, _] =
               for(%{role: :host, why: why} <- proposal.items, why =~ "description", do: why)
    end

    test "a name in both the field and the description is proposed once", ctx do
      stub_inat!(
        observation(%{
          "ofvs" => [host_field("Obsquercus alba")],
          "description" => "On Obsquercus alba."
        })
      )

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)
      assert keys(proposal, :host) == [{:host, ctx.oak.id}]
    end

    test "no Host found: the curator must give it", ctx do
      stub_inat!(observation(%{"description" => "A nice gall on a leaf."}))

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)
      assert keys(proposal, :host) == []
      assert [text] = needs(proposal, :host)
      assert text =~ "Host"
    end

    test "a Host Plant ID the tree does not hold is reported, not proposed", ctx do
      stub_inat!(observation(%{"ofvs" => [host_field("Nullplantus nowhere")]}))

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)
      assert keys(proposal, :host) == []
      assert [text] = needs(proposal, :host)
      assert text =~ "Nullplantus nowhere"
    end
  end

  describe "the Gall" do
    test "without a Gall: the Inducer's only Gall is chosen", ctx do
      stub_inat!(observation(%{"ofvs" => [host_field("Obsquercus alba")]}))

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), nil)
      assert [%{id: id}] = proposal.gall.candidates
      assert id == ctx.gall.id
      assert proposal.gall.gall_id == ctx.gall.id
      assert proposal.items |> Enum.map(& &1.spec.gall_id) |> Enum.uniq() == [ctx.gall.id]
    end

    test "several Galls of the Inducer: the curator chooses", ctx do
      other = gall_fixture(name: "Andricus obsus other gall")
      inducer!(ctx.ada, ctx.weld, ctx.wasp, other)
      stub_inat!(observation())

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), nil)

      assert Enum.sort(Enum.map(proposal.gall.candidates, & &1.id)) ==
               Enum.sort([ctx.gall.id, other.id])

      assert proposal.gall.gall_id == nil
      assert proposal.items |> Enum.map(& &1.spec.gall_id) |> Enum.uniq() == [nil]
      assert [text] = needs(proposal, :gall)
      assert text =~ "2 Galls"
    end

    test "a Gallformers Code field picks the Gall", ctx do
      other = gall_fixture(name: "Andricus obsus coded gall", gallformers_code: "obs-code-1")
      inducer!(ctx.ada, ctx.weld, ctx.wasp, other)

      stub_inat!(
        observation(%{"ofvs" => [%{"name" => "Gallformers Code", "value" => "obs-code-1"}]})
      )

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), nil)
      assert proposal.gall.gall_id == other.id
      assert needs(proposal, :gall) == []
    end

    test "a taxon we do not hold: no candidates, the curator chooses", ctx do
      stub_inat!(observation(%{"taxon" => %{"id" => 9, "name" => "Nullwasp nowhere"}}))

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), nil)
      assert proposal.gall.candidates == []
      assert proposal.gall.gall_id == nil
      assert [text] = needs(proposal, :gall)
      assert text =~ "Nullwasp nowhere"
    end

    test "a Gall that does not exist", ctx do
      stub_inat!(observation())
      assert {:error, :no_such_gall} = Curation.from_observation(ctx.ada, url(), -1)
    end
  end

  describe "photos" do
    test "the observation's photos and the observation, for the image import", ctx do
      stub_inat!(observation())

      assert {:ok, proposal} = Curation.from_observation(ctx.ada, url(), ctx.gall.id)
      assert [%INaturalist.Photo{id: 111, mapped_license: "CC-BY-NC"}] = proposal.photos
      assert %INaturalist.Observation{id: @obs_id} = proposal.inat_observation
    end
  end

  describe "errors" do
    test "not an observation URL", ctx do
      assert {:error, :invalid_input} =
               Curation.from_observation(ctx.ada, "https://example.com/obs/1", nil)
    end

    test "no such observation", ctx do
      stub_inat!(nil)
      assert {:error, :not_found} = Curation.from_observation(ctx.ada, url(), nil)
    end

    @tag :capture_log
    test "iNaturalist unreachable", ctx do
      Req.Test.stub(INaturalist, &Req.Test.transport_error(&1, :econnrefused))
      assert {:error, :unavailable} = Curation.from_observation(ctx.ada, url(), nil)
    end
  end
end
