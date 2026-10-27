defmodule GallformersWeb.TaxonomyURL do
  @moduledoc """
  Centralized URL builder for public taxonomy pages.

  Every place that builds a URL for a taxonomy record (family, genus,
  section, intermediate) should call through this module. This ensures
  the URL scheme is defined in one place and is changeable in one place.
  """
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TreeBuilder

  @doc """
  Returns the public URL path for a taxonomy record, or nil if the
  record doesn't map to a public page.

  Accepts any map/struct with `:type` and `:name` fields (and `:rank`
  for intermediates).

  ## Examples

      iex> TaxonomyURL.public_path(%{type: "family", name: "Cynipidae"})
      "/family/Cynipidae"

      iex> TaxonomyURL.public_path(%{type: "intermediate", rank: "Subfamily", name: "Cynipinae"})
      "/subfamily/Cynipinae"

      iex> TaxonomyURL.public_path(%{type: "family", name: "Santalaceae (gall)"})
      "/family/Santalaceae%20(gall)"
  """
  @spec public_path(map()) :: String.t() | nil
  def public_path(%{type: "family", name: name}), do: "/family/#{URI.encode(name)}"
  def public_path(%{type: "genus", name: name}), do: "/genus/#{URI.encode(name)}"
  def public_path(%{type: "section", name: name}), do: "/section/#{URI.encode(name)}"

  def public_path(%{type: "intermediate", rank: rank, name: name})
      when rank not in [nil, ""],
      do: "/#{String.downcase(rank)}/#{URI.encode(name)}"

  # A taxon (`Gallformers.Taxa`): its rank is an atom.
  def public_path(%{rank: rank, name: name}) when is_atom(rank),
    do: TreeBuilder.rank_path(rank, name)

  def public_path(_), do: nil

  @doc """
  The old taxonomy ID in a numeric rank-page URL (`/genus/33`), mapped to
  its taxon's page through the crosswalk
  (`Gallformers.Taxa.get_by_legacy_id/2`), or nil.
  """
  @spec legacy_path(String.t()) :: String.t() | nil
  def legacy_path(id_str) do
    with %Taxon{} = taxon <- Taxa.get_by_legacy_id(:taxonomy, String.to_integer(id_str)) do
      public_path(%{rank: taxon.rank, name: Taxa.accepted_name(taxon)})
    end
  end

  @doc """
  Returns true if the string looks like a numeric ID (digits only).
  Used by taxonomy LiveViews to detect old ID-based URLs and redirect.
  """
  @spec numeric?(String.t()) :: boolean()
  def numeric?(s), do: Regex.match?(~r/^\d+$/, s)
end
