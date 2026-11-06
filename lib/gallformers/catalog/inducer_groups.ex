defmodule Gallformers.Catalog.InducerGroups do
  @moduledoc """
  Plain-language groups for the Gallformer (Inducer) families: what a
  naturalist calls them ("Gall wasps", "Gall midges", "Rust fungi"), for the
  home page and Browse (matter bc0d).

  This is content, not taxonomy: the tree holds nothing above family, so the
  groups live here until they are stored as data. A family no group names
  falls in "Other". Each family appears in one group.
  """

  @groups [
    {"Gall wasps", ~w(Cynipidae Diplolepididae)},
    {"Gall midges", ~w(Cecidomyiidae)},
    {"Mites", ~w(Eriophyidae)},
    {"Aphids, adelgids and phylloxerans", ~w(Aphididae Adelgidae Phylloxeridae)},
    {"Psyllids", ~w(Aphalaridae Calophyidae Homotomidae Psyllidae Triozidae)},
    {"Other wasps and sawflies",
     ~w(Braconidae Epichrysomallidae Eulophidae Eurytomidae Ormyridae Pteromalidae
        Tanaostigmatidae Torymidae Tenthredinidae Xyelidae)},
    {"Other flies", ~w(Agromyzidae Anthomyiidae Chloropidae Tephritidae)},
    {"Moths", ~w(Alucitidae Bucculatricidae Cecidosidae Choreutidae Cosmopterigidae Gelechiidae
        Gracillariidae Heliozelidae Momphidae Nepticulidae Pyralidae Sesiidae Thyrididae
        Tortricidae Ypsolophidae)},
    {"Beetles", ~w(Anthribidae Brentidae Buprestidae Cerambycidae Curculionidae)},
    {"Thrips", ~w(Phlaeothripidae Thripidae)},
    {"Rust fungi", ~w(Coleosporiaceae Cronartiaceae Pileolariaceae Pucciniaceae Pucciniastraceae
        Raveneliaceae Uropyxidaceae Zaghouaniaceae)},
    {"Other fungi and fungus-like organisms",
     ~w(Anthracoideaceae Botryosphaeriaceae Cryptobasidiaceae Cyttariaceae Erysiphaceae
        Exobasidiaceae Peronosporaceae Physodermataceae Plasmodiophoridae Protomycetaceae
        Sclerotiniaceae Synchytriaceae Taphrinaceae Ustilaginaceae Venturiaceae)},
    {"Bacteria, phytoplasmas and viruses",
     ~w(Acheloplasmataceae Fimoviridae Pseudomonadaceae Rhizobiaceae)},
    {"Nematodes", ~w(Anguinidae Neotylenchidae)},
    {"Parasitic plants", ~w(Santalaceae)}
  ]

  @group_of Map.new(for {group, families} <- @groups, family <- families, do: {family, group})

  @typedoc "A family's count, as `Gallformers.Catalog.ReadModels.Site` gives it."
  @type family :: %{name: String.t(), count: non_neg_integer(), image_url: String.t() | nil}

  @type group :: %{
          name: String.t(),
          slug: String.t(),
          count: non_neg_integer(),
          image_url: String.t() | nil,
          families: [family()]
        }

  @doc "The group a family belongs to: its plain-language name, or \"Other\"."
  @spec group_of(String.t()) :: String.t()
  def group_of(family), do: Map.get(@group_of, family, "Other")

  @doc """
  The families gathered into their groups, most Galls first; each group's
  families most Galls first, and its photo the largest family's. Empty
  groups are left out.
  """
  @spec groups([family()]) :: [group()]
  def groups(families) do
    families
    |> Enum.group_by(&group_of(&1.name))
    |> Enum.map(fn {name, fams} ->
      fams = Enum.sort_by(fams, &{-&1.count, &1.name})

      %{
        name: name,
        slug: slug(name),
        count: fams |> Enum.map(& &1.count) |> Enum.sum(),
        image_url: Enum.find_value(fams, & &1.image_url),
        families: fams
      }
    end)
    |> Enum.reject(&(&1.count == 0))
    |> Enum.sort_by(&{-&1.count, &1.name})
  end

  defp slug(name), do: name |> String.downcase() |> String.replace(~r/[^a-z]+/, "-")
end
