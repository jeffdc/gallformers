defmodule Gallformers.SourcesTest do
  @moduledoc """
  Unit tests for the Sources context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Sources

  describe "short_name/1" do
    alias Gallformers.Sources.Source

    test "the authors' surnames and the year" do
      assert Sources.short_name(%Source{authors: ["Ashmead, W. H."], pubyear: "1897"}) ==
               "Ashmead 1897"

      assert Sources.short_name(%Source{
               authors: ["Nastasi, L. F.", "Davis, C. M."],
               authored_date: ~D[2022-01-01]
             }) == "Nastasi & Davis 2022"

      assert Sources.short_name(%Source{
               authors: ["Osten Sacken, C. R.", "Bassett, H. F.", "Walsh, B. D."],
               pubyear: "c. 1862"
             }) == "Osten Sacken et al. 1862"
    end

    test "the old single author field, a name without a comma, and no year" do
      assert Sources.short_name(%Source{authors: [], author: "Weld, L. H.", pubyear: "1959"}) ==
               "Weld 1959"

      assert Sources.short_name(%Source{authors: ["Lewis Weld"], pubyear: nil}) == "Weld"
    end

    test "nil when the Source names no author" do
      assert Sources.short_name(%Source{authors: [], author: nil, pubyear: "1900"}) == nil
      assert Sources.short_name(%Source{authors: [], author: "", pubyear: "1900"}) == nil
    end

    test "from authors and a year, for a Source not held yet" do
      assert Sources.short_name(["Ashmead, W. H."], 1897) == "Ashmead 1897"
      assert Sources.short_name([], 1897) == nil
    end
  end

  describe "list_recently_changed/1" do
    test "the Sources changed most recently, each marked added or updated" do
      attrs = %{
        author: "Adder, A.",
        pubyear: "2024",
        citation: "C",
        license: "All Rights Reserved"
      }

      {:ok, added} = Sources.create_source(Map.put(attrs, :title, "Recently added"))
      {:ok, updated} = Sources.create_source(Map.put(attrs, :title, "Recently updated"))

      later = ~U[2099-01-02 00:00:00Z]
      latest = ~U[2099-01-03 00:00:00Z]

      Repo.update_all(from(s in Sources.Source, where: s.id == ^added.id),
        set: [inserted_at: later, updated_at: later]
      )

      Repo.update_all(from(s in Sources.Source, where: s.id == ^updated.id),
        set: [inserted_at: later, updated_at: latest]
      )

      assert [first, second] = Sources.list_recently_changed(2)
      assert %{id: id, title: "Recently updated", change: :updated, changed_at: ^latest} = first
      assert id == updated.id
      assert %{title: "Recently added", change: :added, changed_at: ^later} = second
      assert Map.has_key?(first, :authors) and Map.has_key?(first, :year)
    end
  end

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
