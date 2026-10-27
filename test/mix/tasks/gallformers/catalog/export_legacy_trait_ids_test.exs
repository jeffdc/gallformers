defmodule Mix.Tasks.Gallformers.Catalog.ExportLegacyTraitIdsTest do
  @moduledoc """
  `mix gallformers.catalog.export_legacy_trait_ids` (`803b` Task 9): the
  old vocabulary tables' row IDs (old ID-tool bookmarks hold them) mapped
  to the Trait values they became, matched by name as the data migration
  matches the old Trait joins (`Gallformers.CatalogMigration.LegacyFacts`),
  written as `legacy_trait_ids.csv` and read back by
  `Gallformers.Catalog.legacy_trait_values/1`.

  The test database's old vocabulary tables are empty; each test fills
  them. Not async: the old vocabulary tables are shared.
  """
  use Gallformers.DataCase, async: false

  import ExUnit.CaptureIO

  alias Gallformers.Catalog
  alias Mix.Tasks.Gallformers.Catalog.ExportLegacyTraitIds

  setup do
    path =
      Path.join(System.tmp_dir!(), "legacy_trait_ids_#{System.unique_integer([:positive])}.csv")

    on_exit(fn -> File.rm(path) end)

    Repo.insert_all("color", [%{id: 7, color: "red"}, %{id: 3, color: "chartreuse"}])
    Repo.insert_all("plant_part", [%{id: 12, part: "upper leaf"}])
    Repo.insert_all("form", [%{id: 1, form: "non-gall"}, %{id: 2, form: "witches broom"}])
    Repo.insert_all("season", [%{id: 4, season: "Spring"}])
    Repo.insert_all("walls", [%{id: 5, walls: "thin"}])

    %{path: path}
  end

  test "writes each old vocabulary row's table, ID and new Trait value", %{path: path} do
    output = capture_io(fn -> ExportLegacyTraitIds.run(["--output", path]) end)

    assert File.read!(path) ==
             """
             table,old_id,trait,value
             color,7,color,red
             form,2,form,witches broom
             plant_part,12,plant_part,upper leaf
             season,4,season,Spring
             walls,5,walls,thin
             """

    assert output =~ "Wrote 5 rows to #{path}"

    assert output =~
             "Not in the vocabulary (left out): color 3 \"chartreuse\", form 1 \"non-gall\""
  end

  test "the file reads back as a map from old table and ID to Trait value", %{path: path} do
    capture_io(fn -> ExportLegacyTraitIds.run(["--output", path]) end)

    assert {:ok, values} = Catalog.legacy_trait_values(path)
    assert values[{"color", 7}] == %{trait: "color", value: "red"}
    assert values[{"plant_part", 12}] == %{trait: "plant_part", value: "upper leaf"}
    assert values[{"form", 1}] == nil
    assert map_size(values) == 5
  end

  test "a missing or malformed file is an error" do
    assert {:error, message} = Catalog.legacy_trait_values("/nonexistent/legacy_trait_ids.csv")
    assert message =~ "legacy_trait_ids.csv"

    path = Path.join(System.tmp_dir!(), "bad_trait_ids_#{System.unique_integer([:positive])}.csv")
    File.write!(path, "table,old_id,trait,value\ncolor,seven,color,red\n")
    on_exit(fn -> File.rm(path) end)

    assert {:error, message} = Catalog.legacy_trait_values(path)
    assert message =~ "row 2"
  end
end
