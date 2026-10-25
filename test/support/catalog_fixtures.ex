defmodule Gallformers.CatalogFixtures do
  @moduledoc """
  Galls, Sources, plants and vocabularies for Catalog tests
  (`Gallformers.Catalog`). Every write is audited as
  `Gallformers.DataCase.test_actor/0`.

  ## Vocabularies in tests

  The test database has no Catalog vocabulary rows: `priv/repo/test_seeds.sql`
  does not copy `traits.json`, so the contract stays the one source of truth
  and the loader itself is what tests exercise. A test that needs Trait or
  generation values calls `load_vocab!/0` in its setup. The vocabulary
  tables are unique on their values, so such test modules are not async
  (concurrent loads would wait on each other inside their sandboxes).
  """

  import Ecto.Query, only: [from: 2]
  import Gallformers.DataCase, only: [test_actor: 0]
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Repo
  alias Gallformers.Sources

  @doc "Loads the Catalog vocabularies (`Gallformers.Catalog.load_vocab/1`)."
  def load_vocab! do
    {:ok, _counts} = Catalog.load_vocab(test_actor())
    :ok
  end

  @doc """
  Creates a Gall. Defaults: a unique name. `attrs` may give `:generation`
  (a generation value, e.g. `"agamic"`; needs the vocabularies loaded) in
  place of `:generation_value_id`.
  """
  def gall_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    attrs =
      case Map.pop(attrs, :generation) do
        {nil, attrs} ->
          attrs

        {value, attrs} ->
          Map.put(attrs, :generation_value_id, Catalog.get_generation_value(value).id)
      end

    defaults = %{name: "Gall #{System.unique_integer([:positive])}"}
    {:ok, gall} = Catalog.create_gall(test_actor(), Map.merge(defaults, attrs))
    gall
  end

  @doc "A plant taxon (kingdom Plantae). Defaults: a species with a unique name."
  def plant_fixture(attrs \\ %{}) do
    attrs
    |> Map.new()
    |> Map.put_new(:origin, :powo)
    |> Map.put_new(:kingdom, "Plantae")
    |> Map.put_new(:name, "Quercus #{System.unique_integer([:positive])}")
    |> taxon_fixture()
  end

  @doc """
  Gives a plant taxon host-range rows (`host_range`, read-only to the
  Catalog), keyed by `taxon_id` as the data migration re-keys them. Today's
  `species_id` key is still required, so a `species` row with the taxon's ID
  is made first, as the data migration keeps plant IDs. `places` are
  `{place_code, precision}` or `{place_code, precision, distribution_type}`.
  """
  def host_range_fixture(plant, places) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      "species",
      [
        %{
          id: plant.id,
          name: "Plant #{plant.id}",
          taxoncode: "plant",
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing
    )

    rows =
      for entry <- places do
        {code, precision, distribution} =
          case entry do
            {code, precision} -> {code, precision, "native"}
            {code, precision, distribution} -> {code, precision, distribution}
          end

        %{
          species_id: plant.id,
          taxon_id: plant.id,
          place_id: place_id(code),
          precision: precision,
          distribution_type: distribution
        }
      end

    Repo.insert_all("host_range", rows)
    :ok
  end

  @doc """
  An old-model genus placeholder plant (`species` row, e.g. "Quercus spp."),
  which the data migration turns into no taxon. Returns its species ID.
  """
  def placeholder_species_fixture(name) do
    now = DateTime.utc_now(:second)

    {1, [%{id: id}]} =
      Repo.insert_all(
        "species",
        [
          %{
            name: "#{name} #{System.unique_integer([:positive])}",
            taxoncode: "plant",
            genus_placeholder: true,
            inserted_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    id
  end

  @doc "A seeded place's ID by code (`priv/repo/test_seeds.sql`)."
  def place_id(code) do
    Repo.one!(from(p in "place", where: p.code == ^code, select: p.id))
  end

  @doc "A publication Source authored on `authored` (a partial date)."
  def source_fixture(title, authored) do
    {:ok, source} =
      Sources.create_source(%{
        title: "#{title} #{System.unique_integer([:positive])}",
        author: "Weld, L. H.",
        pubyear: String.slice(authored, 0, 4),
        link: "https://example.com/#{System.unique_integer([:positive])}",
        citation: "#{title}.",
        license: "Public Domain / Copyright Expired"
      })

    {:ok, source} =
      Sources.update_source_details(source, %{kind: "publication", authored: authored})

    source
  end

  @doc """
  The Gallformers Source. Only one Source may be kind `gallformers`, so a
  test module using it must not be async.
  """
  def gallformers_source do
    {:ok, source} =
      Sources.create_source(%{
        title: "Gallformers Notes #{System.unique_integer([:positive])}",
        author: "Gallformers Contributors",
        pubyear: "2020",
        link: "https://gallformers.org",
        citation: "Gallformers.",
        license: "Public Domain / CC0"
      })

    Repo.query!("UPDATE source SET kind = NULL WHERE kind = 'gallformers'")
    {:ok, source} = Sources.update_source_details(source, %{kind: "gallformers"})
    source
  end

  @doc "Attribution attrs for `source` confirming, merged with `extra`."
  def confirm(source, extra \\ %{}),
    do: Map.merge(%{source_id: source.id, stance: :confirm}, extra)

  @doc "Attribution attrs for `source` denying, merged with `extra`."
  def deny(source, extra \\ %{}), do: Map.merge(%{source_id: source.id, stance: :deny}, extra)
end
