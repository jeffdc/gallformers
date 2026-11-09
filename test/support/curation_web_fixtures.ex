defmodule GallformersWeb.CurationWebFixtures do
  @moduledoc """
  A Gall to curate in the web tests of the tray and Edit mode (matter
  ec2c): Weld (1959) states its Inducer, a Host and the season Spring; the
  Gallformers Source exists, so Fact items can apply. Load in a test module
  that is not async (the Gallformers Source is one per database).
  """
  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog

  @doc """
  The Gall and its parts, the Facts stated as `actor`:
  `%{gall, wasp, oak, weld, gallformers, host, spring}`.
  """
  def curated_gall!(actor) do
    load_vocab!()
    gallformers = gallformers_source()
    weld = source_fixture("Weld", "1959")
    wasp = taxon_fixture(name: "Andricus webcuratus", kingdom: "Animalia")
    oak = plant_fixture(name: "Quercus webcurata")
    gall = gall_fixture(name: "Andricus webcuratus gall")

    {:ok, %{fact: host}} =
      Catalog.assert_relationship(
        actor,
        %{type: "host_of", subject_taxon_id: oak.id, object_gall_id: gall.id},
        confirm(weld)
      )

    {:ok, _} =
      Catalog.assert_relationship(
        actor,
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(weld)
      )

    {:ok, %{fact: spring}} =
      Catalog.assert_trait(
        actor,
        %{gall_id: gall.id, trait: "season", value: "Spring"},
        confirm(weld, %{value_as_written: "spring"})
      )

    %{
      gall: gall,
      wasp: wasp,
      oak: oak,
      weld: weld,
      gallformers: gallformers,
      host: host,
      spring: spring
    }
  end

  @doc """
  Weld's statement of the Host, quoted ("On Q. webcurata, rarely", p. 41),
  as a Source's statement read from its text is: so its reading can be
  fixed (matter `87a1`).
  """
  def quote_weld_host!(actor, ctx) do
    {:ok, _} =
      Catalog.assert_relationship(
        actor,
        %{type: "host_of", subject_taxon_id: ctx.oak.id, object_gall_id: ctx.gall.id},
        confirm(ctx.weld, %{evidence: [%{quote: "On Q. webcurata, rarely", page: "41"}]})
      )

    ctx
  end
end
