defmodule Gallformers.Catalog.GallNameEditTest do
  @moduledoc """
  Deliberate edits of a Gall's name parts and override (`86e7` Task 2,
  `Gallformers.Catalog.update_name_parts/3`): applied directly — a curator's
  or a Gallformers batch's edit is the review — with the derived name
  recomputed, names shown kept unique ignoring case, and the ID tool's
  lookup table refreshed.

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.GallIndex

  setup do
    load_vocab!()
    source = source_fixture("Weld", "1959")
    genus = taxon_fixture(rank: :genus, name: "Fixturedita", kingdom: "Animalia")
    species = taxon_fixture(rank: :species, name: "Fixturedita saltrix", parent: genus)
    plant = plant_fixture(name: "Fixturquercus editensis")

    gall =
      gall_fixture(
        name: "Fixturedita saltrix (agamic)",
        generation: "agamic",
        gallformers_code: "fixturedita-code"
      )

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: species.id, object_gall_id: gall.id},
        confirm(source)
      )

    %{source: source, genus: genus, species: species, plant: plant, gall: gall}
  end

  defp edit(gall, attrs), do: Catalog.update_name_parts(test_actor(), gall, attrs)

  test "setting a form label renames the Gall", %{gall: gall} do
    assert {:ok, %Gall{} = edited} = edit(gall, %{form_label: "australis"})

    assert {edited.name, edited.form_label, edited.name_override} ==
             {"Fixturedita saltrix (australis) (agamic)", "australis", nil}

    assert Catalog.get_gall!(gall.id).name == "Fixturedita saltrix (australis) (agamic)"
  end

  test "a Host qualifier is written last", %{gall: gall, plant: plant} do
    assert {:ok, edited} =
             edit(gall, %{form_label: "bud", host_qualifier_taxon_id: plant.id})

    assert edited.name == "Fixturedita saltrix (bud) (agamic) (on Fixturquercus editensis)"
  end

  test "a Host qualifier must be a plant", %{gall: gall, genus: genus} do
    assert {:error, changeset} = edit(gall, %{host_qualifier_taxon_id: genus.id})
    assert %{host_qualifier_taxon_id: ["must be a plant"]} = errors_on(changeset)
  end

  test "clearing the override shows the derived name", %{gall: gall} do
    {:ok, overridden} = edit(gall, %{name_override: "Fixturedita saltrix, the old name"})
    assert Gall.display_name(overridden) == "Fixturedita saltrix, the old name"

    # The derived name follows the parts under an override too.
    {:ok, overridden} = edit(overridden, %{form_label: "texanus"})
    assert overridden.name == "Fixturedita saltrix (texanus) (agamic)"
    assert Gall.display_name(overridden) == "Fixturedita saltrix, the old name"

    assert {:ok, cleared} = edit(overridden, %{name_override: nil})
    assert cleared.name_override == nil
    assert Gall.display_name(cleared) == "Fixturedita saltrix (texanus) (agamic)"
  end

  test "a name shown by another Gall, in any case, is rejected and nothing changes", %{gall: gall} do
    gall_fixture(name: "FIXTUREDITA SALTRIX (australis) (agamic)")

    assert {:error, changeset} = edit(gall, %{form_label: "australis"})
    assert %{name: [message]} = errors_on(changeset)
    assert message =~ "another Gall"

    assert Catalog.get_gall!(gall.id) == gall
  end

  test "an override colliding with another Gall's name is rejected", %{gall: gall} do
    gall_fixture(name: "Fixturedita taken")

    assert {:error, changeset} = edit(gall, %{name_override: "fixturedita TAKEN"})
    assert %{name: [_message]} = errors_on(changeset)
  end

  test "parts that give no name need an override" do
    gall = gall_fixture(name: "Fixturedita undescribed gall")

    assert {:error, changeset} = edit(gall, %{form_label: "bud"})
    assert %{name: [message]} = errors_on(changeset)
    assert message =~ "override"
    assert Catalog.get_gall!(gall.id).form_label == nil

    # With an override the parts are kept; the stored name stays as it was.
    assert {:ok, edited} = edit(gall, %{form_label: "bud", name_override: "Fixturedita bud gall"})

    assert {edited.name, edited.form_label, Gall.display_name(edited)} ==
             {"Fixturedita undescribed gall", "bud", "Fixturedita bud gall"}
  end

  test "an undescribed Gall's descriptor names it", %{genus: genus, source: source} do
    gall = gall_fixture(name: "Fixturedita provisional")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: genus.id, object_gall_id: gall.id},
        confirm(source)
      )

    assert {:ok, edited} = edit(gall, %{descriptor: "q-alba-bead-gall"})
    assert edited.name == "Fixturedita q-alba-bead-gall"
  end

  test "the Gallformers code is never touched", %{gall: gall} do
    assert {:ok, edited} = edit(gall, %{form_label: "australis", gallformers_code: "other"})
    assert edited.gallformers_code == "fixturedita-code"
  end

  test "the edit is audited", %{gall: gall} do
    {:ok, _edited} = edit(gall, %{form_label: "australis"})

    [change] =
      Repo.all(
        from(c in test_audit_changes(),
          where: c.table_name == "galls" and c.op == :update and c.table_pk == ^["#{gall.id}"]
        )
      )

    # `updated_at` changes too unless the edit falls in the creation's second.
    assert Enum.sort(change.changed -- ["updated_at"]) == ["form_label", "name"]
  end

  test "the ID tool's lookup table shows the new name", %{gall: gall} do
    :ok = Catalog.refresh_gall_index([gall.id])
    assert Repo.get!(GallIndex, gall.id).name == "Fixturedita saltrix (agamic)"

    {:ok, _edited} = edit(gall, %{form_label: "australis"})

    assert Repo.get!(GallIndex, gall.id).name == "Fixturedita saltrix (australis) (agamic)"
  end
end
