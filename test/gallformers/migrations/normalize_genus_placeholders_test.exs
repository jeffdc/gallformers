defmodule Gallformers.Migrations.NormalizeGenusPlaceholdersTest do
  @moduledoc """
  Tests for the data migration that normalizes `[Genus] sp` / `[Genus] spp`
  placeholder host records.

  The migration module exposes `run!/0` so this test can build a small,
  controlled fixture in the sandboxed test DB and exercise the merge / rename /
  flag-setting logic without depending on prod-shaped data.
  """
  # The migration module is loaded dynamically via Code.require_file in setup_all
  # (priv/repo/migrations is not on the Mix elixir paths), so the compiler can't
  # resolve direct calls like `@migration_module.run!()`. `apply/3` is the
  # correct mechanism here despite Credo's general preference against it.
  # credo:disable-for-this-file Credo.Check.Refactor.Apply
  use Gallformers.DataCase, async: false

  alias Gallformers.Repo

  # The migration module is loaded by Code.require_file/2 in setup_all because
  # priv/repo/migrations is not on the Mix elixir paths.
  @migration_path "priv/repo/migrations/20260515130000_normalize_genus_placeholders.exs"
  @migration_module Gallformers.Repo.Migrations.NormalizeGenusPlaceholders

  setup_all do
    Code.require_file(@migration_path, File.cwd!())
    :ok
  end

  defp insert_genus(name) do
    {:ok, tax} =
      Repo.insert(%Gallformers.Taxonomy.Taxonomy{
        name: name,
        type: "genus",
        description: "Plant"
      })

    tax
  end

  defp insert_species(name, taxoncode \\ "plant") do
    {:ok, sp} =
      Repo.insert(%Gallformers.Species.Species{
        name: name,
        taxoncode: taxoncode,
        datacomplete: false
      })

    sp
  end

  defp link_to_genus(species, genus) do
    Repo.insert_all("species_taxonomy", [
      %{species_id: species.id, taxonomy_id: genus.id}
    ])
  end

  defp insert_host_range(species, place_id) do
    Repo.insert_all("host_range", [
      %{
        species_id: species.id,
        place_id: place_id,
        precision: "exact",
        distribution_type: "native"
      }
    ])
  end

  defp insert_place(name) do
    {:ok, place} =
      Repo.insert(%Gallformers.Places.Place{
        name: name,
        code: name,
        type: "state"
      })

    place
  end

  defp insert_gallhost(gall, host) do
    Repo.insert_all("gallhost", [
      %{
        gall_species_id: gall.id,
        host_species_id: host.id,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])
  end

  defp insert_gall_species(name) do
    {:ok, sp} =
      Repo.insert(%Gallformers.Species.Species{
        name: name,
        taxoncode: "gall",
        datacomplete: false
      })

    Repo.insert_all("gall_traits", [
      %{
        species_id: sp.id,
        undescribed: false,
        detachable: "unknown"
      }
    ])

    sp
  end

  defp species_by_name(name) do
    Repo.get_by(Gallformers.Species.Species, name: name)
  end

  describe "run!/0" do
    test "renames a lone `Foo sp` to `Foo spp`, sets flag, adds synonym alias" do
      genus = insert_genus("Testgenusone")
      sp = insert_species("Testgenusone sp")
      link_to_genus(sp, genus)

      assert :ok = apply(@migration_module, :run!, [])

      assert species_by_name("Testgenusone sp") == nil
      renamed = species_by_name("Testgenusone spp")
      assert renamed != nil
      assert renamed.id == sp.id
      assert renamed.genus_placeholder == true

      # Old name preserved as scientific synonym
      aliases =
        from(a in Gallformers.Species.Alias,
          join: link in "alias_species",
          on: link.alias_id == a.id,
          where: link.species_id == ^renamed.id,
          select: %{name: a.name, type: a.type}
        )
        |> Repo.all()

      assert Enum.find(aliases, &(&1.name == "Testgenusone sp" and &1.type == "scientific")) !=
               nil
    end

    test "merges a `Foo sp` loser into existing `Foo spp` survivor" do
      genus = insert_genus("Testgenustwo")

      survivor = insert_species("Testgenustwo spp")
      link_to_genus(survivor, genus)

      loser = insert_species("Testgenustwo sp")
      link_to_genus(loser, genus)

      # Loser has a unique host_range row
      place = insert_place("TestState_Two")
      insert_host_range(loser, place.id)

      # Loser participates in a gallhost relationship
      gall = insert_gall_species("Testgallone hostmover")
      insert_gallhost(gall, loser)

      assert :ok = apply(@migration_module, :run!, [])

      # Loser deleted
      assert species_by_name("Testgenustwo sp") == nil

      survivor_refreshed = species_by_name("Testgenustwo spp")
      assert survivor_refreshed.id == survivor.id
      assert survivor_refreshed.genus_placeholder == true

      # gallhost migrated to survivor
      gh =
        from(g in "gallhost",
          where: g.gall_species_id == ^gall.id,
          select: %{host_species_id: g.host_species_id}
        )
        |> Repo.all()

      assert gh == [%{host_species_id: survivor.id}]

      # host_range migrated to survivor
      hr =
        from(h in "host_range",
          where: h.species_id == ^survivor.id,
          select: %{place_id: h.place_id}
        )
        |> Repo.all()

      assert Enum.find(hr, &(&1.place_id == place.id)) != nil
    end

    test "is idempotent — running twice yields the same final state" do
      genus = insert_genus("Testgenusthree")
      sp = insert_species("Testgenusthree sp")
      link_to_genus(sp, genus)

      assert :ok = apply(@migration_module, :run!, [])
      assert :ok = apply(@migration_module, :run!, [])

      renamed = species_by_name("Testgenusthree spp")
      assert renamed.genus_placeholder == true

      # Verify no duplicate alias was created on the second pass
      alias_count =
        from(a in Gallformers.Species.Alias,
          join: link in "alias_species",
          on: link.alias_id == a.id,
          where: link.species_id == ^renamed.id and a.name == "Testgenusthree sp",
          select: count(a.id)
        )
        |> Repo.one()

      assert alias_count == 1
    end

    test "skips host_range row when (survivor_id, place_id) already exists on survivor" do
      genus = insert_genus("Testgenusfour")

      survivor = insert_species("Testgenusfour spp")
      link_to_genus(survivor, genus)

      loser = insert_species("Testgenusfour sp")
      link_to_genus(loser, genus)

      # Both reference the same place (conflict on (species_id, place_id) PK)
      place = insert_place("TestState_Four")
      insert_host_range(loser, place.id)
      insert_host_range(survivor, place.id)

      assert :ok = apply(@migration_module, :run!, [])

      assert species_by_name("Testgenusfour sp") == nil

      # Survivor still has exactly one row for that place
      count =
        from(h in "host_range",
          where: h.species_id == ^survivor.id and h.place_id == ^place.id,
          select: count(h.species_id)
        )
        |> Repo.one()

      assert count == 1
    end

    test "leaves already-correct `[Genus] spp` records intact, just sets flag" do
      genus = insert_genus("Testgenusfive")
      existing = insert_species("Testgenusfive spp")
      link_to_genus(existing, genus)

      assert :ok = apply(@migration_module, :run!, [])

      reloaded = Repo.get!(Gallformers.Species.Species, existing.id)
      assert reloaded.name == "Testgenusfive spp"
      assert reloaded.genus_placeholder == true
    end

    test "renames and flags a `[Genus]  sp` row with extra internal whitespace" do
      # Regression: the rename regex used to require exactly one space, while
      # the count/mark regex tolerated multiple. A `[Genus]  sp` row would be
      # counted but never renamed or flagged, silently slipping through.
      genus = insert_genus("Testgenussix")
      sp = insert_species("Testgenussix  sp")
      link_to_genus(sp, genus)

      assert :ok = apply(@migration_module, :run!, [])

      assert species_by_name("Testgenussix  sp") == nil
      renamed = species_by_name("Testgenussix spp")
      assert renamed != nil
      assert renamed.id == sp.id
      assert renamed.genus_placeholder == true
    end
  end
end
