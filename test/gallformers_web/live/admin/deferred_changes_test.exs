defmodule GallformersWeb.Admin.DeferredChangesTest do
  use ExUnit.Case, async: true

  alias GallformersWeb.Admin.DeferredChanges

  describe "init/2" do
    test "creates original and current assigns from items" do
      items = [%{id: 1, name: "foo"}, %{id: 2, name: "bar"}]
      result = DeferredChanges.init(:aliases, items)

      assert result == %{
               original_aliases: items,
               aliases: items
             }
    end

    test "works with empty list" do
      result = DeferredChanges.init(:hosts, [])

      assert result == %{
               original_hosts: [],
               hosts: []
             }
    end

    test "works with various collection names" do
      result = DeferredChanges.init(:filter_values, [%{id: 1}])

      assert Map.has_key?(result, :original_filter_values)
      assert Map.has_key?(result, :filter_values)
    end
  end

  describe "add_pending/4" do
    test "adds item with negative temp ID and pending flag" do
      socket = mock_socket(%{aliases: []})

      socket = DeferredChanges.add_pending(socket, :aliases, %{name: "New", type: "common name"})

      [added] = socket.assigns.aliases
      assert added.name == "New"
      assert added.type == "common name"
      assert added.id < 0
      assert added.pending == true
    end

    test "appends to existing items" do
      existing = [%{id: 1, name: "Existing"}]
      socket = mock_socket(%{aliases: existing})

      socket = DeferredChanges.add_pending(socket, :aliases, %{name: "New"})

      assert length(socket.assigns.aliases) == 2
      assert hd(socket.assigns.aliases).id == 1
    end

    test "uses custom id_field" do
      socket = mock_socket(%{hosts: []})

      socket =
        DeferredChanges.add_pending(
          socket,
          :hosts,
          %{host_species_id: 5, host_name: "Oak"},
          id_field: :host_relation_id
        )

      [added] = socket.assigns.hosts
      assert added.host_relation_id < 0
      assert added.host_species_id == 5
      assert added.pending == true
    end

    test "generates unique negative IDs" do
      socket = mock_socket(%{aliases: []})

      socket = DeferredChanges.add_pending(socket, :aliases, %{name: "First"})
      socket = DeferredChanges.add_pending(socket, :aliases, %{name: "Second"})

      [first, second] = socket.assigns.aliases
      assert first.id != second.id
      assert first.id < 0
      assert second.id < 0
    end
  end

  describe "remove_pending/4" do
    test "removes item by id" do
      items = [%{id: 1, name: "Keep"}, %{id: 2, name: "Remove"}]
      socket = mock_socket(%{aliases: items})

      socket = DeferredChanges.remove_pending(socket, :aliases, 2)

      assert length(socket.assigns.aliases) == 1
      assert hd(socket.assigns.aliases).id == 1
    end

    test "removes item with negative id" do
      items = [%{id: 1, name: "Existing"}, %{id: -999, name: "Pending", pending: true}]
      socket = mock_socket(%{aliases: items})

      socket = DeferredChanges.remove_pending(socket, :aliases, -999)

      assert length(socket.assigns.aliases) == 1
      assert hd(socket.assigns.aliases).id == 1
    end

    test "uses custom id_field" do
      items = [
        %{host_relation_id: 1, name: "Keep"},
        %{host_relation_id: 2, name: "Remove"}
      ]

      socket = mock_socket(%{hosts: items})

      socket = DeferredChanges.remove_pending(socket, :hosts, 2, id_field: :host_relation_id)

      assert length(socket.assigns.hosts) == 1
      assert hd(socket.assigns.hosts).host_relation_id == 1
    end

    test "handles non-existent id gracefully" do
      items = [%{id: 1, name: "Keep"}]
      socket = mock_socket(%{aliases: items})

      socket = DeferredChanges.remove_pending(socket, :aliases, 999)

      assert length(socket.assigns.aliases) == 1
    end
  end

  describe "exists?/4" do
    test "returns true when item with field value exists" do
      items = [%{id: 1, name: "Oak gall"}, %{id: 2, name: "Maple gall"}]
      socket = mock_socket(%{aliases: items})

      assert DeferredChanges.exists?(socket, :aliases, :name, "Oak gall")
    end

    test "returns false when item with field value does not exist" do
      items = [%{id: 1, name: "Oak gall"}]
      socket = mock_socket(%{aliases: items})

      refute DeferredChanges.exists?(socket, :aliases, :name, "Pine gall")
    end

    test "works with different field types" do
      items = [%{id: 1, host_species_id: 42}]
      socket = mock_socket(%{hosts: items})

      assert DeferredChanges.exists?(socket, :hosts, :host_species_id, 42)
      refute DeferredChanges.exists?(socket, :hosts, :host_species_id, 99)
    end

    test "returns false for empty collection" do
      socket = mock_socket(%{aliases: []})

      refute DeferredChanges.exists?(socket, :aliases, :name, "anything")
    end
  end

  describe "compute_changes/3" do
    test "identifies items to add (pending flag)" do
      original = [%{id: 1, name: "Original"}]
      current = [%{id: 1, name: "Original"}, %{id: -1, name: "New", pending: true}]

      socket = mock_socket(%{original_aliases: original, aliases: current})

      {to_add, to_remove} = DeferredChanges.compute_changes(socket, :aliases)

      assert length(to_add) == 1
      assert hd(to_add).name == "New"
      assert MapSet.size(to_remove) == 0
    end

    test "identifies items to add (negative id)" do
      original = [%{id: 1, name: "Original"}]
      current = [%{id: 1, name: "Original"}, %{id: -5, name: "New"}]

      socket = mock_socket(%{original_aliases: original, aliases: current})

      {to_add, _to_remove} = DeferredChanges.compute_changes(socket, :aliases)

      assert length(to_add) == 1
      assert hd(to_add).name == "New"
    end

    test "identifies items to remove" do
      original = [%{id: 1, name: "Keep"}, %{id: 2, name: "Remove"}]
      current = [%{id: 1, name: "Keep"}]

      socket = mock_socket(%{original_aliases: original, aliases: current})

      {to_add, to_remove} = DeferredChanges.compute_changes(socket, :aliases)

      assert length(to_add) == 0
      assert MapSet.member?(to_remove, 2)
      refute MapSet.member?(to_remove, 1)
    end

    test "handles both additions and removals" do
      original = [%{id: 1, name: "Keep"}, %{id: 2, name: "Remove"}]
      current = [%{id: 1, name: "Keep"}, %{id: -1, name: "Add", pending: true}]

      socket = mock_socket(%{original_aliases: original, aliases: current})

      {to_add, to_remove} = DeferredChanges.compute_changes(socket, :aliases)

      assert length(to_add) == 1
      assert hd(to_add).name == "Add"
      assert MapSet.member?(to_remove, 2)
    end

    test "uses custom id_field" do
      original = [%{host_relation_id: 1}, %{host_relation_id: 2}]
      current = [%{host_relation_id: 1}, %{host_relation_id: -1, pending: true}]

      socket = mock_socket(%{original_hosts: original, hosts: current})

      {to_add, to_remove} =
        DeferredChanges.compute_changes(socket, :hosts, id_field: :host_relation_id)

      assert length(to_add) == 1
      assert MapSet.member?(to_remove, 2)
    end

    test "returns empty results when nothing changed" do
      items = [%{id: 1, name: "Same"}]
      socket = mock_socket(%{original_aliases: items, aliases: items})

      {to_add, to_remove} = DeferredChanges.compute_changes(socket, :aliases)

      assert to_add == []
      assert MapSet.size(to_remove) == 0
    end
  end

  describe "refresh/3" do
    test "updates both original and current assigns" do
      socket =
        mock_socket(%{
          original_aliases: [%{id: 1, name: "Old"}],
          aliases: [%{id: -1, name: "Pending", pending: true}]
        })

      new_items = [%{id: 1, name: "Old"}, %{id: 2, name: "New from DB"}]

      socket = DeferredChanges.refresh(socket, :aliases, new_items)

      assert socket.assigns.original_aliases == new_items
      assert socket.assigns.aliases == new_items
    end
  end

  describe "has_changes?/3" do
    test "returns false when no changes" do
      items = [%{id: 1, name: "Same"}, %{id: 2, name: "Also same"}]
      socket = mock_socket(%{original_aliases: items, aliases: items})

      refute DeferredChanges.has_changes?(socket, :aliases)
    end

    test "returns true when item added" do
      original = [%{id: 1}]
      current = [%{id: 1}, %{id: -1, pending: true}]
      socket = mock_socket(%{original_aliases: original, aliases: current})

      assert DeferredChanges.has_changes?(socket, :aliases)
    end

    test "returns true when item removed" do
      original = [%{id: 1}, %{id: 2}]
      current = [%{id: 1}]
      socket = mock_socket(%{original_aliases: original, aliases: current})

      assert DeferredChanges.has_changes?(socket, :aliases)
    end

    test "returns true when items differ" do
      original = [%{id: 1}, %{id: 2}]
      current = [%{id: 1}, %{id: 3}]
      socket = mock_socket(%{original_aliases: original, aliases: current})

      assert DeferredChanges.has_changes?(socket, :aliases)
    end

    test "uses custom id_field" do
      original = [%{host_relation_id: 1}]
      current = [%{host_relation_id: 1}, %{host_relation_id: -1}]
      socket = mock_socket(%{original_hosts: original, hosts: current})

      assert DeferredChanges.has_changes?(socket, :hosts, id_field: :host_relation_id)
    end
  end

  # Helper to create a mock socket struct
  defp mock_socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end
end
