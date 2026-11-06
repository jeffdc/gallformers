defmodule GallformersWeb.PaletteTest do
  @moduledoc """
  What the command palette offers (`GallformersWeb.Palette`): with nothing
  typed, the fixed Go to list (and a curator's commands); for a query,
  shortcuts into the ID tool, results by kind, and every result.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures

  alias Gallformers.Articles
  alias GallformersWeb.Palette

  defp group(groups, title), do: Enum.find(groups, &(&1.title == title))
  defp hrefs(nil), do: []
  defp hrefs(group), do: Enum.map(group.rows, & &1.href)
  defp labels(group), do: Enum.map(group.rows, & &1.label)

  describe "with nothing typed" do
    test "the fixed Go to list" do
      groups = Palette.groups("", admin?: false)

      assert hrefs(group(groups, "Go to")) ==
               ~w(/id /galls /hosts /places /articles /keys /glossary)

      assert group(groups, "Curators") == nil
    end

    test "a curator also gets their commands" do
      groups = Palette.groups("", admin?: true)

      assert labels(group(groups, "Curators")) == [
               "Edit this page",
               "Add from observation…",
               "Sources to review",
               "Changes"
             ]

      assert hrefs(group(groups, "Curators")) ==
               ~w(?edit /admin/observation /admin/review /admin/changes)
    end
  end

  describe "for a query" do
    test "a plant: Galls on it in the ID tool, and its page" do
      plant = plant_fixture(name: "Quercus paletteana")
      groups = Palette.groups("paletteana", admin?: false)

      assert [shortcut | _] = group(groups, "Go to").rows
      assert {shortcut.prefix, shortcut.label} == {"Galls on ", "Quercus paletteana"}
      assert shortcut.href == "/id?h=Quercus+paletteana"
      assert "/host/#{plant.id}" in hrefs(group(groups, "Host plants"))
    end

    test "a Gall: its page" do
      gall = gall_fixture(%{name: "Andricus paletteus"})

      assert "/gall/#{gall.id}" in hrefs(
               group(Palette.groups("paletteus", admin?: false), "Galls")
             )
    end

    test "an article: its page" do
      {:ok, _} =
        Articles.create_article(%{
          title: "Palette rearing notes",
          slug: "palette-rearing",
          author: "A. Kranz",
          content: "Text.",
          is_published: true
        })

      assert hrefs(group(Palette.groups("palette rearing", admin?: false), "Articles")) ==
               ["/articles/palette-rearing"]
    end

    test "a curator: a Source under review, to review" do
      audit_test_metadata(%{})
      source = source_fixture("Paletteweld", "1959")

      Gallformers.AuditFixtures.package_for(source)
      |> Ecto.Changeset.change(status: :awaiting_review)
      |> Repo.update!()

      [row] = group(Palette.groups("Paletteweld", admin?: true), "Review").rows

      assert row.label =~ "Review: "
      assert row.label =~ "Paletteweld"
      assert row.href == "/admin/review/sources/#{source.id}"
      assert group(Palette.groups("Paletteweld", admin?: false), "Review") == nil
    end

    test "a Source not under review has no Review row" do
      source_fixture("Palettequiet", "1960")
      assert group(Palette.groups("Palettequiet", admin?: true), "Review") == nil
    end

    test "the last row: every result, on the search page" do
      groups = Palette.groups("quercus", admin?: false)
      assert %{title: nil, rows: [%{href: "/globalsearch?q=quercus"}]} = List.last(groups)
    end

    test "rows are numbered across the groups, for the keyboard" do
      groups = Palette.groups("", admin?: true)
      indexes = groups |> Enum.flat_map(& &1.rows) |> Enum.map(& &1.index)
      assert indexes == Enum.to_list(0..(length(indexes) - 1))
    end
  end
end
