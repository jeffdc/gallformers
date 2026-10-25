defmodule Gallformers.Catalog.TaxonListenerTest do
  @moduledoc """
  The Catalog listens to "taxon changed" events (`8567` rule 6), registered
  through application config so Taxa never references it.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog.TaxonListener
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Event

  test "is registered as a taxon-changed listener" do
    assert TaxonListener in Taxa.Events.listeners()
  end

  test "accepts moves and renames" do
    assert TaxonListener.taxon_changed(%Event{type: :move, taxon_id: 1}) == :ok

    assert TaxonListener.taxon_changed(%Event{
             type: :rename,
             taxon_id: 1,
             old_name: "Andricus foo",
             new_name: "Andricus bar"
           }) == :ok
  end

  test "taxonomy changes go through with the Catalog listening" do
    family = taxon_fixture(rank: :family, name: "Cynipidae")
    other = taxon_fixture(rank: :family, name: "Figitidae")
    genus = taxon_fixture(rank: :genus, name: "Andricus", parent: family)

    assert {:ok, _} = Taxa.place(test_actor(), genus, other)
    assert {:ok, _} = Taxa.rename(test_actor(), genus, "Callirhytis")
  end
end
