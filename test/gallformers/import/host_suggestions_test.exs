defmodule Gallformers.Import.HostSuggestionsTest.FakeWcvp do
  @moduledoc "WCVP records for the Host suggestion tests, homonyms and synonyms included."
  @behaviour Gallformers.Wcvp.LookupBehaviour

  alias Gallformers.Wcvp.WcvpName

  @records [
    {"1", "Quercus fixtvelutina", "Lam.", "Accepted", "1"},
    {"2", "Quercus fixttinctoria", "Bartram", "Synonym", "1"},
    {"3", "Mulgfixt acuminatum", "Conrath & Freyn", "Illegitimate", "9"},
    {"4", "Mulgfixt acuminatum", "(Willd.) DC.", "Synonym", "5"},
    {"5", "Lactfixt floridana", "(L.) Gaertn.", "Accepted", "5"},
    {"6", "Rubus fixtellipticus", "Sm.", "Accepted", "6"},
    {"7", "Quercus fixtwislizeni", "A.DC.", "Accepted", "7"},
    {"8", "Quercus fixtnigra", "L.", "Accepted", "8"},
    {"9", "Lactfixt nonesuch", "Test", "Accepted", "9"},
    {"10", "Rubus × fixtloganobaccus", "L.H.Bailey", "Artificial Hybrid", "10"},
    {"11", "Rubus fixtursinus var. fixtloganobaccus", "(L.H.Bailey) L.H.Bailey", "Synonym", "10"},
    {"12", "Rubus fixtpensilvanicus", "Poir.", "Unplaced", ""},
    {"13", "Rubus fixtvillosus var. fixtfrondosus", "Bigelow ex Torr.", "Synonym", "12"},
    # Ashmead's "Q. chrysolepis var. vaccinifolia" is WCVP's var. vacciniifolia,
    # a synonym of Quercus vacciniifolia, not of Q. chrysolepis.
    {"14", "Quercus fixtchrysolepis", "Liebm.", "Accepted", "14"},
    {"15", "Quercus fixtchrysolepis var. fixtvacciniifolia", "(Hittell) Engelm.", "Synonym",
     "16"},
    {"16", "Quercus fixtvacciniifolia", "Hittell", "Accepted", "16"},
    # Near "Quercus prinos": Q. prinus is a Quercus; Q. prinodes and
    # Q. pruinosa are synonyms of plants in other genera.
    {"17", "Quercus fixtprinus", "L.", "Synonym", "18"},
    {"18", "Quercus fixtmichauxii", "Nutt.", "Accepted", "18"},
    {"19", "Quercus fixtprinodes", "Voigt", "Synonym", "20"},
    {"20", "Castanopsis fixtindica", "(Roxb. ex Lindl.) A.DC.", "Accepted", "20"},
    {"21", "Quercus fixtpruinosa", "Blume", "Synonym", "22"},
    {"22", "Lithocarpus fixtsundaicus", "(Blume) Rehder", "Accepted", "22"}
  ]

  def names do
    for {id, name, authors, status, accepted} <- @records do
      [genus | _] = String.split(name)

      %WcvpName{
        plant_name_id: id,
        taxon_name: name,
        taxon_authors: authors,
        taxon_status: status,
        accepted_plant_name_id: accepted,
        genus: genus,
        family: "Fixtaceae"
      }
    end
  end

  @impl true
  def available?, do: true

  @impl true
  def built_at, do: nil

  @impl true
  def search(query, opts \\ []) do
    prefix = String.downcase(query)

    names()
    |> Enum.filter(fn name ->
      String.starts_with?(String.downcase(name.taxon_name), prefix) and
        (opts[:include_synonyms] || name.taxon_status == "Accepted")
    end)
    |> Enum.take(Keyword.get(opts, :limit, 20))
  end

  @impl true
  def search_contains(_query, _opts \\ []), do: []

  @impl true
  def match_by_name(_name, _opts \\ []), do: nil

  @impl true
  def get(id), do: Enum.find(names(), &(&1.plant_name_id == id))

  @impl true
  def get_accepted_name(id) do
    case get(id) do
      %{accepted_plant_name_id: ^id} -> nil
      %{accepted_plant_name_id: accepted} -> get(accepted)
      nil -> nil
    end
  end
end

defmodule Gallformers.Import.HostSuggestionsTest do
  @moduledoc """
  Suggestions for a Host name the tree does not hold (queue triage rule F):
  the tree's spelling and ending variants, then WCVP — exact and synonym,
  ending variants, the species of a variety, and an edit distance of 1–2
  within the genus. Each names the tree's taxon (a synonym to add) or a
  WCVP record to add, with authors. Nothing is applied: the Host stays
  unresolved and holds the gall batch.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures, only: [plant_fixture: 1]

  alias Gallformers.Import.HostSuggestionsTest.FakeWcvp
  alias Gallformers.Import.Resolver
  alias Gallformers.Taxa

  defp host_batch(names) do
    taxa =
      for {name, i} <- Enum.with_index(names, 1),
          do: %{"ref" => "t#{i}", "name_as_written" => name, "rank" => "species"}

    facts =
      for i <- 1..length(names) do
        %{
          "id" => "f#{i}",
          "kind" => "relationship",
          "type" => "host_of",
          "stance" => "confirm",
          "subject" => "t#{i}",
          "object" => "g1"
        }
      end

    %{"batch_type" => "gall", "taxa" => taxa, "galls" => [], "facts" => facts}
  end

  defp resolve(batch, opts \\ []) do
    context = Resolver.context(batch, Keyword.merge([wcvp: FakeWcvp], opts))
    batch |> Resolver.resolve_taxa(context) |> Map.new(&{&1.ref, &1})
  end

  test "a Latin ending the tree holds in another form is proposed" do
    rubra = plant_fixture(name: "Quercus fixtrubra")
    %{"t1" => s} = resolve(host_batch(["Quercus fixtrubrum"]))

    assert s.resolution == :unresolved
    assert s.candidate_ids == [rubra.id]
    assert s.detail["proposed"] == rubra.id

    assert [
             %{
               "source" => "tree",
               "match" => "spelling_variant",
               "taxon_id" => id,
               "action" => "add_synonym"
             }
             | _
           ] =
             s.detail["suggestions"]

    assert id == rubra.id
  end

  test "a WCVP synonym proposes the tree's taxon for its accepted name, with authors" do
    plant_fixture(name: "Quercus", rank: :genus)
    velutina = plant_fixture(name: "Quercus fixtvelutina")

    %{"t1" => s} = resolve(host_batch(["Q. fixttinctoria", "Quercus alba"]))

    assert s.detail["proposed"] == velutina.id
    assert [suggestion | _] = s.detail["suggestions"]

    assert %{
             "source" => "wcvp",
             "match" => "synonym",
             "name" => "Quercus fixttinctoria",
             "authors" => "Bartram",
             "wcvp_id" => "2",
             "accepted" => %{
               "name" => "Quercus fixtvelutina",
               "authors" => "Lam.",
               "wcvp_id" => "1"
             },
             "action" => "add_synonym"
           } = suggestion

    assert suggestion["taxon_id"] == velutina.id
  end

  test "homonyms are all shown, the legitimate one first" do
    floridana = plant_fixture(name: "Lactfixt floridana")
    %{"t1" => s} = resolve(host_batch(["Mulgfixt acuminatum"]))

    assert [first, second] = s.detail["suggestions"]
    assert first["authors"] == "(Willd.) DC."
    assert first["taxon_id"] == floridana.id
    assert second["wcvp_status"] == "Illegitimate"
    assert second["action"] == "add_from_wcvp"
    assert s.detail["proposed"] == floridana.id
  end

  test "a WCVP name the tree does not hold is offered to add" do
    %{"t1" => s} = resolve(host_batch(["Rubus fixtellipticus"]))

    assert s.candidate_ids == []
    refute Map.has_key?(s.detail, "proposed")

    assert [
             %{
               "action" => "add_from_wcvp",
               "wcvp_id" => "6",
               "authors" => "Sm.",
               "taxon_id" => nil
             }
           ] =
             s.detail["suggestions"]
  end

  test "a hybrid written with x is looked up with the hybrid sign" do
    %{"t1" => s} = resolve(host_batch(["Rubus x fixtloganobaccus"]))
    assert [%{"wcvp_id" => "10", "action" => "add_from_wcvp"}] = s.detail["suggestions"]
  end

  test "an edit distance within the genus is a suggestion only, never proposed" do
    wislizeni = plant_fixture(name: "Quercus fixtwislizeni")
    %{"t1" => s} = resolve(host_batch(["Quercus fixtwisliceni"]))

    assert s.candidate_ids == [wislizeni.id]
    refute Map.has_key?(s.detail, "proposed")
    assert [%{"match" => "edit_distance", "taxon_id" => id}] = s.detail["suggestions"]
    assert id == wislizeni.id
  end

  test "a variety's near spelling is found over the whole name, before the variety's species" do
    chrysolepis = plant_fixture(name: "Quercus fixtchrysolepis")
    vacciniifolia = plant_fixture(name: "Quercus fixtvacciniifolia")

    %{"t1" => s} = resolve(host_batch(["Quercus fixtchrysolepis var. fixtvaccinifolia"]))

    refute Map.has_key?(s.detail, "proposed")

    assert [near, species] = s.detail["suggestions"]

    assert %{
             "source" => "wcvp",
             "match" => "edit_distance",
             "name" => "Quercus fixtchrysolepis var. fixtvacciniifolia",
             "wcvp_id" => "15",
             "accepted" => %{"name" => "Quercus fixtvacciniifolia"},
             "action" => "add_synonym"
           } = near

    assert near["taxon_id"] == vacciniifolia.id
    assert %{"match" => "species_of_infraspecies", "taxon_id" => id} = species
    assert id == chrysolepis.id
  end

  test "near spellings stay within the Source's genus" do
    %{"t1" => s} = resolve(host_batch(["QUERCUS FIXTPRINOS"]))

    refute Map.has_key?(s.detail, "proposed")

    assert [%{"match" => "edit_distance", "wcvp_id" => "17", "accepted" => accepted}] =
             s.detail["suggestions"]

    assert accepted["name"] == "Quercus fixtmichauxii"
  end

  test "a variety the tree does not hold suggests its species, but never proposes it" do
    nigra = plant_fixture(name: "Quercus fixtnigra")
    %{"t1" => s} = resolve(host_batch(["Quercus fixtnigra var. italica"]))

    refute Map.has_key?(s.detail, "proposed")
    assert [%{"match" => "species_of_infraspecies", "taxon_id" => id}] = s.detail["suggestions"]
    assert id == nigra.id
  end

  test "a variety WCVP sinks into another plant suggests that plant first, not its species" do
    # Rubus ursinus var. loganobaccus is the loganberry, Rubus × loganobaccus.
    ursinus = plant_fixture(name: "Rubus fixtursinus")
    %{"t1" => s} = resolve(host_batch(["Rubus fixtursinus var. fixtloganobaccus"]))

    refute Map.has_key?(s.detail, "proposed")

    assert [first, second] = s.detail["suggestions"]
    assert %{"match" => "species_of_infraspecies", "taxon_id" => id} = second
    assert id == ursinus.id

    assert %{
             "source" => "wcvp",
             "match" => "synonym",
             "action" => "add_from_wcvp",
             "accepted" => %{"name" => "Rubus × fixtloganobaccus"}
           } = first
  end

  test "a name WCVP leaves unplaced is shown, but not offered to add" do
    %{"t1" => s} = resolve(host_batch(["Rubus fixtpensilvanicus"]))

    assert [%{"wcvp_id" => "12", "wcvp_status" => "Unplaced"} = suggestion] =
             s.detail["suggestions"]

    refute Map.has_key?(suggestion, "action")
  end

  test "a synonym of a name WCVP leaves unplaced is shown, but not offered to add" do
    %{"t1" => s} = resolve(host_batch(["Rubus fixtvillosus var. fixtfrondosus"]))

    assert [
             %{"wcvp_id" => "13", "accepted" => %{"name" => "Rubus fixtpensilvanicus"}} =
               suggestion
           ] =
             s.detail["suggestions"]

    refute Map.has_key?(suggestion, "action")
  end

  test "a name WCVP leaves unplaced, held by the tree, is offered as the tree's plant" do
    plant = plant_fixture(name: "Rubus fixtpensilvanicus")
    %{"t1" => s} = resolve(host_batch(["Rubus fixtvillosus var. fixtfrondosus"]))

    assert [%{"action" => "add_synonym", "taxon_id" => id}] = s.detail["suggestions"]
    assert id == plant.id
  end

  test "nothing is applied: the Host stays unresolved, holds the batch and is queued with its suggestions" do
    plant_fixture(name: "Quercus fixtrubra")
    batch = host_batch(["Quercus fixtrubrum"])
    statements = Resolver.resolve_taxa(batch, Resolver.context(batch, wcvp: FakeWcvp))

    assert Resolver.holds_gall_batch?(statements) == true

    assert [
             %{
               kind: :unresolved_host,
               proposal: %{"proposed" => _, "suggestions" => [_ | _], "candidate_ids" => [_]}
             }
           ] =
             Resolver.queue_items(statements)
  end

  test "no suggestions: the item is as before" do
    %{"t1" => s} = resolve(host_batch(["Nonesuchia fixtimaginaria"]))

    assert s.resolution == :unresolved
    assert s.candidate_ids == []
    refute Map.has_key?(s.detail, "suggestions")
  end

  describe "a Host declared by its common name (d213 Task 6)" do
    # Quercus with two sections (the red oaks, Lobatae, and sect. Quercus),
    # its species under them; the genus's common name is "Fixtoaks".
    setup do
      quercus = plant_fixture(name: "Quercus", rank: :genus)
      lobatae = plant_fixture(name: "Lobatae", rank: :section, parent: quercus)
      white = plant_fixture(name: "Quercus", rank: :section, parent: quercus)
      velutina = plant_fixture(name: "Quercus fixtvelutina", parent: lobatae)
      marilandica = plant_fixture(name: "Quercus fixtmarilandica", parent: lobatae)
      plant_fixture(name: "Quercus fixtalba", parent: white)
      {:ok, _} = Taxa.add_common_name(test_actor(), quercus, "Fixtoaks")
      {:ok, _} = Taxa.add_common_name(test_actor(), lobatae, "Fixtred oaks")
      {:ok, _} = Taxa.add_common_name(test_actor(), velutina, "Fixtblack Oak")
      {:ok, _} = Taxa.add_common_name(test_actor(), marilandica, "Fixtblack-jack Oak")

      %{
        quercus: quercus,
        lobatae: lobatae,
        white: white,
        velutina: velutina,
        marilandica: marilandica
      }
    end

    defp quercus_and_sections(ctx) do
      {%{"taxon_id" => ctx.quercus.id, "name" => "Quercus"},
       [
         %{"taxon_id" => ctx.lobatae.id, "name" => "Lobatae", "common_name" => "Fixtred oaks"},
         %{"taxon_id" => ctx.white.id, "name" => "Quercus"}
       ]}
    end

    defp common_host(name) do
      batch = host_batch([name])

      put_in(batch, ["taxa", Access.at(0)], %{
        "ref" => "t1",
        "name_as_written" => name,
        "common_name" => true
      })
    end

    test "suggests Gallformers' plants of that common name, never proposed", ctx do
      %{"t1" => s} = resolve(common_host("the fixtblack oak"))

      assert s.resolution == :unresolved
      assert s.candidate_ids == [ctx.velutina.id]
      refute Map.has_key?(s.detail, "proposed")

      assert [suggestion] = s.detail["suggestions"]

      assert %{
               "source" => "tree",
               "match" => "common_name",
               "name" => "Quercus fixtvelutina",
               "common_name" => "Fixtblack Oak",
               "genus" => %{"taxon_id" => genus_id, "name" => "Quercus"}
             } = suggestion

      assert suggestion["taxon_id"] == ctx.velutina.id
      assert genus_id == ctx.quercus.id
      refute Map.has_key?(suggestion, "action")
    end

    test "reads hyphens, spaces, case and a leading article alike", ctx do
      for name <- ["Fixtblackjack oak", "a fixtblack jack oak", "FIXTBLACK-JACK OAK"] do
        %{"t1" => s} = resolve(common_host(name))
        assert s.candidate_ids == [ctx.marilandica.id], name
      end
    end

    test "names the genus its plants are in, and the genus's sections, from the tree", ctx do
      {genus, sections} = quercus_and_sections(ctx)
      %{"t1" => s} = resolve(common_host("the fixtblack oak"))

      assert s.detail["genus"] == genus
      assert s.detail["sections"] == sections
    end

    test "a bare common name with no plant of its own: the genus by its common name", ctx do
      {genus, sections} = quercus_and_sections(ctx)

      for name <- ["an unknown fixtoak", "some Fixtoaks", "a fixtoak tree"] do
        %{"t1" => s} = resolve(common_host(name))

        assert s.resolution == :unresolved, name
        assert s.candidate_ids == [], name
        refute Map.has_key?(s.detail, "suggestions"), name
        refute Map.has_key?(s.detail, "proposed"), name
        assert s.detail["genus"] == genus, name
        assert s.detail["sections"] == sections, name
        assert s.detail["reason"] =~ "Quercus", name
      end
    end

    test "a bare word that is a genus's name is that genus", ctx do
      {genus, _sections} = quercus_and_sections(ctx)
      %{"t1" => s} = resolve(common_host("an unknown quercus"))

      assert s.detail["genus"] == genus
    end

    test "the Host's queue item carries the genus and its sections", ctx do
      {genus, sections} = quercus_and_sections(ctx)
      batch = common_host("an unknown fixtoak")
      statements = Resolver.resolve_taxa(batch, Resolver.context(batch, wcvp: FakeWcvp))

      assert [%{kind: :unresolved_host, proposal: proposal}] = Resolver.queue_items(statements)
      assert proposal["genus"] == genus
      assert proposal["sections"] == sections
    end

    test "with no plant of that common name, it waits on a curator" do
      %{"t1" => s} = resolve(common_host("the fixtscrub oak"))

      assert s.resolution == :unresolved
      assert s.candidate_ids == []
      refute Map.has_key?(s.detail, "suggestions")
      assert s.detail["reason"] =~ "common name"
    end
  end
end
