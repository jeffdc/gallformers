defmodule Gallformers.Catalog.GallNameTest do
  @moduledoc """
  A Gall's name derived from its name parts (`86e7` Task 1,
  `Gallformers.Catalog.GallName`): the base from its Inducer (or its
  descriptor), then its form label, generation and Host qualifier. Names
  shown are unique, ignoring case.

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.GallName

  setup do
    load_vocab!()

    family = taxon_fixture(rank: :family, name: "Fixturnamidae", kingdom: "Animalia")
    tribe = taxon_fixture(rank: :tribe, name: "Fixturnamini", parent: family)
    genus = taxon_fixture(rank: :genus, name: "Fixturnamus", parent: tribe)
    section = taxon_fixture(rank: :section, name: "Fixturnamus sect. Fixturae", parent: genus)
    species = taxon_fixture(rank: :species, name: "Fixturnamus saltator", parent: genus)
    order = taxon_fixture(rank: :order, name: "Fixturnamoptera", kingdom: "Animalia")
    plant_genus = plant_fixture(rank: :genus, name: "Fixturnamquercus")
    plant = plant_fixture(name: "Fixturnamquercus douglasii", parent: plant_genus)

    %{
      family: family,
      tribe: tribe,
      genus: genus,
      section: section,
      species: species,
      order: order,
      plant_genus: plant_genus,
      plant: plant
    }
  end

  defp generation_id(value), do: Catalog.get_generation_value(value).id

  describe "derive/1" do
    test "a species Inducer and a generation", ctx do
      assert GallName.derive(%{
               inducer_taxon_id: ctx.species.id,
               generation_value_id: generation_id("agamic")
             }) == {:ok, "Fixturnamus saltator (agamic)"}
    end

    test "a species Inducer alone is its accepted name", ctx do
      assert GallName.derive(%{inducer_taxon_id: ctx.species.id}) ==
               {:ok, "Fixturnamus saltator"}
    end

    test "the form label comes before the generation", ctx do
      assert GallName.derive(%{
               inducer_taxon_id: ctx.species.id,
               form_label: "australis",
               generation_value_id: generation_id("agamic")
             }) == {:ok, "Fixturnamus saltator (australis) (agamic)"}
    end

    test "form, generation, then the Host qualifier", ctx do
      assert GallName.derive(%{
               inducer_taxon_id: ctx.species.id,
               form_label: "pacificus",
               generation_value_id: generation_id("sexual"),
               host_qualifier_taxon_id: ctx.plant.id
             }) ==
               {:ok, "Fixturnamus saltator (pacificus) (sexgen) (on Fixturnamquercus douglasii)"}
    end

    test "a genus Host qualifier is the genus's name", ctx do
      assert GallName.derive(%{
               inducer_taxon_id: ctx.species.id,
               host_qualifier_taxon_id: ctx.plant_genus.id
             }) == {:ok, "Fixturnamus saltator (on Fixturnamquercus)"}
    end

    test "a species Inducer ignores a descriptor", ctx do
      assert GallName.derive(%{inducer_taxon_id: ctx.species.id, descriptor: "q-alba-gall"}) ==
               {:ok, "Fixturnamus saltator"}
    end

    test "a genus Inducer: the genus and the descriptor", ctx do
      assert GallName.derive(%{
               inducer_taxon_id: ctx.genus.id,
               descriptor: "q-havardii-cup-gall",
               generation_value_id: generation_id("agamic")
             }) == {:ok, "Fixturnamus q-havardii-cup-gall (agamic)"}
    end

    test "a section Inducer: its genus and the descriptor", ctx do
      assert GallName.derive(%{inducer_taxon_id: ctx.section.id, descriptor: "q-alba-bead"}) ==
               {:ok, "Fixturnamus q-alba-bead"}
    end

    test "a tribe Inducer: Unknown (its family) and the descriptor", ctx do
      assert GallName.derive(%{inducer_taxon_id: ctx.tribe.id, descriptor: "q-alba-bead"}) ==
               {:ok, "Unknown (Fixturnamidae) q-alba-bead"}
    end

    test "a family Inducer: Unknown (the family) and the descriptor", ctx do
      assert GallName.derive(%{inducer_taxon_id: ctx.family.id, descriptor: "salix-gall"}) ==
               {:ok, "Unknown (Fixturnamidae) salix-gall"}
    end

    test "no Inducer, with a descriptor: Unknown (Unknown) and the descriptor" do
      assert GallName.derive(%{descriptor: "ash-leaf-bunching"}) ==
               {:ok, "Unknown (Unknown) ash-leaf-bunching"}
    end

    test "an undescribed Gall needs a descriptor", ctx do
      assert GallName.derive(%{}) == {:error, :no_base}
      assert GallName.derive(%{inducer_taxon_id: ctx.genus.id}) == {:error, :no_base}

      assert GallName.derive(%{inducer_taxon_id: ctx.family.id, descriptor: "  "}) ==
               {:error, :no_base}
    end

    test "an Inducer above family has no family to name", ctx do
      assert GallName.derive(%{inducer_taxon_id: ctx.order.id, descriptor: "x-gall"}) ==
               {:error, :no_family}
    end

    test "parts are trimmed", ctx do
      assert GallName.derive(%{
               inducer_taxon_id: ctx.genus.id,
               descriptor: " q-gall ",
               form_label: " bud "
             }) ==
               {:ok, "Fixturnamus q-gall (bud)"}
    end
  end

  describe "derived_name/1" do
    test "reads the Gall's current Inducer and its parts", ctx do
      source = source_fixture("Weld", "1959")

      gall =
        gall_fixture(
          name: "Fixture placeholder name",
          generation: "agamic",
          form_label: "australis",
          host_qualifier_taxon_id: ctx.plant.id
        )

      assert Catalog.derived_name(gall.id) == {:error, :no_base}

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: ctx.species.id, object_gall_id: gall.id},
          confirm(source)
        )

      assert Catalog.derived_name(gall.id) ==
               {:ok, "Fixturnamus saltator (australis) (agamic) (on Fixturnamquercus douglasii)"}
    end

    test "several current Inducers give no name", ctx do
      source = source_fixture("Weld", "1959")
      other = source_fixture("Kinsey", "1930")
      gall = gall_fixture()

      for {taxon, src} <- [{ctx.species, source}, {ctx.genus, other}] do
        {:ok, _} =
          Catalog.assert_relationship(
            test_actor(),
            %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
            confirm(src)
          )
      end

      assert Catalog.derived_name(gall.id) == {:error, :several_inducers}
    end
  end

  describe "names shown are unique, ignoring case" do
    test "a name differing only in case is rejected" do
      gall_fixture(name: "Fixturnamus foo")

      assert {:error, changeset} = Catalog.create_gall(test_actor(), %{name: "fixturnamus FOO"})
      assert %{name: [_message]} = errors_on(changeset)
    end

    test "an override is compared with the names shown" do
      gall_fixture(name: "Fixturnamus bar (derived)", name_override: "Fixturnamus bar")

      assert {:error, _changeset} =
               Catalog.create_gall(test_actor(), %{name: "FIXTURNAMUS BAR"})

      # The derived name under an override is not shown, so it is free.
      assert {:ok, _gall} =
               Catalog.create_gall(test_actor(), %{name: "Fixturnamus bar (derived)"})
    end

    test "gall_name_taken?/1 ignores case" do
      gall_fixture(name: "Fixturnamus baz")

      assert Catalog.gall_name_taken?("fixturnamus BAZ") == true
      assert Catalog.gall_name_taken?("Fixturnamus baz (2)") == false
    end
  end

  describe "the name parts" do
    test "a Gall stores its form label, descriptor and Host qualifier", ctx do
      gall =
        gall_fixture(
          form_label: "bud",
          descriptor: "q-alba-gall",
          host_qualifier_taxon_id: ctx.plant.id
        )

      stored = Catalog.get_gall!(gall.id)

      assert {stored.form_label, stored.descriptor, stored.host_qualifier_taxon_id} ==
               {"bud", "q-alba-gall", ctx.plant.id}
    end
  end
end
