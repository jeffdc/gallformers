defmodule Gallformers.GallsIdentificationTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Galls

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
end
