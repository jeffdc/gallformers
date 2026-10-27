defmodule Gallformers.Catalog.ReadModels.Site do
  @moduledoc """
  Site-wide Gall reads (`803b` Task 12): the counts of the home and about
  pages, the home page's random Gall and the Gall IDs the sitemap lists.

  A Gall is undescribed when it has no current Inducer at species rank or
  below (`Gallformers.Catalog.ReadModels.GallPage`). Its family and genus
  are its current Inducer's (the Inducer itself when it is one), from the
  lineages `Gallformers.Taxa` gives.
  """
  import Ecto.Query

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Images
  alias Gallformers.Images.Image
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

  @type gall_counts :: %{
          galls: non_neg_integer(),
          undescribed: non_neg_integer(),
          families: non_neg_integer(),
          genera: non_neg_integer()
        }

  @type random_gall :: %{
          id: integer(),
          name: String.t(),
          undescribed: boolean(),
          image_url: String.t() | nil,
          image_creator: String.t() | nil,
          image_license: String.t() | nil,
          image_sourcelink: String.t() | nil,
          image_licenselink: String.t() | nil
        }

  @doc "How many Galls there are."
  @spec count_galls() :: non_neg_integer()
  def count_galls, do: Repo.aggregate(Gall, :count)

  @doc """
  How many Galls there are, how many are undescribed, and how many
  families and genera their current Inducers fall in.
  """
  @spec gall_counts() :: gall_counts()
  def gall_counts do
    pairs =
      Repo.all(
        from(r in Current.relationships("inducer_of"),
          distinct: true,
          select: {r.object_gall_id, r.subject_taxon_id}
        )
      )

    lineages = pairs |> Enum.map(&elem(&1, 1)) |> Taxa.lineages()

    described =
      for {gall_id, inducer_id} <- pairs,
          %{rank: rank} <- [lineages |> Map.get(inducer_id, []) |> List.last()],
          rank in Rank.species_and_below(),
          into: MapSet.new(),
          do: gall_id

    groups =
      lineages
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(&(&1.rank in [:family, :genus]))
      |> Enum.uniq_by(& &1.taxon_id)
      |> Enum.frequencies_by(& &1.rank)

    galls = count_galls()

    %{
      galls: galls,
      undescribed: galls - MapSet.size(described),
      families: Map.get(groups, :family, 0),
      genera: Map.get(groups, :genus, 0)
    }
  end

  @doc """
  A random Gall with an image (its default image, from `gall_index`), with
  its display name, undescribed flag and the image's URL and credits; nil
  when no Gall has one.
  """
  @spec random_gall() :: random_gall() | nil
  def random_gall do
    from(r in GallIndex,
      where: not is_nil(r.image_id),
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
    |> with_image()
  end

  defp with_image(nil), do: nil

  defp with_image(%GallIndex{} = row) do
    # `gall_index.image_id` references `image` (nilified on delete), so the
    # image exists.
    image = Images.get_image!(row.image_id)

    %{
      id: row.gall_id,
      name: row.name,
      undescribed: row.undescribed,
      image_url: Image.url(image),
      image_creator: image.creator,
      image_license: image.license,
      image_sourcelink: image.sourcelink,
      image_licenselink: image.licenselink
    }
  end

  @doc "Every Gall's ID, ascending."
  @spec list_gall_ids() :: [integer()]
  def list_gall_ids, do: Repo.all(from(g in Gall, order_by: g.id, select: g.id))
end
