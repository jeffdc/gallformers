defmodule GallformersWeb.RankPageTest do
  use Gallformers.DataCase, async: true

  # Reads the converted seeds' taxonomy.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Taxa
  alias GallformersWeb.RankPage

  describe "crumbs/1" do
    test "the ancestors with pages, linked by encoded name; genus and section italic" do
      [andricus] = Taxa.get_by_name("Andricus", :genus)

      assert [
               %{name: "Cynipidae", path: "/family/Cynipidae", italic: false},
               %{name: "Cynipinae", path: "/subfamily/Cynipinae"},
               %{name: "Cynipini", path: "/tribe/Cynipini", italic: false}
             ] = RankPage.crumbs(andricus.id)
    end

    test "a family has none" do
      [cynipidae] = Taxa.get_by_name("Cynipidae", :family)
      assert RankPage.crumbs(cynipidae.id) == []
    end
  end
end
