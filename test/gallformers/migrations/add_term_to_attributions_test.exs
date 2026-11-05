defmodule Gallformers.Migrations.AddTermToAttributionsTest do
  @moduledoc """
  Trait attributions carry the Source's term (`d213` Task A): the
  migration's backfill gives each existing Trait attribution its value as
  written as its term, and leaves other kinds' attributions alone.
  """
  # The migration module is loaded by Code.require_file/2 in setup_all
  # (priv/repo/migrations is not on the Mix elixir paths), so its functions
  # are called with apply/3.
  # credo:disable-for-this-file Credo.Check.Refactor.Apply
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Facts.Attribution

  @migration_path "priv/repo/migrations/20261102200100_add_term_to_attributions.exs"
  @migration_module Gallformers.Repo.Migrations.AddTermToAttributions

  setup_all do
    # Running the migrations (the `mix test` alias) may have loaded it already.
    unless Code.ensure_loaded?(@migration_module),
      do: Code.require_file(@migration_path, File.cwd!())

    :ok
  end

  setup do
    load_vocab!()
    %{gall: gall_fixture(), source: source_fixture("Weld", "1959")}
  end

  test "a Trait attribution's term is its value as written; others keep none", ctx do
    {:ok, %{attribution: trait}} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: ctx.gall.id, trait: "color", value: "red"},
        confirm(ctx.source, %{value_as_written: "crimson"})
      )

    {:ok, %{attribution: bare}} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: ctx.gall.id, trait: "color", value: "green"},
        confirm(ctx.source)
      )

    {:ok, %{attribution: occurrence}} =
      Catalog.assert_occurrence(
        test_actor(),
        %{gall_id: ctx.gall.id, place_id: place_id("US-CA")},
        confirm(ctx.source, %{value_as_written: "California"})
      )

    # As before the migration: no attribution has a term.
    Repo.update_all(from(a in Attribution, where: a.id in ^[trait.id, bare.id, occurrence.id]),
      set: [term: nil]
    )

    Repo.query!(apply(@migration_module, :backfill_sql, []))

    assert Repo.get!(Attribution, trait.id).term == "crimson"
    assert Repo.get!(Attribution, bare.id).term == nil
    assert Repo.get!(Attribution, occurrence.id).term == nil
  end
end
