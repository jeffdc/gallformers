defmodule Gallformers.SourcesTest do
  @moduledoc """
  Unit tests for the Sources context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Sources

  describe "list_sources_by_id/1" do
    test "the Sources with the given IDs, by ID; unknown IDs are left out" do
      assert [%{id: 58}, %{id: 59}] = Sources.list_sources_by_id([59, 58, 999_999])
      assert Sources.list_sources_by_id([]) == []
    end
  end

  describe "list_sources_page/1" do
    test "a page of the Sources whose title or author matches, by title, and the count" do
      prefix = "Paged #{System.unique_integer([:positive])}"

      for n <- [3, 1, 2] do
        {:ok, _} =
          Sources.create_source(%{
            title: "#{prefix} #{n}",
            author: "Author #{n}",
            pubyear: "2024",
            citation: "Citation #{n}",
            license: "All Rights Reserved"
          })
      end

      assert %{entries: [first, second], total: 3} =
               Sources.list_sources_page(query: prefix, page: 1, page_size: 2)

      assert {first.title, second.title} == {"#{prefix} 1", "#{prefix} 2"}

      assert %{entries: [third], total: 3} =
               Sources.list_sources_page(
                 query: " #{String.upcase(prefix)} ",
                 page: 2,
                 page_size: 2
               )

      assert third.title == "#{prefix} 3"
      assert %{total: 0} = Sources.list_sources_page(query: "#{prefix} nothing")
    end
  end
end
