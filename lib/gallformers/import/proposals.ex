defmodule Gallformers.Import.Proposals do
  @moduledoc """
  What accepting a queue item's proposal decides (`6611` Task 3), for one
  item (the review's Accept) and for many (`Gallformers.Import.accept_proposals/2`).

  | Item | Accepting decides |
  |---|---|
  | a name (`t1`): ambiguous, unresolved, held-valid synonym | `%{"taxon_id" => proposed}` |
  | an unresolved Host (`t2`) | `%{"taxon_id" => proposed, "add_synonym" => true}`: the plant, with the Source's spelling as its synonym (`Gallformers.Import.HostDecisions`) |
  | a Gall (`g1`) | `%{"gall_id" => proposed}`, or `%{"new" => true}` when new is proposed; never an undescribed match or one with `"conflicts"` (only a `"best"` match, weak) |
  | a statement set aside | `%{"keep" => true}` |
  | a Trait term (`Gallformers.Import.TraitTerms`) | `%{"category" => c}`, when the producer and the checkers agree on `c` for every Gall it covers |
  | a rename proposal | `%{"accept" => true}` |
  | a split question (`Gallformers.Import.SplitQuestions`) | nothing: a daughter suggested by a shared Host is only a suggestion (weak) |

  `"proposed"` is set only where resolution is confident
  (`Gallformers.Import.Resolver`, `Gallformers.Import.GallMatcher`,
  `Gallformers.Import.HostSuggestions`: an edit-distance Host name, a
  doubtful WCVP record or a choice between several is never proposed).
  An item with candidates or suggestions but nothing proposed is only a
  suggestion to check (`:weak`), as is a rename to a name another Gall has
  and the package's Source when several match; it is never accepted in
  bulk. Disputes, retractions and what is only acknowledged (same-date
  conflicts, generations outside their group, disagreeing acts) have no
  proposal. Nor does an item whose proposal a curator rejected
  (`proposal_rejected_at`).
  """
  alias Gallformers.Import.QueueItem

  @typedoc "Why an item has no proposal to accept."
  @type reason :: :rejected | :weak | :no_proposal

  @doc "The decision accepting `item`'s proposal makes, or why there is none."
  @spec proposed(QueueItem.t()) :: {:ok, map()} | {:none, reason()}
  def proposed(%QueueItem{proposal_rejected_at: %DateTime{}}), do: {:none, :rejected}
  def proposed(%QueueItem{} = item), do: answer(item)

  @doc """
  Whether `item` has an answer to reject: a proposal or a suggestion
  (`proposed/1` ignoring any rejection gives `{:ok, _}` or `{:none, :weak}`).
  """
  @spec rejectable?(QueueItem.t()) :: boolean()
  def rejectable?(%QueueItem{} = item), do: answer(item) != {:none, :no_proposal}

  defp answer(%QueueItem{kind: :gall_rename, proposal: %{"collision" => true}}),
    do: {:none, :weak}

  defp answer(%QueueItem{kind: :gall_rename, proposal: %{"to" => to}}) when is_binary(to),
    do: {:ok, %{"accept" => true}}

  # A split question's suggestion (a shared Host) is only one to check.
  defp answer(%QueueItem{kind: :split_inducer, proposal: %{"taxon_id" => id}})
       when is_integer(id),
       do: {:none, :weak}

  defp answer(%QueueItem{kind: :set_aside_statement} = item) do
    if item.proposal["keep"] == true,
      do: {:ok, %{"keep" => true}},
      else: {:none, :no_proposal}
  end

  defp answer(%QueueItem{kind: :trait_term, proposal: %{"category" => c}}) when is_binary(c),
    do: {:ok, %{"category" => c}}

  defp answer(%QueueItem{kind: kind}) when kind in [:trait_term, :set_aside_term],
    do: {:none, :no_proposal}

  defp answer(%QueueItem{kind: kind})
       when kind in [:dispute, :same_date_conflict, :generation_outside_group],
       do: {:none, :no_proposal}

  defp answer(%QueueItem{statement_ref: "source", proposal: proposal}), do: candidates(proposal)
  defp answer(%QueueItem{statement_ref: "retracts", proposal: proposal}), do: candidates(proposal)

  defp answer(%QueueItem{statement_ref: "t" <> _, proposal: %{"proposed" => id}} = item)
       when is_integer(id) do
    if item.kind == :unresolved_host,
      do: {:ok, %{"taxon_id" => id, "add_synonym" => true}},
      else: {:ok, %{"taxon_id" => id}}
  end

  # An undescribed match, or one conflicting with what the Source says, is
  # never firm (`Gallformers.Import.GallMatcher` gives such a Gall only a
  # `"best"` match; this guards items queued before it did).
  defp answer(%QueueItem{statement_ref: "g" <> _, proposal: %{"proposed" => id}} = item)
       when is_integer(id) do
    if item.kind == :undescribed_gall or List.wrap(item.proposal["conflicts"]) != [],
      do: {:none, :weak},
      else: {:ok, %{"gall_id" => id}}
  end

  defp answer(%QueueItem{statement_ref: "g" <> _, proposal: %{"proposed" => "new"}}),
    do: {:ok, %{"new" => true}}

  defp answer(%QueueItem{statement_ref: "t" <> _, proposal: proposal}), do: candidates(proposal)
  defp answer(%QueueItem{statement_ref: "g" <> _, proposal: proposal}), do: candidates(proposal)
  defp answer(_item), do: {:none, :no_proposal}

  # Candidates or suggestions, but nothing proposed: a suggestion to check.
  defp candidates(proposal) do
    if List.wrap(proposal["candidate_ids"]) != [] or List.wrap(proposal["suggestions"]) != [],
      do: {:none, :weak},
      else: {:none, :no_proposal}
  end
end
