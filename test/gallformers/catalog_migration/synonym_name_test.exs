defmodule Gallformers.CatalogMigration.SynonymNameTest do
  @moduledoc """
  The name a migrated "scientific" alias is stored under as a taxon synonym
  (alias rule 1, Jeff 2026-10-26): today's alias text without a trailing
  generation tag or author citation, so import name resolution matches it.
  Cases are real aliases from the production copy.
  """
  use ExUnit.Case, async: true

  alias Gallformers.CatalogMigration.Aliases

  test "drops a trailing generation tag" do
    assert Aliases.synonym_name("Cynips maculosus (agamic)") == "Cynips maculosus"
    assert Aliases.synonym_name("Callirhytis congregata (sexgen)") == "Callirhytis congregata"
  end

  test "drops a trailing author citation, with or without parentheses" do
    assert Aliases.synonym_name("Rhodites radicum Gillette") == "Rhodites radicum"
    assert Aliases.synonym_name("Diplolepis polita (Bassett)") == "Diplolepis polita"
    assert Aliases.synonym_name("Quercus graciliformis C.H.Mull.") == "Quercus graciliformis"
    assert Aliases.synonym_name("Andricus foo (Ashmead, 1881)") == "Andricus foo"
  end

  test "keeps a subgenus, infraspecific ranks and 19th-century three-part names" do
    assert Aliases.synonym_name("Andricus (Callirhytis) foo") == "Andricus (Callirhytis) foo"
    assert Aliases.synonym_name("Cynips hirta var undulata") == "Cynips hirta var undulata"

    assert Aliases.synonym_name("Kermes galliformis var. cueroensis") ==
             "Kermes galliformis var. cueroensis"

    assert Aliases.synonym_name("Cynips quercus spongifica") == "Cynips quercus spongifica"
    assert Aliases.synonym_name("Aloe × spinosissima") == "Aloe × spinosissima"
  end

  test "trims surrounding whitespace" do
    assert Aliases.synonym_name("  Eriophyes calaceris ") == "Eriophyes calaceris"
  end
end
