defmodule Gallformers.Wcvp.ReaderTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Reader

  @names_csv """
  plant_name_id|ipni_id|taxon_rank|taxon_status|family|genus_hybrid|genus|species_hybrid|species|infraspecific_rank|infraspecies|parenthetical_author|primary_author|publication_author|place_of_publication|volume_and_page|first_published|nomenclatural_remarks|geographic_area|lifeform_description|climate_description|taxon_name|taxon_authors|accepted_plant_name_id|basionym_plant_name_id|replaced_synonym_author|homotypic_synonym|parent_plant_name_id|powo_id|hybrid_formula|reviewed
  1|123-1|Species|Accepted|Fagaceae||Quercus||alba|||||||||||||Quercus alba|L.|1|||||urn:lsid:ipni.org:names:123-1||
  2|124-1|Species|Synonym|Fagaceae||Quercus||stellata|||||||||||||Quercus stellata|Wangenh.|3|||||||
  3|125-1|Species|Accepted|Fagaceae||Quercus||rubra|||||||||||||Quercus rubra|L.|3|||||urn:lsid:ipni.org:names:125-1||
  4|126-1|Variety|Accepted|Rosaceae||Rosa||canina|var.|lutetiana|||||||||||Rosa canina var. lutetiana|(Leman) Baker|4|||||||
  5|127-1|Species|Unplaced|Asteraceae||Fictus||plantus|||||||||||||Fictus plantus|Auth.|5|||||||
  """

  @distributions_csv """
  plant_locality_id|plant_name_id|continent_code_l1|continent|region_code_l2|region|area_code_l3|area|introduced|extinct|location_doubtful
  1|1|7|NORTHERN AMERICA|71|Southeastern U.S.A.|ALB|Alabama|0|0|0
  2|1|7|NORTHERN AMERICA|71|Southeastern U.S.A.|GEO|Georgia|0|0|0
  3|1|8|SOUTHERN AMERICA|84|Brazil|BZL|Brazil South|0|0|0
  4|3|7|NORTHERN AMERICA|74|North-Central U.S.A.|ILL|Illinois|1|0|0
  5|1|7|NORTHERN AMERICA|71|Southeastern U.S.A.|ALB|Alabama|0|1|0
  """

  describe "stream_accepted_names/1" do
    test "filters to accepted species and subspecific taxa only" do
      path = write_temp_csv("names.csv", @names_csv)
      names = Reader.stream_accepted_names(path) |> Enum.to_list()

      assert length(names) == 3
      assert Enum.all?(names, fn n -> n.taxon_status == "Accepted" end)
    end

    test "parses fields into a struct" do
      path = write_temp_csv("names.csv", @names_csv)
      [first | _] = Reader.stream_accepted_names(path) |> Enum.to_list()

      assert first.plant_name_id == "1"
      assert first.genus == "Quercus"
      assert first.species == "alba"
      assert first.family == "Fagaceae"
      assert first.taxon_name == "Quercus alba"
      assert first.taxon_authors == "L."
    end
  end

  describe "stream_names_for_synonym_lookup/1" do
    test "includes synonyms with their accepted_plant_name_id" do
      path = write_temp_csv("names.csv", @names_csv)
      synonyms = Reader.stream_names_for_synonym_lookup(path) |> Enum.to_list()

      # Should include synonyms that point to a different accepted name
      syn = Enum.find(synonyms, fn n -> n.taxon_status == "Synonym" end)
      assert syn != nil
      assert syn.taxon_name == "Quercus stellata"
      assert syn.accepted_plant_name_id == "3"
    end
  end

  describe "stream_established_distributions/1" do
    test "includes both native and introduced, excludes extinct and doubtful" do
      path = write_temp_csv("distributions.csv", @distributions_csv)
      dists = Reader.stream_established_distributions(path) |> Enum.to_list()

      # Row 4 is introduced (kept), row 5 is extinct (excluded) — 4 total
      assert length(dists) == 4
      assert Enum.all?(dists, fn d -> d.extinct == "0" end)

      introduced = Enum.filter(dists, fn d -> d.introduced == "1" end)
      assert length(introduced) == 1
      assert hd(introduced).plant_name_id == "3"
      assert hd(introduced).area_code_l3 == "ILL"
    end
  end

  describe "build_synonym_index/1" do
    test "maps synonym canonical names to their accepted name IDs" do
      path = write_temp_csv("names.csv", @names_csv)
      index = Reader.build_synonym_index(path)

      assert Map.has_key?(index, "Quercus stellata")
      assert index["Quercus stellata"] == "3"
    end
  end

  describe "build_accepted_name_lookup/1" do
    test "maps accepted plant_name_id to name struct" do
      path = write_temp_csv("names.csv", @names_csv)
      lookup = Reader.build_accepted_name_lookup(path)

      assert Map.has_key?(lookup, "1")
      assert lookup["1"].taxon_name == "Quercus alba"
    end
  end

  describe "build_distribution_index/1" do
    test "groups native TDWG codes by plant_name_id" do
      path = write_temp_csv("distributions.csv", @distributions_csv)
      index = Reader.build_distribution_index(path)

      assert Map.has_key?(index, "1")
      assert "ALB" in index["1"]
      assert "GEO" in index["1"]
      assert "BZL" in index["1"]
    end
  end

  defp write_temp_csv(filename, content) do
    dir = System.tmp_dir!()
    path = Path.join(dir, "wcvp_test_#{filename}")
    File.write!(path, String.trim(content))
    path
  end
end
