defmodule Gallformers.Catalog.FactNotesTest do
  @moduledoc """
  A Gall's Facts by the Gall page's keys (`Gallformers.Catalog.find_gall_fact/2`)
  and the notes curators write on them (`Gallformers.Catalog.FactNote`,
  matter `ec2c`): a record of its own, not a statement, so the Fact's
  standing does not change.

  Not async: the tests load the vocabularies.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.FactNote
  alias Gallformers.Facts

  setup do
    {:ok, user} =
      Gallformers.Accounts.create_user(%{
        auth0_id: "auth0|notes-#{System.unique_integer([:positive])}",
        display_name: "Ada"
      })

    :ok = put_test_actor(Actor.user(user.id, "Ada"))
    load_vocab!()
    source = source_fixture("Weld", "1959")
    gall = gall_fixture()
    oak = plant_fixture(name: "Quercus notata")

    {:ok, %{fact: host}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: oak.id, object_gall_id: gall.id},
        confirm(source)
      )

    %{gall: gall, oak: oak, host: host, user: user, source: source}
  end

  describe "find_gall_fact/2" do
    test "finds a Fact by its key, or nil when there is none", ctx do
      assert Catalog.find_gall_fact(ctx.gall.id, {:host, ctx.oak.id}) == {:ok, ctx.host.id}
      assert Catalog.find_gall_fact(ctx.gall.id, {:trait, "color", "red"}) == {:ok, nil}
      assert Catalog.find_gall_fact(ctx.gall.id, {:alias, "oak apple"}) == {:ok, nil}
      assert Catalog.find_gall_fact(ctx.gall.id, {:occurrence, place_id("US-CA")}) == {:ok, nil}

      assert Catalog.find_gall_fact(ctx.gall.id, {:range, :exclude, place_id("US-CA")}) ==
               {:ok, nil}
    end

    test "a key that cannot name a Fact is an error", ctx do
      assert {:error, _} = Catalog.find_gall_fact(ctx.gall.id, {:trait, "color", "plaid"})
      wasp = Gallformers.TaxaFixtures.taxon_fixture(kingdom: "Animalia")
      assert {:error, _} = Catalog.find_gall_fact(ctx.gall.id, {:host, wasp.id})
      assert {:error, :unknown_key} = Catalog.find_gall_fact(ctx.gall.id, {:colour, "red"})
    end
  end

  describe "add_fact_note/3" do
    test "records the note with its author, leaving the Fact's standing", ctx do
      before = Facts.get_fact!(ctx.host.id)

      assert {:ok, %FactNote{} = note} =
               Catalog.add_fact_note(test_actor(), ctx.host.id, "  Only on young trees.  ")

      assert note.text == "Only on young trees."
      assert note.author_user_id == ctx.user.id
      assert note.author_name == "Ada"
      assert Facts.get_fact!(ctx.host.id).standing == before.standing

      assert Catalog.list_fact_notes([ctx.host.id]) == %{ctx.host.id => [note]}
    end

    test "a blank note is refused", ctx do
      assert {:error, changeset} = Catalog.add_fact_note(test_actor(), ctx.host.id, "  ")
      assert errors_on(changeset).text != []
    end
  end
end
