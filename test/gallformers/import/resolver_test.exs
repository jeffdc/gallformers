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
end
