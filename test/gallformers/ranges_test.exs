defmodule Gallformers.RangesTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.Places
  alias Gallformers.Ranges
  alias Gallformers.Ranges.HostRange

  describe "precision validation" do
    test "rejects continent precision" do
      changeset =
        HostRange.changeset(%HostRange{}, %{
          species_id: 1,
          place_id: 1,
          precision: "continent"
        })

      assert %{precision: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "get_display_range_for_taxa/1" do
    # Seeds converted by the catalog migration: plant taxon 10 (Notholithocarpus
    # densiflorus) is native in US-CA and introduced in RO-B; its genus carries
    # its former placeholder's country-level row for Mexico (MX-JAL).
    defp genus_taxon_id, do: Gallformers.Taxa.get_by_legacy_id(:taxonomy, 41).id

    defp sorted(%Ranges.DisplayRange{} = range) do
      %{
        in_range: Enum.sort(range.in_range),
        inherited_range: Enum.sort(range.inherited_range),
        introduced_range: Enum.sort(range.introduced_range)
      }
    end

    test "splits a taxon's host_range rows by precision, marking introduced places" do
      assert sorted(Ranges.get_display_range_for_taxa([10])) == %{
               in_range: ["RO-B", "US-CA"],
               inherited_range: [],
               introduced_range: ["RO-B"]
             }
    end

    test "reads rows by taxon: a genus carries its former placeholder's country-level row" do
      assert sorted(Ranges.get_display_range_for_taxa([genus_taxon_id()])) == %{
               in_range: [],
               inherited_range: ["MX-JAL"],
               introduced_range: []
             }
    end

    test "is the union of several taxa's ranges" do
      assert sorted(Ranges.get_display_range_for_taxa([10, genus_taxon_id()])) == %{
               in_range: ["RO-B", "US-CA"],
               inherited_range: ["MX-JAL"],
               introduced_range: ["RO-B"]
             }
    end

    test "no taxa, or taxa without rows, give an empty range" do
      empty = %Ranges.DisplayRange{}
      assert Ranges.get_display_range_for_taxa([]) == empty
      assert Ranges.get_display_range_for_taxa([1]) == empty
    end
  end

  describe "get_places_for_taxa/1" do
    # The same converted seeds as get_display_range_for_taxa/1 above.
    test "each taxon's host_range place codes as stored, sorted, by taxon ID" do
      genus_id = Gallformers.Taxa.get_by_legacy_id(:taxonomy, 41).id

      assert Ranges.get_places_for_taxa([10, genus_id, 1]) == %{
               10 => ["RO-B", "US-CA"],
               genus_id => ["MX"]
             }

      assert Ranges.get_places_for_taxa([]) == %{}
    end
  end

  describe "display range computation" do
    test "compute_display_range passes through exact codes and expands country ones" do
      california = Places.get_place_by_code("US-CA")
      mexico = Places.get_place_by_code("MX")

      result =
        Ranges.compute_display_range([
          %{code: "US-CA", precision: "exact", place_id: california.id},
          %{code: "MX", precision: "country", place_id: mexico.id}
        ])

      assert "US-CA" in result.in_range
      assert "MX-JAL" in result.inherited_range
    end

    test "compute_display_range with with_introduced partitions by distribution_type" do
      california = Places.get_place_by_code("US-CA")
      alberta = Places.get_place_by_code("CA-AB")

      entries = [
        %{
          code: "US-CA",
          precision: "exact",
          place_id: california.id,
          distribution_type: "native"
        },
        %{
          code: "CA-AB",
          precision: "exact",
          place_id: alberta.id,
          distribution_type: "introduced"
        }
      ]

      result = Ranges.compute_display_range(entries, with_introduced: true)
      assert %Ranges.DisplayRange{} = result
      assert "US-CA" in result.in_range
      assert "CA-AB" in result.in_range
      # CA-AB is introduced
      assert "CA-AB" in result.introduced_range
      # US-CA is native, not introduced
      refute "US-CA" in result.introduced_range
    end

    test "exact native subdivision overrides introduced country-level inheritance" do
      us = Places.get_place_by_code("US")
      california = Places.get_place_by_code("US-CA")

      entries = [
        %{
          code: "US",
          precision: "country",
          place_id: us.id,
          distribution_type: "introduced"
        },
        %{
          code: "US-CA",
          precision: "exact",
          place_id: california.id,
          distribution_type: "native"
        }
      ]

      result = Ranges.compute_display_range(entries, with_introduced: true)

      assert "US-CA" in result.in_range
      refute "US-CA" in result.introduced_range
    end

    test "exact introduced subdivision overrides native country-level inheritance" do
      us = Places.get_place_by_code("US")
      california = Places.get_place_by_code("US-CA")

      entries = [
        %{
          code: "US",
          precision: "country",
          place_id: us.id,
          distribution_type: "native"
        },
        %{
          code: "US-CA",
          precision: "exact",
          place_id: california.id,
          distribution_type: "introduced"
        }
      ]

      result = Ranges.compute_display_range(entries, with_introduced: true)

      assert "US-CA" in result.in_range
      assert "US-CA" in result.introduced_range
    end

    test "compute_display_range without with_introduced returns empty introduced_range" do
      california = Places.get_place_by_code("US-CA")
      entries = [%{code: "US-CA", precision: "exact", place_id: california.id}]
      result = Ranges.compute_display_range(entries)
      assert result.introduced_range == []
    end

    test "expand_range_entries_to_leaf_status expands country entries to leaf coverage" do
      expanded =
        Ranges.expand_range_entries_to_leaf_status(%{
          "US" => %{precision: "country", distribution_type: "native"}
        })

      assert expanded["US-CA"].distribution_type == "native"
      assert expanded["US-CA"].source_code == "US"
      assert expanded["US-CA"].source_precision == "country"
    end

    test "expand_range_entries_to_leaf_status prefers exact entries over country entries" do
      expanded =
        Ranges.expand_range_entries_to_leaf_status(%{
          "US" => %{precision: "country", distribution_type: "introduced"},
          "US-CA" => %{precision: "exact", distribution_type: "native"}
        })

      assert expanded["US-CA"].distribution_type == "native"
      assert expanded["US-CA"].source_code == "US-CA"
      assert expanded["US-CA"].source_precision == "exact"
    end

    test "expand_place_entries_to_leaf_codes expands country precision to leaf codes" do
      codes =
        Ranges.expand_place_entries_to_leaf_codes([
          %{code: "MX", precision: "country"},
          %{code: "US-CA", precision: "exact"}
        ])

      assert MapSet.member?(codes, "MX-JAL") == true
      assert MapSet.member?(codes, "US-CA") == true
      refute MapSet.member?(codes, "MX")
    end
  end

  describe "distribution_type" do
    test "HostRange changeset accepts valid distribution_type values" do
      for dt <- ~w(native introduced) do
        changeset =
          HostRange.changeset(%HostRange{}, %{taxon_id: 1, place_id: 1, distribution_type: dt})

        assert changeset.valid? == true
      end
    end

    test "HostRange changeset rejects invalid distribution_type" do
      changeset =
        HostRange.changeset(%HostRange{}, %{
          taxon_id: 1,
          place_id: 1,
          distribution_type: "cultivated"
        })

      assert %{distribution_type: ["is invalid"]} = errors_on(changeset)
    end

    test "HostRange changeset defaults distribution_type to native" do
      changeset = HostRange.changeset(%HostRange{}, %{taxon_id: 1, place_id: 1})
      assert Ecto.Changeset.get_field(changeset, :distribution_type) == "native"
    end
  end
end
