defmodule Gallformers.Import.ReviewContextTest.FakeWcvp do
  @moduledoc "WCVP records for the Host panel tests."
  @behaviour Gallformers.Wcvp.LookupBehaviour

  alias Gallformers.Wcvp.WcvpName

  @records [
    {"1", "Quercus rcxalba", "L.", "Accepted", "1"},
    {"2", "Quercus rcxprinos", "L.", "Synonym", "3"},
    {"3", "Quercus rcxmichauxii", "Nutt.", "Accepted", "3"},
    {"4", "Quercus rcxvelutina", "Lam.", "Accepted", "4"},
    {"5", "Quercus rcxrubra", "L.", "Accepted", "5"}
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
        family: "Fagaceae"
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
      %{accepted_plant_name_id: accepted} when accepted not in [nil, "", id] -> get(accepted)
      _ -> nil
    end
  end
end

defmodule Gallformers.Import.ReviewContextTest do
  @moduledoc """
  What the review pages' questions need from the database (`d213` Task 13):
  a taxon's identity line and whether it holds the Source's name, what WCVP
  and Gallformers hold for a Host name, a candidate Gall's photos, Sources
  and whether its description quotes this Source, and the package's
  `document.json`.

  Not async: the tests load the vocabularies (`Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Images
  alias Gallformers.Import.Package
  alias Gallformers.Import.ReviewContext
  alias Gallformers.Import.ReviewContextTest.FakeWcvp
  alias Gallformers.Storage.Private
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    %{source: source_fixture("Ashmead", "1896")}
  end

  defp relate!(type, taxon, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )
  end

  describe "taxon/1" do
    test "is the taxon's name, rank, authorship, family, synonyms, Galls and their Hosts",
         %{source: source} do
      family = taxon_fixture(name: "Rcxcynipidae", rank: :family)
      genus = taxon_fixture(name: "Rcxandricus", rank: :genus, parent: family)

      species =
        taxon_fixture(
          name: "Rcxandricus wisliceni",
          parent: genus,
          authorship: "Ashmead, 1896"
        )

      {:ok, _} = Taxa.add_synonym(test_actor(), species, "Cynips wisliceni")
      {:ok, _} = Taxa.add_synonym(test_actor(), species, "Rcxandricus wislizeni")

      oak = plant_fixture(name: "Quercus rcxwislizeni")
      maple = plant_fixture(name: "Acer rcxrubrum")
      agamic = gall_fixture(name: "Rcx agamic gall")
      sexgen = gall_fixture(name: "Rcx sexgen gall")

      for gall <- [agamic, sexgen], do: relate!("inducer_of", species, gall, source)
      relate!("host_of", oak, agamic, source)
      relate!("host_of", oak, sexgen, source)
      relate!("host_of", maple, sexgen, source)

      assert %{
               taxon_id: id,
               name: "Rcxandricus wisliceni",
               rank: :species,
               authorship: "Ashmead, 1896",
               family: "Rcxcynipidae",
               synonyms: ["Cynips wisliceni", "Rcxandricus wislizeni"],
               galls: galls,
               hosts: hosts
             } = ReviewContext.taxon(species.id)

      assert id == species.id
      assert Enum.map(galls, & &1.name) == ["Rcx agamic gall", "Rcx sexgen gall"]
      assert Enum.map(galls, & &1.id) == [agamic.id, sexgen.id]

      assert hosts == [
               %{taxon_id: maple.id, name: "Acer rcxrubrum"},
               %{taxon_id: oak.id, name: "Quercus rcxwislizeni"}
             ]
    end

    test "has no family, authorship, Galls or Hosts when the tree records none" do
      species = taxon_fixture(name: "Rcxlonely species")

      assert %{family: nil, authorship: nil, synonyms: [], galls: [], hosts: []} =
               ReviewContext.taxon(species.id)
    end

    test "is nil for a taxon there is not" do
      assert ReviewContext.taxon(-1) == nil
    end
  end

  describe "holds_name/2" do
    setup do
      %{
        taxon: %{
          name: "Andricus californicus",
          synonyms: ["Cynips californica", "Andricus wisliceni", "Callirhytis rcxseminosa"]
        }
      }
    end

    test "the accepted name or a synonym, compared normalized, is held exactly", %{taxon: t} do
      assert ReviewContext.holds_name(t, "Andricus californicus") == :exact
      assert ReviewContext.holds_name(t, "ANDRICUS  WISLICENI") == :exact
    end

    test "a synonym sharing the epithet's first six letters in the same genus is a close spelling",
         %{taxon: t} do
      assert ReviewContext.holds_name(t, "Andricus wislicenii") ==
               {:close_spelling, "Andricus wisliceni"}
    end

    test "in another genus it is the same epithet in another genus", %{taxon: t} do
      assert ReviewContext.holds_name(t, "Andricus californica") ==
               {:same_epithet_other_genus, "Cynips californica"}
    end

    test "otherwise the name is not held", %{taxon: t} do
      assert ReviewContext.holds_name(t, "Andricus dasydactyli") == :no
    end
  end

  describe "host/2" do
    test "the WCVP record of the name as written, accepted, and the plant Gallformers holds" do
      plant = plant_fixture(name: "Quercus rcxalba")

      assert ReviewContext.host("Quercus rcxalba", wcvp: FakeWcvp) == %{
               written: "Quercus rcxalba",
               match: :exact,
               wcvp: %{id: "1", name: "Quercus rcxalba", authors: "L.", status: "Accepted"},
               accepted: nil,
               held: %{taxon_id: plant.id, name: "Quercus rcxalba"}
             }
    end

    test "a WCVP synonym gives its accepted name; Gallformers holds neither" do
      assert %{
               match: :exact,
               wcvp: %{id: "2", status: "Synonym"},
               accepted: %{id: "3", name: "Quercus rcxmichauxii", authors: "Nutt."},
               held: nil
             } = ReviewContext.host("Quercus rcxprinos", wcvp: FakeWcvp)
    end

    test "a name WCVP doesn't hold gives its nearest spelling in the genus" do
      assert %{match: :near, wcvp: %{id: "4", name: "Quercus rcxvelutina"}, held: nil} =
               ReviewContext.host("Quercus rcxvelutna", wcvp: FakeWcvp)
    end

    test "a name the tree holds in another ending gives that spelling's WCVP record" do
      plant = plant_fixture(name: "Quercus rcxrubra")

      assert %{
               match: :near,
               wcvp: %{id: "5", name: "Quercus rcxrubra"},
               held: %{taxon_id: id}
             } = ReviewContext.host("Quercus rcxrubrum", wcvp: FakeWcvp)

      assert id == plant.id
    end

    test "a plant Gallformers holds that WCVP doesn't is held, with nothing from WCVP" do
      plant = plant_fixture(name: "Quercus rcxlocalis")

      assert %{match: nil, wcvp: nil, accepted: nil, held: %{taxon_id: id}} =
               ReviewContext.host("Quercus rcxlocalis", wcvp: FakeWcvp)

      assert id == plant.id
    end

    test "nothing anywhere: every field nil but the name" do
      assert ReviewContext.host("Rcxnowhere plantus", wcvp: FakeWcvp) == %{
               written: "Rcxnowhere plantus",
               match: nil,
               wcvp: nil,
               accepted: nil,
               held: nil
             }
    end
  end

  describe "gall/2" do
    @described "Gall.—A small, hard, globular gall, occurring on the twigs of the black oak."

    setup %{source: source} do
      gall = gall_fixture()
      other = source_fixture("Beutenmuller", "1904")

      {:ok, 2} =
        Catalog.insert_legacy_citations(test_actor(), [
          %{gall_id: gall.id, source_id: source.id, description: "Ashmead: " <> @described},
          %{gall_id: gall.id, source_id: other.id, description: "Another description."}
        ])

      for i <- 1..3 do
        {:ok, _} = Images.create_image(%{gall_id: gall.id, path: "gall/#{gall.id}/rcx#{i}.jpg"})
      end

      %{gall: gall}
    end

    test "counts the Gall's photos and Sources, and finds the description quoting the text",
         %{gall: gall, source: source} do
      # Line breaks and spacing as the Source's document has them.
      text = "Gall.—A small, hard,\nglobular  gall, occurring on the twigs"

      assert ReviewContext.gall(gall.id, text) == %{
               gall_id: gall.id,
               photos: 3,
               sources: 2,
               quoted_in: source.title,
               description: "Ashmead: " <> @described
             }
    end

    test "the description is the default Source's, else the first with one", ctx do
      %{gall: gall, source: source} = ctx
      other = Enum.find(Catalog.gall_sources(gall.id), &(&1.id != source.id))
      {:ok, _} = Catalog.update_gall_editorial(test_actor(), gall, %{default_source_id: other.id})

      assert %{description: "Another description."} = ReviewContext.gall(gall.id, nil)

      bare = gall_fixture()
      assert %{description: nil} = ReviewContext.gall(bare.id, nil)
    end

    test "no description quotes a text that isn't in one", %{gall: gall} do
      assert %{quoted_in: nil} =
               ReviewContext.gall(gall.id, "Gall.—A large, soft, spongy gall on the roots.")
    end

    test "a text too short to tell quotes nothing", %{gall: gall} do
      assert %{quoted_in: nil} = ReviewContext.gall(gall.id, "Gall.—A small")
      assert %{quoted_in: nil} = ReviewContext.gall(gall.id, nil)
    end

    test "is nil for a Gall there is not" do
      assert ReviewContext.gall(-1, "anything") == nil
    end
  end

  describe "document/1" do
    test "is the package's document.json, decoded" do
      :ok = Private.put("import/rcx-doc/document.json", ~s({"texts": []}))

      assert ReviewContext.document(%Package{s3_prefix: "import/rcx-doc/"}) ==
               {:ok, %{"texts" => []}}
    end

    test "says when the package has no document" do
      assert ReviewContext.document(%Package{s3_prefix: "import/rcx-none/"}) ==
               {:error, :not_found}
    end

    test "says when the document is not JSON" do
      :ok = Private.put("import/rcx-bad/document.json", "not json")

      assert ReviewContext.document(%Package{s3_prefix: "import/rcx-bad/"}) ==
               {:error, :invalid_json}
    end
  end
end
