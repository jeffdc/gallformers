defmodule GallformersWeb.Admin.TaxonomyLive.TaxonChanges do
  @moduledoc """
  The changes to a non-plant taxon that follow a Source (matter `f923`
  Task 8), asked through "Based on which Source?"
  (`GallformersWeb.Admin.TaxonomyLive.BasisPicker`): each builds the
  `Gallformers.Import.record_taxonomy_change/3` change, its summary in
  words, the confirm button's label and the flash on success, and opens the
  dialog with them. The page then runs the change on the Source chosen
  (`BasisPicker.run/2`).

  Shared by the taxonomy admin's taxon page
  (`GallformersWeb.Admin.TaxonomyLive.Edit`) and the species page's Edit
  mode (`GallformersWeb.SpeciesLive`), so both ask the same thing in the
  same words.
  """
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.TaxonomyLive.BasisPicker
  alias Phoenix.LiveView.Socket

  @parent_results 20

  @doc """
  A name: the accepted name, its rank and authorship are one statement of
  the Source it follows. `params` are the form's (`"rank"`, `"authorship"`);
  a missing one keeps the taxon's. Nothing is asked when none changed.
  """
  @spec name(Socket.t(), Taxa.Taxon.t(), String.t(), String.t(), map()) :: Socket.t()
  def name(socket, taxon, current_name, new_name, params) do
    rank = Enum.find(Rank.all(), taxon.rank, &(Atom.to_string(&1) == params["rank"]))
    current_authorship = accepted_authorship(taxon) || ""
    authorship = given_authorship(params["authorship"], current_authorship)
    renamed? = new_name != current_name

    if not renamed? and rank == taxon.rank and authorship == current_authorship do
      socket
    else
      written = Enum.join([new_name, authorship], " ") |> String.trim()
      change = {:name, taxon.id, %{name: new_name, rank: rank, authorship: authorship}}

      if renamed?,
        do:
          BasisPicker.ask(
            socket,
            change,
            "Rename #{current_name} to #{written} (#{rank_label(rank)}).",
            "Rename",
            "Renamed to #{new_name}"
          ),
        else:
          BasisPicker.ask(
            socket,
            change,
            "Name it #{written} (#{rank_label(rank)}).",
            "Save name",
            "Name updated"
          )
    end
  end

  defp given_authorship(nil, current), do: current
  defp given_authorship(given, _current), do: String.trim(given)

  @doc "Adds `name` as a synonym of the taxon `taxon_id`, named `accepted`."
  @spec add_synonym(Socket.t(), integer(), String.t(), String.t()) :: Socket.t()
  def add_synonym(socket, taxon_id, name, accepted) do
    BasisPicker.ask(
      socket,
      {:add_synonym, taxon_id, name},
      "Add #{name} as a synonym of #{accepted}.",
      "Add synonym",
      "Synonym #{name} added"
    )
  end

  @doc "Removes the synonym `synonym_id`, named `name`, of the taxon named `accepted`."
  @spec remove_synonym(Socket.t(), integer(), String.t() | nil, String.t()) :: Socket.t()
  def remove_synonym(socket, synonym_id, name, accepted) do
    BasisPicker.ask(
      socket,
      {:remove_synonym, synonym_id},
      "Remove #{name} as a synonym of #{accepted}.",
      "Remove synonym",
      "Synonym removed"
    )
  end

  @doc "Gives the taxon `taxon_id`, named `accepted`, the common name `name`."
  @spec add_common_name(Socket.t(), integer(), String.t(), String.t()) :: Socket.t()
  def add_common_name(socket, taxon_id, name, accepted) do
    BasisPicker.ask(
      socket,
      {:add_common_name, taxon_id, name},
      "Give #{accepted} the common name #{name}.",
      "Add common name",
      "Common name #{name} added"
    )
  end

  @doc "Removes the common name `common_id`, `name`, of the taxon named `accepted`."
  @spec remove_common_name(Socket.t(), integer(), String.t() | nil, String.t()) :: Socket.t()
  def remove_common_name(socket, common_id, name, accepted) do
    BasisPicker.ask(
      socket,
      {:remove_common_name, common_id},
      "Remove the common name #{name} of #{accepted}.",
      "Remove common name",
      "Common name removed"
    )
  end

  @doc "Moves the taxon `taxon_id`, named `name`, under `parent` (`%{id, name}`)."
  @spec move(Socket.t(), integer(), String.t(), %{id: integer(), name: String.t()}) ::
          Socket.t()
  def move(socket, taxon_id, name, parent) do
    BasisPicker.ask(
      socket,
      {:place, taxon_id, parent.id},
      "Move #{name} under #{parent.name}.",
      "Move",
      "Moved under #{parent.name}"
    )
  end

  @doc """
  The taxa `taxon` may move under, for a parent search: taxa of a higher
  rank in its kingdom matching `query` (two letters at least), itself left
  out.
  """
  @spec parent_candidates(Taxa.Taxon.t(), String.t()) :: [map()]
  def parent_candidates(taxon, query) do
    if String.length(String.trim(query)) >= 2 do
      ranks = Enum.filter(Rank.all(), &Rank.below?(taxon.rank, &1))
      opts = if taxon.kingdom, do: [ranks: ranks, kingdom: taxon.kingdom], else: [ranks: ranks]

      query
      |> Taxa.search(opts)
      |> Enum.reject(&(&1.id == taxon.id))
      |> Enum.take(@parent_results)
    else
      []
    end
  end

  @doc "The authorship of `taxon`'s accepted name, or nil."
  @spec accepted_authorship(Taxa.Taxon.t()) :: String.t() | nil
  def accepted_authorship(taxon),
    do: Enum.find_value(taxon.names, &(&1.status == :accepted && &1.authorship))

  @doc "A rank as a label: `:species` is \"Species\"."
  @spec rank_label(Rank.t()) :: String.t()
  def rank_label(rank), do: rank |> Atom.to_string() |> String.capitalize()

  @doc "Every rank as a select's options (`{label, value}`)."
  @spec rank_options() :: [{String.t(), String.t()}]
  def rank_options, do: Enum.map(Rank.all(), &{rank_label(&1), Atom.to_string(&1)})
end
