defmodule Gallformers.Repo.Migrations.DropIncludeRangeAdjustment do
  @moduledoc """
  Drops the `include` range adjustment (Jeff, 2026-10-26): a Gall's range
  never leaves every one of its Hosts' ranges, so its potential range is
  their union, minus `exclude`, restricted by `only`. A place where a Source
  says the Gall occurs but no Host grows is a recorded occurrence
  (`occurrence_facts`), not a range adjustment.

  No `include` rows exist outside tests, so none are moved. Range Facts now
  compete in a slot per Gall and place (`Gallformers.Catalog.Facts.RangeFact`);
  any made before this have none, and the catalog data migration
  (`Gallformers.CatalogMigration`), which deletes and remakes every range
  Fact, gives them theirs.
  """
  use Ecto.Migration

  def up do
    drop constraint(:range_facts, :range_facts_adjustment_check)

    create constraint(:range_facts, :range_facts_adjustment_check,
             check: "adjustment IN ('exclude', 'only')"
           )
  end

  def down do
    drop constraint(:range_facts, :range_facts_adjustment_check)

    create constraint(:range_facts, :range_facts_adjustment_check,
             check: "adjustment IN ('include', 'exclude', 'only')"
           )
  end
end
