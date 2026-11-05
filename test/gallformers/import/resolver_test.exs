defmodule Gallformers.Import.ResolverTest do
  @moduledoc """
  Resolving a batch's taxon names (`9449` Task 12; producer guide
  background, *What Gallformers does on import* steps 1–3): through
  `Gallformers.Taxa.resolve_name/2` with rank (and kingdom Plantae for
  Hosts), abbreviations expanded from genera the batch and document name,
  `name_reading` when `name_as_written` fails, 19th-century fused epithets.
  No fuzzy matching; a name the tree holds as a synonym while the Source
  treats it as valid is flagged, never merged silently.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]
  import Gallformers.TaxaFixtures

  alias Gallformers.Import.Resolver
  alias Gallformers.Taxa

  setup :audit_test_metadata

  defp taxon(ref, name, rank \\ "species", extra \\ %{}),
    do: Map.merge(%{"ref" => ref, "name_as_written" => name, "rank" => rank}, extra)

  defp gall_batch(taxa, extra \\ %{}) do
    Map.merge(%{"batch_type" => "gall", "taxa" => taxa, "galls" => [], "facts" => []}, extra)
  end

  defp host_fact(subject, object \\ "g1") do
    %{
      "id" => "f#{subject}",
      "kind" => "relationship",
      "type" => "host_of",
      "stance" => "confirm",
      "subject" => subject,
      "object" => object
    }
  end

  defp resolve(batch, opts \\ []) do
    context =
      Resolver.context(batch,
        taxonomy: opts[:taxonomy],
        document_texts: Keyword.get(opts, :document_texts, [])
      )

    batch |> Resolver.resolve_taxa(context) |> Map.new(&{&1.ref, &1})
  end

  describe "names" do
    test "an accepted name resolves exactly" do
      wasp = taxon_fixture(name: "Andricus quercuscalifornicus")
      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Andricus quercuscalifornicus")]))

      assert s.kind == :taxon
      assert s.resolution == :resolved
      assert s.method == "exact"
      assert s.taxon_id == wasp.id
      assert s.flags == []
    end

    test "a synonym resolves to its taxon when the Source only uses the name" do
      velutina = plant_fixture(name: "Quercus velutina")
      {:ok, _} = Taxa.add_synonym(test_actor(), velutina, "Quercus tinctoria")

      batch = gall_batch([taxon("t1", "Quercus tinctoria")], %{"facts" => [host_fact("t1")]})
      %{"t1" => s} = resolve(batch)

      assert s.resolution == :resolved
      assert s.method == "synonym"
      assert s.taxon_id == velutina.id
      assert s.flags == []
    end

    test "the rank filters" do
      genus = taxon_fixture(name: "Fixturicus", rank: :genus)
      taxon_fixture(name: "Fixturicus", rank: :subgenus)

      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Fixturicus", "genus")]))
      assert s.resolution == :resolved
      assert s.taxon_id == genus.id
    end

    test "a Host resolves among plants only" do
      plant = plant_fixture(name: "Morus rubra")
      taxon_fixture(name: "Morus rubra", kingdom: "Animalia")

      batch = gall_batch([taxon("t1", "Morus rubra")], %{"facts" => [host_fact("t1")]})
      %{"t1" => s} = resolve(batch)
      assert s.resolution == :resolved
      assert s.taxon_id == plant.id
      assert s.detail["host"] == true

      # The same name, not as a Host, is ambiguous.
      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Morus rubra")]))
      assert s.resolution == :ambiguous
      assert length(s.candidate_ids) == 2
    end

    test "a sensu name resolves to the misapplied usage" do
      taxon_fixture(name: "Cynips strobilana")
      other = taxon_fixture(name: "Cynips other")

      {:ok, _} =
        Taxa.add_synonym(test_actor(), other, "Cynips strobilana", sensu: "O. S. non Harris")

      %{"t1" => s} =
        resolve(
          gall_batch([
            taxon("t1", "Cynips strobilana", "species", %{"sensu" => "O. S. non Harris"})
          ])
        )

      assert s.resolution == :resolved
      assert s.taxon_id == other.id
    end

    test "no fuzzy matching" do
      plant_fixture(name: "Quercus lobata")
      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Quercus lobta")]))

      assert s.resolution == :unresolved
      assert s.taxon_id == nil
      assert s.candidate_ids == []
    end
  end

  describe "abbreviations" do
    test "are expanded from genera the batch names" do
      plant_fixture(name: "Quercus", rank: :genus)
      lobata = plant_fixture(name: "Quercus lobata")
      plant_fixture(name: "Quercus douglasii")

      batch = gall_batch([taxon("t1", "Q. lobata"), taxon("t2", "Quercus douglasii")])
      %{"t1" => s} = resolve(batch)

      assert s.resolution == :resolved
      assert s.method == "abbreviation"
      assert s.taxon_id == lobata.id
      assert s.detail["tried"] == "Quercus lobata"
    end

    test "are expanded from genera the document names, including genera printed in capitals" do
      plant_fixture(name: "Quercus", rank: :genus)
      prinus = plant_fixture(name: "Quercus prinus")

      batch = gall_batch([taxon("t1", "Q. prinus")])
      assert %{"t1" => %{resolution: :unresolved}} = resolve(batch)

      %{"t1" => s} = resolve(batch, document_texts: ["QUERCUS PRINOS.", "On the chestnut oak."])
      assert s.resolution == :resolved
      assert s.taxon_id == prinus.id
    end

    test "matching in several genera is ambiguous" do
      plant_fixture(name: "Carya", rank: :genus)
      plant_fixture(name: "Castanea", rank: :genus)
      a = plant_fixture(name: "Carya alba")
      b = plant_fixture(name: "Castanea alba")

      %{"t1" => s} =
        resolve(gall_batch([taxon("t1", "C. alba")]), document_texts: ["Carya and Castanea"])

      assert s.resolution == :ambiguous
      assert Enum.sort(s.candidate_ids) == Enum.sort([a.id, b.id])
    end
  end

  describe "name_reading and fused epithets" do
    test "name_reading is used when name_as_written fails" do
      wasp = taxon_fixture(name: "Cynips flocossa")

      %{"t1" => s} =
        resolve(
          gall_batch([
            taxon("t1", "Cynips Jlocossa", "species", %{"name_reading" => "Cynips flocossa"})
          ])
        )

      assert s.resolution == :resolved
      assert s.method == "name_reading"
      assert s.taxon_id == wasp.id
    end

    test "a 19th-century 'C. q. spongifica' is tried as the fused epithet" do
      wasp = taxon_fixture(name: "Andricus quercusspongifica")

      for written <- ["Cynips q. spongifica", "C. quercus-spongifica", "C.Q. SPONGIFICA"] do
        %{"t1" => s} = resolve(gall_batch([taxon("t1", written)]))
        assert s.resolution == :resolved, written
        assert s.method == "fused_epithet"
        assert s.taxon_id == wasp.id
      end
    end

    test "a fused epithet in several genera is ambiguous" do
      taxon_fixture(name: "Andricus quercusfusa")
      taxon_fixture(name: "Callirhytis quercusfusa")

      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Cynips q. fusa")]))
      assert s.resolution == :ambiguous
      assert length(s.candidate_ids) == 2
    end
  end

  describe "new taxa and the taxonomy batch" do
    defp taxonomy(taxa, acts),
      do: %{"batch_type" => "taxonomy", "taxa" => taxa, "acts" => acts}

    defp act(id, kind, fields),
      do:
        Map.merge(%{"id" => id, "kind" => kind, "stance" => "confirm", "evidence" => []}, fields)

    test "a taxon the Source presents as new is new" do
      tb =
        taxonomy(
          [taxon("t1", "Andricus exemplaris", "species", %{"new" => %{"status" => "sp. nov."}})],
          [act("a1", "name", %{"taxon" => "t1"})]
        )

      %{"t1" => s} = resolve(tb, taxonomy: tb)
      assert s.resolution == :new
      assert s.detail["new_status"] == "sp. nov."
    end

    test "a gall batch's taxon the taxonomy batch presents as new is new" do
      tb =
        taxonomy(
          [taxon("t1", "Andricus exemplaris", "species", %{"new" => %{"status" => "sp. nov."}})],
          [act("a1", "name", %{"taxon" => "t1"})]
        )

      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Andricus exemplaris")]), taxonomy: tb)
      assert s.resolution == :new
    end

    test "a name the tree holds as a synonym, which the Source treats as valid, is flagged, not merged" do
      accepted = taxon_fixture(name: "Callirhytis quercusexempla")
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Andricus quercusexempla")

      tb =
        taxonomy(
          [taxon("t1", "Andricus quercusexempla"), taxon("t2", "Andricus", "genus")],
          [act("a1", "placement", %{"taxon" => "t1", "parent" => "t2"})]
        )

      %{"t1" => s} = resolve(tb, taxonomy: tb)
      assert s.resolution == :unresolved
      assert s.taxon_id == nil
      assert "synonym_held_valid" in s.flags
      assert s.candidate_ids == [accepted.id]

      # The gall batch's use of the name does not resolve through it either.
      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Andricus quercusexempla")]), taxonomy: tb)
      assert s.resolution == :unresolved
      assert "synonym_held_valid" in s.flags
    end

    test "a name the Source itself sinks as a synonym resolves through the tree's synonym" do
      accepted = taxon_fixture(name: "Andricus quercusprimus")
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Callirhytis quercusprimus")

      tb =
        taxonomy(
          [taxon("t1", "Callirhytis quercusprimus"), taxon("t2", "Andricus quercusprimus")],
          [act("a1", "synonymy", %{"name" => "t1", "accepted" => "t2"})]
        )

      %{"t1" => s} = resolve(tb, taxonomy: tb)
      assert s.resolution == :resolved
      assert s.flags == []
      assert s.taxon_id == accepted.id
    end
  end

  # A family with two of its genera, for the rules that look within a family.
  defp fixt_family do
    family = taxon_fixture(name: "Fixtidae", rank: :family)

    %{
      family: family,
      old_genus: taxon_fixture(name: "Oldfixtus", rank: :genus, parent: family),
      new_genus: taxon_fixture(name: "Newfixtus", rank: :genus, parent: family)
    }
  end

  defp new_species(ref, name, extra \\ %{}),
    do: taxon(ref, name, "species", Map.merge(%{"new" => %{"status" => "new species"}}, extra))

  # The taxonomy batch of an original description: each taxon named, and
  # placed under `parent` when given.
  defp description(taxa, parents \\ %{}) do
    names =
      for {t, i} <- Enum.with_index(taxa, 1), do: act("n#{i}", "name", %{"taxon" => t["ref"]})

    placements =
      for {{child, parent}, i} <- Enum.with_index(parents, 1),
          do: act("p#{i}", "placement", %{"taxon" => child, "parent" => parent})

    taxonomy(taxa, names ++ placements)
  end

  describe "an original description against a later tree (rule C)" do
    setup do: fixt_family()

    test "a new name the tree holds as a synonym with the same epithet resolves to the tree's taxon",
         %{new_genus: genus} do
      accepted = taxon_fixture(name: "Newfixtus morrisoni", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus morrisoni")

      tb = description([new_species("t1", "OLDFIXTUS MORRISONI")])
      %{"t1" => s} = resolve(tb, taxonomy: tb)

      assert s.resolution == :resolved
      assert s.taxon_id == accepted.id
      assert s.flags == ["original_combination"]

      # The gall batch's use of it too, and neither is queued.
      statements =
        Resolver.resolve_taxa(
          gall_batch([taxon("t1", "OLDFIXTUS MORRISONI")]),
          Resolver.context(gall_batch([]), taxonomy: tb)
        )

      assert [%{resolution: :resolved, flags: ["original_combination"]}] = statements
      assert Resolver.queue_items(statements) == []
    end

    test "an epithet in another gender is the same epithet", %{new_genus: genus} do
      accepted = taxon_fixture(name: "Newfixtus sulcata", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus sulcatus")

      tb = description([new_species("t1", "OLDFIXTUS SULCATUS")])

      assert %{"t1" => %{resolution: :resolved, flags: ["original_combination"]}} =
               resolve(tb, taxonomy: tb)
    end

    test "a synonym with another epithet (heterotypic) stays a disagreement", %{new_genus: genus} do
      accepted = taxon_fixture(name: "Newfixtus clarkei", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus vesiculoides")

      tb = description([new_species("t1", "OLDFIXTUS VESICULOIDES")])
      %{"t1" => s} = resolve(tb, taxonomy: tb)

      assert s.resolution == :unresolved
      assert s.flags == ["synonym_held_valid"]
    end

    test "not across families: the synonym's genus is in another family than the taxon" do
      eulophid_family = taxon_fixture(name: "Otherfixtidae", rank: :family)
      eulophid_genus = taxon_fixture(name: "Smilfixtus", rank: :genus, parent: eulophid_family)
      accepted = taxon_fixture(name: "Smilfixtus smilacis", parent: eulophid_genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus smilacis")

      tb = description([new_species("t1", "OLDFIXTUS SMILACIS")])
      %{"t1" => s} = resolve(tb, taxonomy: tb)

      assert s.resolution == :unresolved
      assert s.flags == ["synonym_held_valid"]
    end

    test "a genus the tree doesn't hold is placed by the tree's other names in it",
         %{new_genus: genus} do
      accepted = taxon_fixture(name: "Newfixtus emoryi", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Lostfixtus emoryi")
      tb = description([new_species("t1", "LOSTFIXTUS EMORYI")])

      # No other name in Lostfixtus: its family is unknown, so it stays.
      assert %{"t1" => %{resolution: :unresolved}} = resolve(tb, taxonomy: tb)

      other = taxon_fixture(name: "Newfixtus radicola", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), other, "Lostfixtus radicola")

      assert %{"t1" => %{resolution: :resolved, flags: ["original_combination"]}} =
               resolve(tb, taxonomy: tb)
    end

    test "not when the Source does not present the name as new", %{new_genus: genus} do
      accepted = taxon_fixture(name: "Newfixtus apicalis", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus apicalis")

      tb = description([taxon("t1", "OLDFIXTUS APICALIS")])

      assert %{"t1" => %{resolution: :unresolved, flags: ["synonym_held_valid"]}} =
               resolve(tb, taxonomy: tb)
    end
  end

  describe "an old genus used only as a parent (rule D)" do
    setup do: fixt_family()

    setup %{new_genus: genus} do
      for epithet <- ["radicola", "apicalis"] do
        accepted = taxon_fixture(name: "Newfixtus #{epithet}", parent: genus)
        {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Lostfixtus #{epithet}")
      end

      :ok
    end

    test "is not queued when every species placed in it resolves elsewhere" do
      tb =
        description(
          [
            taxon("t1", "LOSTFIXTUS", "genus"),
            new_species("t2", "LOSTFIXTUS RADICOLA"),
            taxon("t3", "LOSTFIXTUS APICALIS")
          ],
          %{"t2" => "t1", "t3" => "t1"}
        )
        |> Map.update!("acts", &Enum.reject(&1, fn a -> a["taxon"] == "t1" end))

      statements = Resolver.resolve_taxa(tb, Resolver.context(tb, taxonomy: tb))
      %{"t1" => genus} = Map.new(statements, &{&1.ref, &1})

      assert genus.resolution == :unresolved
      assert "parent_only" in genus.flags
      refute Enum.any?(Resolver.queue_items(statements), &(&1.statement_ref == "t1"))
    end

    test "is queued when a species placed in it is new" do
      tb =
        taxonomy(
          [
            taxon("t1", "LOSTFIXTUS", "genus"),
            new_species("t2", "LOSTFIXTUS RADICOLA"),
            new_species("t3", "LOSTFIXTUS PUNCTATISSIMA")
          ],
          [
            act("a1", "placement", %{"taxon" => "t2", "parent" => "t1"}),
            act("a2", "placement", %{"taxon" => "t3", "parent" => "t1"})
          ]
        )

      statements = Resolver.resolve_taxa(tb, Resolver.context(tb, taxonomy: tb))

      assert %{resolution: :new} = Enum.find(statements, &(&1.ref == "t3"))

      assert %{kind: :unresolved_name} =
               Enum.find(Resolver.queue_items(statements), &(&1.statement_ref == "t1"))
    end

    test "is queued when another act names it" do
      tb =
        taxonomy(
          [taxon("t1", "LOSTFIXTUS", "genus"), new_species("t2", "LOSTFIXTUS RADICOLA")],
          [
            act("a1", "name", %{"taxon" => "t1"}),
            act("a2", "placement", %{"taxon" => "t2", "parent" => "t1"})
          ]
        )

      statements = Resolver.resolve_taxa(tb, Resolver.context(tb, taxonomy: tb))

      assert %{kind: :unresolved_name} =
               Enum.find(Resolver.queue_items(statements), &(&1.statement_ref == "t1"))
    end
  end

  describe "a name is not new when the tree holds its epithet (rule G)" do
    setup do: fixt_family()

    test "an ending variant is proposed, not resolved", %{old_genus: genus} do
      held = taxon_fixture(name: "Oldfixtus gemmae", parent: genus)
      tb = description([new_species("t1", "OLDFIXTUS GEMMA")])

      statements = Resolver.resolve_taxa(tb, Resolver.context(tb, taxonomy: tb))
      [s] = statements

      assert s.resolution == :ambiguous
      assert s.method == "spelling_variant"
      assert s.taxon_id == nil
      assert s.candidate_ids == [held.id]
      assert s.detail["proposed"] == held.id
      assert s.detail["new_status"] == "new species"
      assert s.detail["reason"] =~ "Oldfixtus gemmae"

      assert [%{kind: :ambiguous_match, proposal: %{"candidate_ids" => [id], "proposed" => id}}] =
               Resolver.queue_items(statements)

      assert id == held.id
    end

    test "ii and i, æ and a", %{old_genus: genus} do
      vaccini = taxon_fixture(name: "Oldfixtus vaccinifoliae", parent: genus)
      ambrosia = taxon_fixture(name: "Oldfixtus ambrosiacola", parent: genus)

      tb =
        description([
          new_species("t1", "OLDFIXTUS VACCINIIFOLIZ", %{
            "name_reading" => "OLDFIXTUS VACCINIIFOLIÆ"
          }),
          new_species("t2", "OLDFIXTUS AMBROSIÆCOLA")
        ])

      assert %{
               "t1" => %{resolution: :ambiguous, candidate_ids: [v]},
               "t2" => %{candidate_ids: [a]}
             } =
               resolve(tb, taxonomy: tb)

      assert v == vaccini.id
      assert a == ambrosia.id
    end

    test "the epithet alone, in the genus's family only", %{new_genus: genus} do
      held = taxon_fixture(name: "Newfixtus dasydactyli", parent: genus)
      elsewhere = taxon_fixture(name: "Farfixtus", rank: :genus)
      taxon_fixture(name: "Farfixtus dasydactyli", parent: elsewhere)

      tb = description([new_species("t1", "OLDFIXTUS DASYDACTYLI")])
      %{"t1" => s} = resolve(tb, taxonomy: tb)

      assert s.resolution == :ambiguous
      assert s.method == "epithet_in_family"
      assert s.candidate_ids == [held.id]
      assert s.detail["reason"] =~ "Fixtidae"
    end

    test "an abbreviated genus takes its family from the genera it expands to", %{
      new_genus: genus
    } do
      held = taxon_fixture(name: "Newfixtus vesicula", parent: genus)

      %{"t1" => s} =
        resolve(gall_batch([taxon("t1", "O. vesicula")]), document_texts: ["OLDFIXTUS"])

      assert s.resolution == :ambiguous
      assert s.candidate_ids == [held.id]
    end

    test "C. q. X is tried as Cynips X and Cynips quercus X", %{new_genus: genus} do
      a = taxon_fixture(name: "Newfixtus confluentissima", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), a, "Cynips fixtaciculata")
      b = taxon_fixture(name: "Newfixtus quercusfixtspongia", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), b, "Cynips quercus fixtcoccinea")

      batch =
        gall_batch([
          taxon("t1", "C. Q. fixtaciculata"),
          taxon("t2", "C. Q. cocctnem", "species", %{"name_reading" => "C. Q. fixtcoccineæ"})
        ])

      assert %{
               "t1" => %{resolution: :ambiguous, method: "cynips_name", candidate_ids: [ida]},
               "t2" => %{resolution: :ambiguous, candidate_ids: [idb]}
             } = resolve(batch)

      assert ida == a.id
      assert idb == b.id
    end

    test "a fused epithet in another ending is proposed" do
      held = taxon_fixture(name: "Andricus quercusfixtstrobilanus")
      %{"t1" => s} = resolve(gall_batch([taxon("t1", "C. q. fixtstrobilana")]))

      assert s.resolution == :ambiguous
      assert s.candidate_ids == [held.id]
    end

    test "a name with nothing like it in the tree stays new" do
      tb = description([new_species("t1", "OLDFIXTUS FLAVICOLLISSIMA")])
      assert %{"t1" => %{resolution: :new}} = resolve(tb, taxonomy: tb)
    end
  end

  describe "a held-valid name the Source describes as new, in a gall batch (rule H)" do
    setup do: fixt_family()

    test "proposes the tree's taxon", %{new_genus: genus} do
      accepted = taxon_fixture(name: "Newfixtus clarkei", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus vesiculoides")
      tb = description([new_species("t1", "OLDFIXTUS VESICULOIDES")])

      statements =
        Resolver.resolve_taxa(
          gall_batch([taxon("t1", "OLDFIXTUS VESICULOIDES")]),
          Resolver.context(gall_batch([]), taxonomy: tb)
        )

      assert [%{resolution: :unresolved, flags: ["synonym_held_valid"]} = s] = statements
      assert s.detail["proposed"] == accepted.id

      assert [%{kind: :taxonomy_disagreement, proposal: %{"proposed" => id}}] =
               Resolver.queue_items(statements)

      assert id == accepted.id

      # The taxonomy batch's own item is not one-click.
      %{"t1" => s} = resolve(tb, taxonomy: tb)
      refute Map.has_key?(s.detail, "proposed")
    end

    test "not across families" do
      family = taxon_fixture(name: "Otherfixtidae", rank: :family)
      genus = taxon_fixture(name: "Smilfixtus", rank: :genus, parent: family)
      accepted = taxon_fixture(name: "Smilfixtus smilax", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus smilacis")
      tb = description([new_species("t1", "OLDFIXTUS SMILACIS")])

      %{"t1" => s} = resolve(gall_batch([taxon("t1", "OLDFIXTUS SMILACIS")]), taxonomy: tb)
      assert s.flags == ["synonym_held_valid"]
      refute Map.has_key?(s.detail, "proposed")
    end

    test "not when the Source does not describe it as new", %{new_genus: genus} do
      accepted = taxon_fixture(name: "Newfixtus tartareus", parent: genus)
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Oldfixtus junctisensoriatus")
      tb = description([taxon("t1", "Oldfixtus junctisensoriatus")])

      %{"t1" => s} =
        resolve(gall_batch([taxon("t1", "Oldfixtus junctisensoriatus")]), taxonomy: tb)

      assert s.flags == ["synonym_held_valid"]
      refute Map.has_key?(s.detail, "proposed")
    end
  end

  describe "an accepted-name hit beats a synonym hit (rule J)" do
    test "is proposed among the candidates" do
      accepted = taxon_fixture(name: "Fixtpemphigus populitransversus")
      other = taxon_fixture(name: "Fixtpemphigus obesinymphae")
      {:ok, _} = Taxa.add_synonym(test_actor(), other, "Fixtpemphigus populitransversus")

      statements =
        Resolver.resolve_taxa(
          gall_batch([taxon("t1", "Fixtpemphigus populitransversus")]),
          Resolver.context(gall_batch([]))
        )

      assert [%{resolution: :ambiguous} = s] = statements
      assert Enum.sort(s.candidate_ids) == Enum.sort([accepted.id, other.id])
      assert s.detail["proposed"] == accepted.id

      assert [%{kind: :ambiguous_match, proposal: %{"proposed" => id}}] =
               Resolver.queue_items(statements)

      assert id == accepted.id
    end

    test "nothing is proposed when several accepted names match" do
      taxon_fixture(name: "Fixtmorus rubra")
      taxon_fixture(name: "Fixtmorus rubra")

      %{"t1" => s} = resolve(gall_batch([taxon("t1", "Fixtmorus rubra")]))
      assert s.resolution == :ambiguous
      refute Map.has_key?(s.detail, "proposed")
    end
  end

  describe "queue_items/1" do
    test "unresolved Hosts, unresolved and ambiguous names, and held-valid synonyms" do
      plant_fixture(name: "Carya", rank: :genus)
      plant_fixture(name: "Castanea", rank: :genus)
      plant_fixture(name: "Carya alba")
      plant_fixture(name: "Castanea alba")
      accepted = taxon_fixture(name: "Callirhytis quercusheld")
      {:ok, _} = Taxa.add_synonym(test_actor(), accepted, "Andricus quercusheld")

      tb = %{
        "batch_type" => "taxonomy",
        "taxa" => [taxon("t1", "Andricus quercusheld")],
        "acts" => [%{"id" => "a1", "kind" => "name", "stance" => "confirm", "taxon" => "t1"}]
      }

      batch =
        gall_batch(
          [
            taxon("t1", "Quercus tinctoria"),
            taxon("t2", "Nonesuch imaginaria"),
            taxon("t3", "C. alba"),
            taxon("t4", "Andricus quercusheld")
          ],
          %{"facts" => [host_fact("t1")]}
        )

      statements =
        Resolver.resolve_taxa(
          batch,
          Resolver.context(batch, taxonomy: tb, document_texts: ["Carya, Castanea"])
        )

      items = statements |> Resolver.queue_items() |> Map.new(&{&1.statement_ref, &1})

      assert %{kind: :unresolved_host, subject: %{"name_as_written" => "Quercus tinctoria"}} =
               items["t1"]

      assert %{kind: :unresolved_name} = items["t2"]
      assert %{kind: :ambiguous_match, proposal: %{"candidate_ids" => [_, _]}} = items["t3"]

      assert %{kind: :taxonomy_disagreement, proposal: %{"candidate_ids" => [id]}} = items["t4"]
      assert id == accepted.id
    end
  end

  describe "a Host declared by its common name (d213 Task 6)" do
    defp common(ref, name), do: %{"ref" => ref, "name_as_written" => name, "common_name" => true}

    test "is never resolved, even when its words are a name the tree holds" do
      plant_fixture(name: "Quercus fixtcommonis")
      batch = gall_batch([common("t1", "Quercus fixtcommonis")], %{"facts" => [host_fact("t1")]})
      %{"t1" => s} = resolve(batch)

      assert s.resolution == :unresolved
      assert s.taxon_id == nil
      assert s.detail["common_name"] == true
      refute Map.has_key?(s.detail, "proposed")
    end

    test "is an unresolved Host item that holds the gall batch" do
      batch = gall_batch([common("t1", "the fixtblack oak")], %{"facts" => [host_fact("t1")]})
      statements = Resolver.resolve_taxa(batch, Resolver.context(batch))

      assert [
               %{
                 kind: :unresolved_host,
                 subject: %{
                   "name_as_written" => "the fixtblack oak",
                   "common_name" => true,
                   "host" => true
                 }
               }
             ] = Resolver.queue_items(statements)

      assert Resolver.holds_gall_batch?(statements) == true
    end
  end
end
