defmodule Gallformers.Galls.HostAssociationsTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.Galls
  alias Gallformers.Galls.GallHost
  alias Gallformers.Plants

  # ============================================
  # Test helpers — create own data, no seed IDs
  # ============================================

  defp create_species(name, taxoncode) do
    Repo.insert!(%Gallformers.Species.Species{
      name: name,
      taxoncode: taxoncode
    })
  end

  defp create_gall(name), do: create_species(name, "gall")
  defp create_host(name), do: create_species(name, "plant")

  defp create_placeholder_host(name) do
    Repo.insert!(%Gallformers.Species.Species{
      name: name,
      taxoncode: "plant",
      genus_placeholder: true
    })
  end

  # ============================================
  # Schema / Changeset
  # ============================================

  describe "GallHost changeset" do
    test "valid with required fields" do
      changeset = GallHost.changeset(%GallHost{}, %{gall_species_id: 1, host_species_id: 2})
      assert changeset.valid? == true
    end

    test "invalid without gall_species_id" do
      changeset = GallHost.changeset(%GallHost{}, %{host_species_id: 2})
      assert %{gall_species_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without host_species_id" do
      changeset = GallHost.changeset(%GallHost{}, %{gall_species_id: 1})
      assert %{host_species_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid with no fields" do
      changeset = GallHost.changeset(%GallHost{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:gall_species_id] != nil
      assert errors[:host_species_id] != nil
    end

    test "enforces unique gall + host pair" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      {:ok, _} = Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host.id})

      {:error, changeset} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host.id})

      assert %{host_species_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  # ============================================
  # Queries — single record
  # ============================================

  describe "get_gall_host/1" do
    test "returns the record when it exists" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      {:ok, relation} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host.id})

      assert Galls.get_gall_host(relation.id) == relation
    end

    test "returns nil when not found" do
      assert Galls.get_gall_host(0) == nil
    end
  end

  describe "get_hosts_for_gall/1" do
    test "returns hosts with relation ID and name" do
      gall = create_gall("Andricus test")
      host1 = create_host("Quercus alba test")
      host2 = create_host("Quercus rubra test")

      {:ok, rel1} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host1.id})

      {:ok, rel2} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host2.id})

      hosts = Galls.get_hosts_for_gall(gall.id)
      assert length(hosts) == 2

      ids = Enum.map(hosts, & &1.host_relation_id) |> Enum.sort()
      assert ids == Enum.sort([rel1.id, rel2.id])

      names = Enum.map(hosts, & &1.host_name) |> Enum.sort()
      assert names == ["Quercus alba test", "Quercus rubra test"]
    end

    test "returns empty list for gall with no hosts" do
      gall = create_gall("Lonely gall")
      assert Galls.get_hosts_for_gall(gall.id) == []
    end

    test "returns empty list for nonexistent gall" do
      assert Galls.get_hosts_for_gall(0) == []
    end

    test "does not include hosts from other galls" do
      gall1 = create_gall("Gall one")
      gall2 = create_gall("Gall two")
      host1 = create_host("Host one")
      host2 = create_host("Host two")

      Galls.create_gall_host(%{gall_species_id: gall1.id, host_species_id: host1.id})
      Galls.create_gall_host(%{gall_species_id: gall2.id, host_species_id: host2.id})

      hosts = Galls.get_hosts_for_gall(gall1.id)
      assert length(hosts) == 1
      assert hd(hosts).host_name == "Host one"
    end

    test "surfaces the genus_placeholder flag on each host" do
      gall = create_gall("Andricus placeholder test")
      host_real = create_host("Quercus alba placeholder test")
      host_placeholder = create_placeholder_host("Quercus placeholder spp")

      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host_real.id})
      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host_placeholder.id})

      hosts = Galls.get_hosts_for_gall(gall.id)

      flags =
        hosts
        |> Enum.map(fn h -> {h.host_name, h.genus_placeholder} end)
        |> Enum.sort()

      assert flags == [
               {"Quercus alba placeholder test", false},
               {"Quercus placeholder spp", true}
             ]
    end
  end

  describe "only_placeholder_hosts?/1" do
    test "returns true when every host is a genus placeholder" do
      gall = create_gall("Only placeholders gall")
      ph1 = create_placeholder_host("Quercus only ph1 spp")
      ph2 = create_placeholder_host("Carya only ph2 spp")

      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: ph1.id})
      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: ph2.id})

      assert gall.id |> Galls.get_hosts_for_gall() |> Galls.only_placeholder_hosts?() == true
    end

    test "returns false when at least one host is a real species" do
      gall = create_gall("Mixed hosts gall")
      ph = create_placeholder_host("Quercus mixed ph spp")
      real = create_host("Quercus mixed real")

      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: ph.id})
      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: real.id})

      assert gall.id |> Galls.get_hosts_for_gall() |> Galls.only_placeholder_hosts?() == false
    end

    test "returns false for an empty host list" do
      assert Galls.only_placeholder_hosts?([]) == false
    end
  end

  describe "get_galls_for_host/1" do
    test "returns galls for a host" do
      host = create_host("Quercus test")
      gall = create_gall("Andricus test")

      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host.id})

      galls = Plants.get_galls_for_host(host.id)
      assert length(galls) == 1
      assert hd(galls).name == "Andricus test"
    end

    test "returns empty list for host with no galls" do
      host = create_host("Lonely host")
      assert Plants.get_galls_for_host(host.id) == []
    end
  end

  describe "get_host_species_ids_for_gall/1" do
    test "returns just the host IDs" do
      gall = create_gall("Andricus test")
      host1 = create_host("Host one")
      host2 = create_host("Host two")

      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host1.id})
      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host2.id})

      ids = Galls.get_host_species_ids_for_gall(gall.id) |> Enum.sort()
      assert ids == Enum.sort([host1.id, host2.id])
    end

    test "returns empty list when no hosts" do
      assert Galls.get_host_species_ids_for_gall(0) == []
    end
  end

  # ============================================
  # Queries — batch
  # ============================================

  describe "get_hosts_for_galls/1" do
    test "returns empty map for empty list" do
      assert Galls.get_hosts_for_galls([]) == %{}
    end

    test "groups hosts by gall ID" do
      gall1 = create_gall("Gall one")
      gall2 = create_gall("Gall two")
      host_a = create_host("Host A")
      host_b = create_host("Host B")

      Galls.create_gall_host(%{gall_species_id: gall1.id, host_species_id: host_a.id})
      Galls.create_gall_host(%{gall_species_id: gall2.id, host_species_id: host_b.id})

      result = Galls.get_hosts_for_galls([gall1.id, gall2.id])

      assert length(result[gall1.id]) == 1
      assert hd(result[gall1.id]).host_name == "Host A"
      assert length(result[gall2.id]) == 1
      assert hd(result[gall2.id]).host_name == "Host B"
    end

    test "gall with no hosts is absent from result map" do
      gall = create_gall("No hosts")
      result = Galls.get_hosts_for_galls([gall.id])
      refute Map.has_key?(result, gall.id)
    end
  end

  describe "get_gall_counts_for_hosts/1" do
    test "returns empty map for empty list" do
      assert Plants.get_gall_counts_for_hosts([]) == %{}
    end

    test "returns count of galls per host" do
      host = create_host("Popular host")
      gall1 = create_gall("Gall one")
      gall2 = create_gall("Gall two")

      Galls.create_gall_host(%{gall_species_id: gall1.id, host_species_id: host.id})
      Galls.create_gall_host(%{gall_species_id: gall2.id, host_species_id: host.id})

      result = Plants.get_gall_counts_for_hosts([host.id])
      assert result[host.id] == 2
    end

    test "host with no galls is absent from result" do
      host = create_host("No galls")
      result = Plants.get_gall_counts_for_hosts([host.id])
      refute Map.has_key?(result, host.id)
    end
  end

  describe "get_host_counts_for_galls/1" do
    test "returns empty map for empty list" do
      assert Galls.get_host_counts_for_galls([]) == %{}
    end

    test "returns count of hosts per gall" do
      gall = create_gall("Polyphagous gall")
      host1 = create_host("Host one")
      host2 = create_host("Host two")
      host3 = create_host("Host three")

      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host1.id})
      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host2.id})
      Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host3.id})

      result = Galls.get_host_counts_for_galls([gall.id])
      assert result[gall.id] == 3
    end
  end

  # ============================================
  # Mutations — individual
  # ============================================

  describe "add_host_to_gall/2" do
    test "creates the relationship" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      assert {:ok, relation} = Galls.add_host_to_gall(gall.id, host.id)
      assert relation.gall_species_id == gall.id
      assert relation.host_species_id == host.id
    end

    test "broadcasts species change" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      Phoenix.PubSub.subscribe(Gallformers.PubSub, "species")
      Galls.add_host_to_gall(gall.id, host.id)

      gall_id = gall.id
      assert_receive {:species_updated, %{id: ^gall_id}}
    end

    test "rejects duplicate gall-host pair" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      {:ok, _} = Galls.add_host_to_gall(gall.id, host.id)
      assert {:error, _changeset} = Galls.add_host_to_gall(gall.id, host.id)
    end
  end

  describe "remove_host_from_gall/1" do
    test "deletes the relationship" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      {:ok, relation} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host.id})

      assert {:ok, deleted} = Galls.remove_host_from_gall(relation.id)
      assert deleted.id == relation.id
      assert Galls.get_gall_host(relation.id) == nil
    end

    test "broadcasts species change" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      {:ok, relation} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host.id})

      Phoenix.PubSub.subscribe(Gallformers.PubSub, "species")
      Galls.remove_host_from_gall(relation.id)

      gall_id = gall.id
      assert_receive {:species_updated, %{id: ^gall_id}}
    end

    test "returns error for nonexistent relation" do
      assert {:error, :not_found} = Galls.remove_host_from_gall(0)
    end
  end

  describe "delete_gall_host/1" do
    test "deletes the relationship" do
      gall = create_gall("Andricus test")
      host = create_host("Quercus test")

      {:ok, relation} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host.id})

      assert {:ok, _} = Galls.delete_gall_host(relation.id)
      assert Galls.get_gall_host(relation.id) == nil
    end

    test "returns error for nonexistent ID" do
      assert {:error, :not_found} = Galls.delete_gall_host(0)
    end
  end

  # ============================================
  # Transaction — save_gall_host_changes
  # ============================================

  describe "save_gall_host_changes/5" do
    setup do
      gall = create_gall("Transaction gall")
      host1 = create_host("Existing host")
      host2 = create_host("New host")

      {:ok, relation} =
        Galls.create_gall_host(%{gall_species_id: gall.id, host_species_id: host1.id})

      %{gall: gall, host1: host1, host2: host2, relation: relation}
    end

    test "adds and removes hosts atomically", %{gall: gall, host2: host2, relation: relation} do
      hosts_to_add = [%{host_species_id: host2.id}]
      hosts_to_remove = MapSet.new([relation.id])

      assert {:ok, :ok} = Galls.save_gall_host_changes(gall.id, hosts_to_add, hosts_to_remove)

      hosts = Galls.get_hosts_for_gall(gall.id)
      names = Enum.map(hosts, & &1.host_name)

      assert "New host" in names
      refute "Existing host" in names
    end

    test "with no changes is a no-op", %{gall: gall} do
      assert {:ok, :ok} = Galls.save_gall_host_changes(gall.id, [], MapSet.new())

      hosts = Galls.get_hosts_for_gall(gall.id)
      assert length(hosts) == 1
    end

    test "updates gall range when entries provided", %{gall: gall} do
      # Use a place with a unique code to avoid constraint conflicts
      code = "ZZ-#{System.unique_integer([:positive])}"

      place =
        %Gallformers.Places.Place{}
        |> Ecto.Changeset.change(%{name: "Test Place", code: code, type: "state"})
        |> Repo.insert!()

      range_entries = [{place.id, "exact"}]

      assert {:ok, :ok} =
               Galls.save_gall_host_changes(gall.id, [], MapSet.new(), range_entries)

      # Verify range was set
      range_ids = Gallformers.Ranges.get_gall_range_place_ids(gall.id)
      assert place.id in range_ids
    end

    test "confirms range when option set", %{gall: gall} do
      # confirm_gall_range does update_all, so a gall_traits record must exist
      Repo.insert!(%Gallformers.Galls.GallTraits{species_id: gall.id, range_confirmed: false})

      assert {:ok, :ok} =
               Galls.save_gall_host_changes(gall.id, [], MapSet.new(), nil, confirm_range: true)

      traits = Galls.get_gall_traits(gall.id)
      assert traits.range_confirmed != nil
    end

    test "touches the species updated_at", %{gall: gall} do
      # Set updated_at to a known past time so the touch is always detectable
      past = ~U[2020-01-01 00:00:00Z]

      Repo.get!(Gallformers.Species.Species, gall.id)
      |> Ecto.Changeset.change(%{updated_at: past})
      |> Repo.update!()

      Galls.save_gall_host_changes(gall.id, [], MapSet.new())

      after_save = Repo.get!(Gallformers.Species.Species, gall.id).updated_at
      assert DateTime.compare(after_save, past) == :gt
    end

    test "rolls back atomically when a host removal targets a non-existent relation",
         %{gall: gall, host2: host2, relation: relation} do
      # Pin updated_at to a known past time so we can detect whether touch ran
      past = ~U[2020-01-01 00:00:00Z]

      Repo.get!(Gallformers.Species.Species, gall.id)
      |> Ecto.Changeset.change(%{updated_at: past})
      |> Repo.update!()

      hosts_to_add = [%{host_species_id: host2.id}]
      hosts_to_remove = MapSet.new([relation.id, 999_999_999])

      assert {:error, _reason} =
               Galls.save_gall_host_changes(gall.id, hosts_to_add, hosts_to_remove)

      # The existing host must still be present (remove rolled back)
      hosts = Galls.get_hosts_for_gall(gall.id)
      names = Enum.map(hosts, & &1.host_name)
      assert "Existing host" in names
      # The new host must NOT have been added
      refute "New host" in names
      # Species.touch must not have run
      after_save = Repo.get!(Gallformers.Species.Species, gall.id).updated_at
      assert DateTime.compare(after_save, past) == :eq
    end

    test "emits exactly one broadcast on successful batch save",
         %{gall: gall, host2: host2, relation: relation} do
      Phoenix.PubSub.subscribe(Gallformers.PubSub, "species")

      hosts_to_add = [%{host_species_id: host2.id}]
      hosts_to_remove = MapSet.new([relation.id])

      assert {:ok, :ok} = Galls.save_gall_host_changes(gall.id, hosts_to_add, hosts_to_remove)

      gall_id = gall.id
      assert_receive {:species_updated, %{id: ^gall_id}}, 500
      # No additional broadcasts for the individual add/remove operations
      refute_receive {:species_updated, %{id: ^gall_id}}, 200
    end
  end
end
