defmodule Gallformers.RangesTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Ranges
  alias Gallformers.Ranges.HostRange
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  # A host's range codes.
  defp host_codes(host_id),
    do: host_id |> Ranges.get_places_for_host_with_precision() |> Enum.map(& &1.code)

  # A gall's curated gall_range place IDs.
  defp gall_range_place_ids(gall_id),
    do: gall_id |> Ranges.get_gall_range_with_precision() |> Enum.map(& &1.place_id)

  describe "precision-aware range queries" do
    test "get_places_for_host_with_precision/1 returns exact and country-level codes" do
      # M. arvensis (id=8) has exact ranges in CA-AB and US-CA,
      # plus a country-level range for US
      codes = host_codes(8)
      assert "CA-AB" in codes
      assert "US-CA" in codes
      assert "US" in codes
    end

    test "get_places_for_host_with_precision/1 includes precision metadata" do
      results = Ranges.get_places_for_host_with_precision(8)
      us_entry = Enum.find(results, &(&1.code == "US"))
      ca_entry = Enum.find(results, &(&1.code == "US-CA"))
      assert us_entry.precision == "country"
      assert ca_entry.precision == "exact"
    end
  end

  describe "precision validation" do
    test "rejects continent precision" do
      alias Gallformers.Ranges.HostRange

      changeset =
        HostRange.changeset(%HostRange{}, %{
          species_id: 1,
          place_id: 1,
          precision: "continent"
        })

      assert %{precision: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects continent precision for gall range" do
      alias Gallformers.Ranges.GallRange

      changeset =
        GallRange.changeset(%GallRange{}, %{
          species_id: 1,
          place_id: 1,
          precision: "continent"
        })

      assert %{precision: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "precision-aware range management" do
    test "add_place_to_host/3 accepts precision parameter" do
      bahamas = Places.get_place_by_code("BS")
      {:ok, _} = Ranges.add_place_to_host(6, bahamas.id, "exact")
      codes = host_codes(6)
      assert "BS" in codes
    end

    test "add_place_to_host/3 stores country precision" do
      mexico = Places.get_place_by_code("MX")
      {:ok, _} = Ranges.add_place_to_host(6, mexico.id, "country")
      results = Ranges.get_places_for_host_with_precision(6)
      mx = Enum.find(results, &(&1.code == "MX"))
      assert mx.precision == "country"
    end

    test "add_place_to_host/2 defaults to exact precision" do
      bahamas = Places.get_place_by_code("BS")
      {:ok, _} = Ranges.add_place_to_host(6, bahamas.id)
      results = Ranges.get_places_for_host_with_precision(6)
      bs = Enum.find(results, &(&1.code == "BS"))
      assert bs.precision == "exact"
    end

    test "update_host_places/2 accepts {place_id, precision} tuples" do
      california = Places.get_place_by_code("US-CA")
      mexico = Places.get_place_by_code("MX")
      {:ok, _} = Ranges.update_host_places(6, [{california.id, "exact"}, {mexico.id, "country"}])
      results = Ranges.get_places_for_host_with_precision(6)
      ca = Enum.find(results, &(&1.code == "US-CA"))
      mx = Enum.find(results, &(&1.code == "MX"))
      assert ca.precision == "exact"
      assert mx.precision == "country"
    end

    test "update_host_places/2 remains backwards-compatible with plain IDs" do
      california = Places.get_place_by_code("US-CA")
      {:ok, _} = Ranges.update_host_places(6, [california.id])
      results = Ranges.get_places_for_host_with_precision(6)
      ca = Enum.find(results, &(&1.code == "US-CA"))
      assert ca.precision == "exact"
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
    test "compute_display_range passes through all codes" do
      # Host 6 only has US-CA exact
      ranges = Ranges.get_places_for_host_with_precision(6)
      result = Ranges.compute_display_range(ranges)
      assert "US-CA" in result.in_range
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

    test "get_host_ranges_with_precision_for_species_ids includes distribution_type" do
      results = Ranges.get_host_ranges_with_precision_for_species_ids([7])
      assert length(results) > 0

      for entry <- results do
        assert Map.has_key?(entry, :distribution_type) == true
        assert entry.distribution_type in ["native", "introduced"]
      end
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
      alias Gallformers.Ranges.HostRange

      for dt <- ~w(native introduced) do
        changeset =
          HostRange.changeset(%HostRange{}, %{species_id: 1, place_id: 1, distribution_type: dt})

        assert changeset.valid? == true
      end
    end

    test "HostRange changeset rejects invalid distribution_type" do
      alias Gallformers.Ranges.HostRange

      changeset =
        HostRange.changeset(%HostRange{}, %{
          species_id: 1,
          place_id: 1,
          distribution_type: "cultivated"
        })

      assert %{distribution_type: ["is invalid"]} = errors_on(changeset)
    end

    test "HostRange changeset defaults distribution_type to native" do
      alias Gallformers.Ranges.HostRange
      changeset = HostRange.changeset(%HostRange{}, %{species_id: 1, place_id: 1})
      assert Ecto.Changeset.get_field(changeset, :distribution_type) == "native"
    end
  end

  describe "distribution_type in insert paths" do
    test "add_place_to_host/4 stores distribution_type" do
      mexico = Places.get_place_by_code("MX")
      {:ok, _} = Ranges.add_place_to_host(6, mexico.id, "country", "introduced")

      import Ecto.Query

      row =
        Gallformers.Repo.one(
          from(hr in Gallformers.Ranges.HostRange,
            where: hr.species_id == 6 and hr.place_id == ^mexico.id,
            select: hr.distribution_type
          )
        )

      assert row == "introduced"
    end

    test "add_place_to_host/3 defaults distribution_type to native" do
      bahamas = Places.get_place_by_code("BS")
      {:ok, _} = Ranges.add_place_to_host(6, bahamas.id, "exact")

      import Ecto.Query

      row =
        Gallformers.Repo.one(
          from(hr in Gallformers.Ranges.HostRange,
            where: hr.species_id == 6 and hr.place_id == ^bahamas.id,
            select: hr.distribution_type
          )
        )

      assert row == "native"
    end

    test "update_host_places/2 accepts {place_id, precision, distribution_type} triples" do
      california = Places.get_place_by_code("US-CA")
      mexico = Places.get_place_by_code("MX")

      {:ok, _} =
        Ranges.update_host_places(6, [
          {california.id, "exact", "native"},
          {mexico.id, "country", "introduced"}
        ])

      import Ecto.Query

      rows =
        Gallformers.Repo.all(
          from(hr in Gallformers.Ranges.HostRange,
            join: p in Gallformers.Places.Place,
            on: hr.place_id == p.id,
            where: hr.species_id == 6,
            select: %{code: p.code, distribution_type: hr.distribution_type}
          )
        )

      ca = Enum.find(rows, &(&1.code == "US-CA"))
      mx = Enum.find(rows, &(&1.code == "MX"))
      assert ca.distribution_type == "native"
      assert mx.distribution_type == "introduced"
    end

    test "update_host_places/2 deduplicates entries for the same place_id" do
      # This is the WCVP sync bug: a place can appear in both native and introduced
      # distributions. Native should win since the PK is (species_id, place_id).
      host =
        Repo.insert!(%Species{
          name: "Dedup Test Host",
          taxoncode: "plant",
          datacomplete: false
        })

      california = Repo.get_by!(Place, code: "US-CA")

      # Same place_id with different distribution_type — should not crash
      {:ok, _} =
        Ranges.update_host_places(host.id, [
          {california.id, "exact", "native"},
          {california.id, "exact", "introduced"}
        ])

      import Ecto.Query

      rows =
        Repo.all(
          from(hr in HostRange,
            where: hr.species_id == ^host.id,
            select: %{place_id: hr.place_id, distribution_type: hr.distribution_type}
          )
        )

      # Should have exactly one row, and native wins
      assert length(rows) == 1
      assert hd(rows).distribution_type == "native"
    end

    test "normalize_entries backwards compatible with plain IDs defaults to native" do
      california = Places.get_place_by_code("US-CA")

      {:ok, _} = Ranges.update_host_places(6, [california.id])

      import Ecto.Query

      row =
        Gallformers.Repo.one(
          from(hr in Gallformers.Ranges.HostRange,
            where: hr.species_id == 6 and hr.place_id == ^california.id,
            select: hr.distribution_type
          )
        )

      assert row == "native"
    end

    test "normalize_entries backwards compatible with pairs defaults to native" do
      california = Places.get_place_by_code("US-CA")

      {:ok, _} = Ranges.update_host_places(6, [{california.id, "exact"}])

      import Ecto.Query

      row =
        Gallformers.Repo.one(
          from(hr in Gallformers.Ranges.HostRange,
            where: hr.species_id == 6 and hr.place_id == ^california.id,
            select: hr.distribution_type
          )
        )

      assert row == "native"
    end
  end

  describe "toggle operations" do
    test "toggle_place_for_host adds then removes" do
      # Host 6 does not have place 3 (MX-JAL)
      result = Ranges.toggle_place_for_host(6, 3)
      assert {:added, 3} = result

      # Verify it was added
      codes = host_codes(6)
      assert "MX-JAL" in codes

      # Toggle off
      result = Ranges.toggle_place_for_host(6, 3)
      assert {:removed, 3} = result

      # Verify it was removed
      codes = host_codes(6)
      refute "MX-JAL" in codes
    end
  end

  describe "GallRange schema" do
    test "changeset accepts valid precision values" do
      alias Gallformers.Ranges.GallRange

      for p <- ~w(exact country) do
        changeset = GallRange.changeset(%GallRange{}, %{species_id: 1, place_id: 1, precision: p})
        assert changeset.valid? == true
      end
    end

    test "changeset rejects invalid precision" do
      alias Gallformers.Ranges.GallRange

      changeset =
        GallRange.changeset(%GallRange{}, %{
          species_id: 1,
          place_id: 1,
          precision: "continent"
        })

      assert %{precision: ["is invalid"]} = errors_on(changeset)
    end

    test "changeset defaults precision to exact" do
      alias Gallformers.Ranges.GallRange
      changeset = GallRange.changeset(%GallRange{}, %{species_id: 1, place_id: 1})
      assert Ecto.Changeset.get_field(changeset, :precision) == "exact"
    end
  end

  describe "set_gall_range/2" do
    test "replaces all gall_range entries for a species" do
      california = Places.get_place_by_code("US-CA")
      alberta = Places.get_place_by_code("CA-AB")

      # Gall 100 has 3 entries: US-CA, CA-AB, US (country)
      assert length(gall_range_place_ids(100)) == 3

      # Replace with just US-CA
      {:ok, :ok} = Ranges.set_gall_range(100, [{california.id, "exact"}])

      ids = gall_range_place_ids(100)
      assert ids == [california.id]

      # Replace with both US-CA and CA-AB
      {:ok, :ok} = Ranges.set_gall_range(100, [{california.id, "exact"}, {alberta.id, "exact"}])

      ids = gall_range_place_ids(100)
      assert length(ids) == 2
      assert california.id in ids
      assert alberta.id in ids
    end

    test "accepts plain place_ids (defaults to exact precision)" do
      california = Places.get_place_by_code("US-CA")
      {:ok, :ok} = Ranges.set_gall_range(100, [california.id])

      results = Ranges.get_gall_range_with_precision(100)
      assert length(results) == 1
      assert hd(results).precision == "exact"
    end

    test "clears all entries when given empty list" do
      {:ok, :ok} = Ranges.set_gall_range(100, [])
      assert gall_range_place_ids(100) == []
    end
  end

  describe "gall range query functions" do
    test "get_gall_range_codes returns codes from gall_range table" do
      codes = Ranges.get_gall_range_codes(100)
      assert "US-CA" in codes
      assert "CA-AB" in codes
      # MX-JAL is NOT in gall_range (was excluded in old system)
      refute "MX-JAL" in codes
    end

    test "get_gall_range_with_precision returns precision metadata" do
      results = Ranges.get_gall_range_with_precision(100)
      us_ca = Enum.find(results, &(&1.code == "US-CA"))
      us = Enum.find(results, &(&1.code == "US"))
      assert us_ca.precision == "exact"
      assert us.precision == "country"
    end

    test "get_gall_range_codes returns empty for gall without range" do
      # Gall 102 has no hosts, so no gall_range entries
      assert Ranges.get_gall_range_codes(102) == []
    end
  end
end
