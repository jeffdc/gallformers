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
  alias Gallformers.Catalog.Vocab.TraitValue
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

  # The SQL arrays of taxon IDs a `gall_index` row (`g`) falls under.
  @host_ids "g.host_taxon_ids || g.host_ancestor_ids"
  @inducer_ids "g.inducer_ancestor_ids || array[g.inducer_taxon_id]"

  @type ranked :: %{name: String.t(), count: pos_integer(), image_url: String.t() | nil}

  @doc """
  The Host genera carrying the most distinct Galls, most first (ties by
  name), each with a small photo of one of its Galls (the lowest-ID one with
  an image) or nil. A Gall counts once per genus however many of its Hosts
  sit in it.
  """
  @spec top_host_genera(pos_integer()) :: [ranked()]
  def top_host_genera(limit) do
    @host_ids |> ranked(["genus"], limit) |> Enum.map(&Map.delete(&1, :taxon_id))
  end

  @doc """
  The current Inducers' families with how many distinct Galls each has,
  most first (ties by name), each with a small photo of one of its Galls or
  nil.
  """
  @spec inducer_families() :: [ranked()]
  def inducer_families do
    @inducer_ids |> ranked(["family"], nil) |> Enum.map(&Map.delete(&1, :taxon_id))
  end

  @doc """
  How many distinct Galls each plant taxon with a page (family, subfamily,
  tribe, subtribe, genus, section) carries, on it or anything below it,
  with a small photo of one of them, by taxon ID. A taxon with no Galls is
  absent.
  """
  @spec host_gall_counts() :: %{
          integer() => %{count: pos_integer(), image_url: String.t() | nil}
        }
  def host_gall_counts do
    @host_ids
    |> ranked(~w(family subfamily tribe subtribe genus section), nil)
    |> Map.new(&{&1.taxon_id, %{count: &1.count, image_url: &1.image_url}})
  end

  @doc """
  How many distinct Galls are known to occur in each place (by place code):
  those whose known places (`gall_index.known_place_ids`,
  `PotentialRange.known_for_galls/1`: their Hosts' native ranges, and
  introduced ranges only where the Gall is recorded) meet the place or a
  place under it. Galls with no range data are known nowhere; `everywhere`
  is how many there are. A place with no Galls is absent.
  """
  @spec place_gall_counts() :: %{
          counts: %{String.t() => pos_integer()},
          everywhere: non_neg_integer()
        }
  def place_gall_counts do
    # A range lists leaf places, and places nest at most two deep
    # (continent, country, state or province), so a Gall reaches a place's
    # ancestors in two steps up. Leaves are counted alone (a leaf is no
    # one's parent); the two steps up are counted together, distinct,
    # because a continent is reached both from a leaf country (one step)
    # and from a country's states (two). The steps are small sets; the
    # leaf pairs are not (a range averages hundreds of places), so they
    # are never deduplicated. A recursive form took 6s.
    %{rows: rows} =
      Repo.query!("""
      with leaf as (
        select g.gall_id, r.place_id
        from gall_index g cross join lateral unnest(g.known_place_ids) as r(place_id)
      ), up1 as (
        select distinct l.gall_id, ph.parent_id as place_id
        from leaf l join place_hierarchy ph on ph.place_id = l.place_id
      ), up2 as (
        select distinct u.gall_id, ph.parent_id as place_id
        from up1 u join place_hierarchy ph on ph.place_id = u.place_id
      ), counts as (
        select place_id, count(*) as n from leaf group by place_id
        union all
        select place_id, count(distinct gall_id)
        from (select * from up1 union all select * from up2) as up
        group by place_id
      )
      select p.code, c.n from counts c join place p on p.id = c.place_id
      """)

    everywhere = Repo.aggregate(from(g in GallIndex, where: g.everywhere), :count)
    %{counts: Map.new(rows, fn [code, count] -> {code, count} end), everywhere: everywhere}
  end

  @type gall_details :: %{
          image_url: String.t() | nil,
          hosts: [String.t()],
          plant_part: [String.t()],
          season: [String.t()]
        }

  @doc """
  What a search result shows of each of the Galls among `gall_ids`, by Gall
  ID, from `gall_index`: a small photo (nil without one), its current Hosts'
  names (by name), and its plant part and season values.
  """
  @spec gall_search_details([integer()]) :: %{integer() => gall_details()}
  def gall_search_details([]), do: %{}

  def gall_search_details(gall_ids) when is_list(gall_ids) do
    rows =
      Repo.all(
        from(g in GallIndex,
          left_join: i in Image,
          on: i.id == g.image_id,
          where: g.gall_id in ^gall_ids,
          select: {g.gall_id, i.path, g.host_taxon_ids, g.trait_value_ids}
        )
      )

    host_names =
      rows
      |> Enum.flat_map(fn {_, _, hosts, _} -> hosts end)
      |> Enum.uniq()
      |> then(
        &Repo.all(
          from(n in "taxon_names",
            where: n.taxon_id in ^&1 and n.status == "accepted",
            select: {n.taxon_id, n.name}
          )
        )
      )
      |> Map.new()

    values =
      rows
      |> Enum.flat_map(fn {_, _, _, ids} -> ids end)
      |> Enum.uniq()
      |> then(
        &Repo.all(
          from(v in TraitValue,
            where: v.id in ^&1 and v.trait in ["plant_part", "season"],
            select: {v.id, {v.trait, v.value}}
          )
        )
      )
      |> Map.new()

    Map.new(rows, fn {gall_id, path, hosts, value_ids} ->
      traits =
        value_ids
        |> Enum.flat_map(&List.wrap(values[&1]))
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      {gall_id,
       %{
         image_url: path && Image.sized_url(path, :small),
         hosts: hosts |> Enum.flat_map(&List.wrap(host_names[&1])) |> Enum.sort(),
         plant_part: traits |> Map.get("plant_part", []) |> Enum.sort(),
         season: traits |> Map.get("season", []) |> Enum.sort()
       }}
    end)
  end

  @doc "A small photo URL for each Gall with an image (its default image), by Gall ID."
  @spec gall_photo_urls() :: %{integer() => String.t()}
  def gall_photo_urls do
    from(g in GallIndex,
      join: i in Image,
      on: i.id == g.image_id,
      select: {g.gall_id, i.path}
    )
    |> Repo.all()
    |> Map.new(fn {gall_id, path} -> {gall_id, Image.sized_url(path, :small)} end)
  end

  # Each taxon of `ranks` that `ids` reach, with its distinct Galls, most
  # first, and the lowest-ID one's photo.
  defp ranked(ids, ranks, limit) do
    %{rows: rows} =
      Repo.query!(
        """
        select t.id, n.name, count(distinct g.gall_id),
               (array_agg(g.image_id order by g.gall_id) filter (where g.image_id is not null))[1]
        from gall_index g
        cross join lateral unnest(#{ids}) as h(id)
        join taxa t on t.id = h.id and t.rank = any($1)
        join taxon_names n on n.taxon_id = t.id and n.status = 'accepted'
        group by t.id, n.name
        order by 3 desc, 2
        limit $2
        """,
        [ranks, limit]
      )

    paths =
      Repo.all(
        from(i in Image,
          where: i.id in ^Enum.flat_map(rows, fn [_, _, _, id] -> List.wrap(id) end),
          select: {i.id, i.path}
        )
      )
      |> Map.new()

    for [taxon_id, name, count, image_id] <- rows do
      path = Map.get(paths, image_id)

      %{
        taxon_id: taxon_id,
        name: name,
        count: count,
        image_url: path && Image.sized_url(path, :small)
      }
    end
  end

  @doc "Every Gall's ID, ascending."
  @spec list_gall_ids() :: [integer()]
  def list_gall_ids, do: Repo.all(from(g in Gall, order_by: g.id, select: g.id))
end
