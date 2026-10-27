defmodule Gallformers.Catalog.GallEditorialTest do
  @moduledoc """
  The Gall page's editorial fields (`a856` Task 4,
  `Gallformers.Catalog.update_gall_editorial/3`): the Gallformers code
  (unique), abundance, `datacomplete` (locked false for an undescribed Gall
  or one with no Sources) and the lead Source (one of the Gall's Sources);
  with the Gall's Sources (`Gallformers.Catalog.gall_sources/1`) and its
  current range adjustments (`Gallformers.Catalog.list_range_adjustments/1`).

  Abundances 1 (common) and 2 (uncommon) are seeded
  (`priv/repo/test_seeds.sql`).

  Not async: some tests use the Gallformers Source (see
  `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Sources

  setup do
    source = source_fixture("Weld", "1959")
    genus = taxon_fixture(rank: :genus, name: "Fixtureditoria", kingdom: "Animalia")
    species = taxon_fixture(rank: :species, name: "Fixtureditoria lecta", parent: genus)

    %{source: source, genus: genus, species: species}
  end

  defp inducer!(gall, taxon, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )

    gall
  end

  defp described_gall(%{species: species, source: source}, attrs \\ %{}),
    do: attrs |> gall_fixture() |> inducer!(species, source)

  defp cite!(gall, source) do
    {:ok, 1} =
      Catalog.insert_legacy_citations(test_actor(), [
        %{gall_id: gall.id, source_id: source.id, description: "Cited.", useasdefault: false}
      ])

    :ok
  end

  defp edit(gall, attrs), do: Catalog.update_gall_editorial(test_actor(), gall, attrs)

  describe "update_gall_editorial/3" do
    test "sets the Gallformers code, abundance and datacomplete", ctx do
      gall = described_gall(ctx)

      assert {:ok, %Gall{} = edited} =
               edit(gall, %{
                 gallformers_code: "  lecta-gall ",
                 abundance_id: 2,
                 datacomplete: true
               })

      assert {edited.gallformers_code, edited.abundance_id, edited.datacomplete} ==
               {"lecta-gall", 2, true}

      assert Catalog.get_gall!(gall.id) == edited
    end

    test "takes form params with string keys; a blank code or lead Source clears it", ctx do
      gall =
        described_gall(ctx, %{gallformers_code: "lecta-code", default_source_id: ctx.source.id})

      assert {:ok, edited} =
               edit(gall, %{
                 "gallformers_code" => "  ",
                 "default_source_id" => "",
                 "abundance_id" => "1"
               })

      assert {edited.gallformers_code, edited.default_source_id, edited.abundance_id} ==
               {nil, nil, 1}
    end

    test "touches nothing but the editorial fields", ctx do
      gall = described_gall(ctx, %{form_label: "bud"})

      assert {:ok, edited} =
               edit(gall, %{
                 name: "Other",
                 name_override: "Other",
                 form_label: nil,
                 abundance_id: 1
               })

      assert {edited.name, edited.name_override, edited.form_label} ==
               {gall.name, nil, "bud"}
    end

    test "a Gallformers code another Gall has is refused and nothing changes", ctx do
      gall_fixture(gallformers_code: "taken-code")
      gall = described_gall(ctx, %{abundance_id: 1})

      assert {:error, changeset} = edit(gall, %{gallformers_code: "taken-code", abundance_id: 2})
      assert %{gallformers_code: ["has already been taken"]} = errors_on(changeset)
      assert Catalog.get_gall!(gall.id) == gall
    end

    test "a Gall keeps its own Gallformers code", ctx do
      gall = described_gall(ctx, %{gallformers_code: "own-code"})

      assert {:ok, edited} = edit(gall, %{gallformers_code: "own-code", abundance_id: 2})
      assert edited.gallformers_code == "own-code"
    end

    test "an unknown abundance is refused", ctx do
      assert {:error, changeset} = edit(described_gall(ctx), %{abundance_id: 999_999})
      assert %{abundance_id: ["does not exist"]} = errors_on(changeset)
    end

    test "is audited", ctx do
      gall = described_gall(ctx)
      {:ok, _edited} = edit(gall, %{gallformers_code: "audited-code", abundance_id: 1})

      [change] =
        Repo.all(
          from(c in test_audit_changes(),
            where: c.table_name == "galls" and c.op == :update and c.table_pk == ^["#{gall.id}"]
          )
        )

      # `updated_at` changes too unless the edit falls in the creation's second.
      assert Enum.sort(change.changed -- ["updated_at"]) == ["abundance_id", "gallformers_code"]
    end
  end

  describe "gallformers_code_taken?/2" do
    test "another Gall's code is taken; the Gall's own is not", ctx do
      gall = described_gall(ctx, %{gallformers_code: "mine"})
      gall_fixture(gallformers_code: "theirs")

      assert Catalog.gallformers_code_taken?("theirs", gall.id) == true
      assert Catalog.gallformers_code_taken?(" theirs ", gall.id) == true
      assert Catalog.gallformers_code_taken?("mine", gall.id) == false
      assert Catalog.gallformers_code_taken?("mine") == true
      assert Catalog.gallformers_code_taken?("free", gall.id) == false
    end
  end

  describe "the datacomplete lock" do
    test "a Gall with no Sources is locked" do
      gall = gall_fixture()

      assert Catalog.datacomplete_lock(gall) == {:locked, :no_sources}
      assert {:error, changeset} = edit(gall, %{datacomplete: true})
      assert %{datacomplete: [message]} = errors_on(changeset)
      assert message =~ "no Sources"

      assert {:ok, %Gall{datacomplete: false}} =
               edit(gall, %{datacomplete: false, abundance_id: 1})
    end

    test "an undescribed Gall (no current species-rank Inducer) is locked", ctx do
      gall = gall_fixture() |> inducer!(ctx.genus, ctx.source)

      assert Catalog.datacomplete_lock(gall) == {:locked, :undescribed}
      assert {:error, changeset} = edit(gall, %{datacomplete: true})
      assert %{datacomplete: [message]} = errors_on(changeset)
      assert message =~ "undescribed"
    end

    test "a described Gall with Sources is not locked", ctx do
      gall = described_gall(ctx)

      assert Catalog.datacomplete_lock(gall) == :unlocked
      assert {:ok, %Gall{datacomplete: true}} = edit(gall, %{datacomplete: true})
    end

    test "is enforced on the stored value: a locked Gall saved complete must be cleared" do
      gall = gall_fixture(datacomplete: true)

      assert {:error, changeset} = edit(gall, %{abundance_id: 1})
      assert %{datacomplete: [_message]} = errors_on(changeset)

      assert {:ok, %Gall{datacomplete: false}} =
               edit(gall, %{abundance_id: 1, datacomplete: false})
    end
  end

  describe "the lead Source" do
    test "must be one of the Gall's Sources", ctx do
      gall = described_gall(ctx)
      other = source_fixture("Unrelated", "2001")

      assert {:error, changeset} = edit(gall, %{default_source_id: other.id})
      assert %{default_source_id: [message]} = errors_on(changeset)
      assert message =~ "Sources"
    end

    test "may be a Source attributing a current Fact, a cited Source or the note's Source", ctx do
      gall = described_gall(ctx)
      cited = source_fixture("Cited", "1920")
      cite!(gall, cited)
      gallformers = gallformers_source()
      {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "A note.")

      for source <- [ctx.source, cited, gallformers] do
        assert {:ok, %Gall{default_source_id: id}} = edit(gall, %{default_source_id: source.id})
        assert id == source.id
      end
    end
  end

  describe "gall_sources/1" do
    test "a Gall's cited, noted and current-Fact Sources, each once, by title", ctx do
      gall = described_gall(ctx)
      cited = source_fixture("Aardvark", "1920")
      cite!(gall, cited)
      cite!(gall, ctx.source)
      gallformers = gallformers_source()
      {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "A note.")

      sources = Catalog.gall_sources(gall.id)

      assert Enum.map(sources, & &1.id) ==
               [cited, gallformers, ctx.source] |> Enum.sort_by(& &1.title) |> Enum.map(& &1.id)
    end

    test "counts a qualifier's Source and a Relationship naming the Gall as its subject", ctx do
      gall = gall_fixture()
      other = gall_fixture()
      relationship_source = source_fixture("Alternation", "1990")
      qualifier_source = source_fixture("Qualifier", "1991")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "alternate_generation_of", subject_gall_id: gall.id, object_gall_id: other.id},
          confirm(relationship_source)
        )

      {:ok, %{fact: parasitism}} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "parasitoid_in", subject_taxon_id: taxon_fixture().id, object_gall_id: gall.id},
          confirm(ctx.source)
        )

      {:ok, _} =
        Catalog.assert_qualifier(
          test_actor(),
          %{of_fact_id: parasitism.id, qualifier: "parasitism_mode", value: "koinobiont"},
          confirm(qualifier_source)
        )

      assert gall.id |> Catalog.gall_sources() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([relationship_source.id, qualifier_source.id, ctx.source.id])
    end

    test "a Fact no longer current does not count", ctx do
      gall = gall_fixture()
      plant = plant_fixture()
      revision = source_fixture("Revision", "1990")

      for attribution <- [confirm(ctx.source), deny(revision)] do
        {:ok, _} =
          Catalog.assert_relationship(
            test_actor(),
            %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
            attribution
          )
      end

      assert Catalog.gall_sources(gall.id) == []
      assert Catalog.datacomplete_lock(gall) == {:locked, :no_sources}
    end
  end

  describe "list_abundances/0" do
    test "the abundance choices by ID" do
      assert [%{id: 1, abundance: "common"}, %{id: 2, abundance: "uncommon"} | _] =
               Catalog.list_abundances()
    end
  end

  describe "change_gall_editorial/2 and change_name_parts/2" do
    test "are the changesets the edits validate with, for a form", ctx do
      gall = described_gall(ctx)

      assert %Ecto.Changeset{changes: %{gallformers_code: "a-code"}} =
               Catalog.change_gall_editorial(gall, %{"gallformers_code" => " a-code "})

      assert %Ecto.Changeset{changes: %{form_label: "bud"}} =
               Catalog.change_name_parts(gall, %{"form_label" => "bud", "abundance_id" => "1"})
    end
  end

  describe "list_range_adjustments/1" do
    test "the current exclude and only adjustments with their places and attributions", ctx do
      gall = gall_fixture()
      later = source_fixture("Later", "2001")

      range! = fn adjustment, code, attribution ->
        {:ok, _} =
          Catalog.assert_range(
            test_actor(),
            %{gall_id: gall.id, adjustment: adjustment, place_id: place_id(code)},
            attribution
          )
      end

      range!.(:exclude, "US-CA", confirm(ctx.source))
      range!.(:only, "MX-JAL", confirm(ctx.source))
      # Newer statements win their slot: CA-AB's exclude is superseded by its only.
      range!.(:exclude, "CA-AB", confirm(ctx.source))
      range!.(:only, "CA-AB", confirm(later))

      assert [
               %{adjustment: :only, place_code: "CA-AB", attributions: [ca_attribution]},
               %{adjustment: :only, place_code: "MX-JAL"},
               %{adjustment: :exclude, place_code: "US-CA", place_id: us_ca} = us
             ] = Catalog.list_range_adjustments(gall.id)

      assert ca_attribution.source_id == later.id
      assert us_ca == place_id("US-CA")
      assert [%{source_id: source_id, stance: :confirm}] = us.attributions
      assert source_id == ctx.source.id
      assert is_binary(us.place_name)
      assert is_integer(us.fact_id)

      assert Catalog.list_range_adjustments(gall_fixture().id) == []
    end
  end
end
