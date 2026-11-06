defmodule GallformersWeb.RankGallsTest do
  use ExUnit.Case, async: true

  alias GallformersWeb.RankGalls

  defp gall(id, name, opts \\ []) do
    %{
      id: id,
      name: name,
      common_name: opts[:common_name],
      count: opts[:count] || 1,
      undescribed: false,
      image_url: nil,
      traits: opts[:traits] || %{},
      host_genera: opts[:hosts] || []
    }
  end

  defp galls(n) do
    for i <- 1..n do
      part = if rem(i, 2) == 0, do: "leaf", else: "stem"
      gall(i, "Gall #{String.pad_leading("#{i}", 3, "0")}", traits: %{"plant_part" => [part]})
    end
  end

  @by_name %{field: :name, dir: :asc}

  describe "compute/3" do
    test "the search and facets narrow; an option counts what choosing it would leave" do
      list =
        galls(10)
        |> RankGalls.new()
        |> RankGalls.filter(%{"plant_part" => ["leaf"]})
        |> RankGalls.compute("", @by_name)

      assert list.shown_count == 5
      assert %{options: options} = Enum.find(list.facets, &(&1.key == "plant_part"))
      assert [%{value: "leaf", count: 5, selected: true}, %{value: "stem", count: 5}] = options

      assert %{shown_count: 1, shown: [%{name: "Gall 010"}]} =
               galls(10) |> RankGalls.new() |> RankGalls.compute("010", @by_name)
    end

    test "the search matches a common name; facets need eight Galls and two options" do
      few = [gall(1, "Andricus a", common_name: "oak apple"), gall(2, "Andricus b")]

      assert %{shown: [%{id: 1}], facets: []} =
               few |> RankGalls.new() |> RankGalls.compute("apple", @by_name)
    end

    test "a card leads with its Host count, then its plant part, form and season" do
      galls = [
        gall(1, "A", count: 3, traits: %{"plant_part" => ["leaf"], "season" => ["spring"]})
      ]

      assert %{shown: [%{subtitle: "3 hosts · leaf · spring", navigate: "/gall/1"}]} =
               galls |> RankGalls.new() |> RankGalls.compute("", @by_name)
    end

    test "sorts by the page's sort; a field the list lacks sorts by name" do
      galls = [gall(1, "B", count: 1), gall(2, "A", count: 5)]
      list = RankGalls.new(galls)

      assert %{shown: [%{id: 2}, %{id: 1}]} =
               RankGalls.compute(list, "", %{field: :count, dir: :desc})

      assert %{shown: [%{id: 2}, %{id: 1}]} =
               RankGalls.compute(list, "", %{field: :rank, dir: :asc})
    end

    test "pages of 48 photos or 50 rows; a page past the end shows the last" do
      list = galls(120) |> RankGalls.new()
      assert list.view == :photos

      assert %{total_pages: 3, page: 3, shown: shown} =
               list |> RankGalls.page("9") |> RankGalls.compute("", @by_name)

      assert length(shown) == 24

      assert %{total_pages: 3, page_size: 50} =
               list |> RankGalls.view("table") |> RankGalls.compute("", @by_name)
    end

    test "more than 150 Galls open as a table; filtering goes back to page 1" do
      list = galls(151) |> RankGalls.new()
      assert list.view == :table

      assert %{page: 1} =
               list
               |> RankGalls.page(3)
               |> RankGalls.filter(%{"plant_part" => ["stem"]})
               |> RankGalls.compute("", @by_name)

      assert %{selected: selected} = list |> RankGalls.filter(%{}) |> RankGalls.clear()
      assert selected == %{}
    end
  end

  describe "photos only" do
    test "a list offering only photos stays photos, however large, and ignores a switch" do
      list = galls(151) |> RankGalls.new(views: [:photos])

      assert list.view == :photos
      assert list.views == [:photos]
      assert %{view: :photos} = RankGalls.handle(list, "galls_view", %{"view" => "table"})
    end

    test "a list offers both views by default" do
      assert %{views: [:photos, :table]} = galls(3) |> RankGalls.new()
    end
  end

  describe "handle/3" do
    test "the list's events" do
      list = galls(10) |> RankGalls.new()

      assert %{selected: %{"plant_part" => _}} =
               RankGalls.handle(list, "galls_filter", %{"plant_part" => ["leaf"]})

      assert %{view: :table} = RankGalls.handle(list, "galls_view", %{"view" => "table"})
      assert %{page: 2} = RankGalls.handle(list, "galls_page", %{"page" => 2})
      assert %{selected: selected} = RankGalls.handle(list, "galls_clear", %{})
      assert selected == %{}
    end
  end
end
