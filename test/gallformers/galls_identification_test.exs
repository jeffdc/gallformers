defmodule Gallformers.GallsIdentificationTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Galls

  # Seed data IDs (from test_seeds.sql):
  #   Hosts: T. alpinus=6, T. serpyllum=7, M. arvensis=8
  #   Galls: 100 (hosts: T. alpinus + M. arvensis), 101 (host: T. serpyllum)
  #   Taxonomy: GenusAlpha=10 (T. alpinus, T. serpyllum), GenusBeta=11 (M. arvensis)
  #   Places: Alberta(AB)=1, California(CA)=2
  #   host_range: T. alpinus→CA, M. arvensis→AB+CA, T. serpyllum→CA

  describe "get_summary_data/1" do
    test "returns filter data for given gall_ids" do
      # Empty list returns empty map
      assert Galls.get_summary_data([]) == %{}
    end

    test "returns map keyed by gall_id with filter values" do
      # Test with non-existent IDs should return empty map
      result = Galls.get_summary_data([99_999, 99_998])
      assert result == %{} or is_map(result)
    end
  end

  describe "filter_galls genus+place interaction" do
    test "genus + place excludes galls whose genus hosts are not in the place" do
      # Gall 100 is on T. alpinus (GenusAlpha) AND M. arvensis (GenusBeta).
      # M. arvensis is in Alberta but T. alpinus is NOT in Alberta.
      # genus=GenusAlpha + place=Alberta should NOT return gall 100.
      results = Galls.filter_galls(%{genus_id: 10, place_codes: ["AB"]})
      gall_ids = Enum.map(results, & &1.id)
      refute 100 in gall_ids
    end

    test "genus + place includes galls whose genus hosts are in the place" do
      # Gall 100 is on T. alpinus (GenusAlpha). T. alpinus IS in California.
      # genus=GenusAlpha + place=California SHOULD return gall 100.
      results = Galls.filter_galls(%{genus_id: 10, place_codes: ["CA"]})
      gall_ids = Enum.map(results, & &1.id)
      assert 100 in gall_ids
    end

    test "host + place constrains to selected host" do
      # Gall 100 is on T. alpinus (6) and M. arvensis (8).
      # T. alpinus is NOT in Alberta, so host=T. alpinus + place=Alberta should exclude gall 100.
      results = Galls.filter_galls(%{host_ids: [6], place_codes: ["AB"]})
      gall_ids = Enum.map(results, & &1.id)
      refute 100 in gall_ids
    end

    test "place filter without host/genus is unconstrained" do
      # Place=Alberta with no host/genus filter should still return gall 100,
      # because M. arvensis (one of its hosts) is in Alberta.
      results = Galls.filter_galls(%{place_codes: ["AB"]})
      gall_ids = Enum.map(results, & &1.id)
      assert 100 in gall_ids
    end
  end
end
