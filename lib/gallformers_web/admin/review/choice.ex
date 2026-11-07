defmodule GallformersWeb.Admin.Review.Choice do
  @moduledoc """
  One answer a curator may give a question
  (`GallformersWeb.Admin.Review.Questions`):

    * `label` — what it is, in the curator's words; `hint` — what it does.
    * `decision` — the decision map it sends
      (`Gallformers.Import.decide_queue_item/3`), or nil when the curator
      picks something first: then `picker` says what (`:plant`, `:taxon`,
      `:gall`, `{:trait_value, trait}`, `:place`, `:statement`: a Trait
      value, a Host or a place to state, `:galls`: a category, or none,
      for each Gall a Trait term covers, `:tree`: what a synonym becomes
      when the Source is right, `:statements`: keep or leave out each of
      the Source's statements a chosen Gall disagrees with, or
      `:generation`: the generation of a Gall to create, `:reason`: why a
      taxonomic statement is declined (a reason, required), `{:trait_values,
      trait}`: several values of a Trait, `:keep_galls`: which Galls a
      group of identical disputes is kept for, `{:parent, rank}`: the
      taxon a new taxon of `rank` goes under, or none, `{:reading, name}`: the
      plant a Host dispute's Host name means, kept so, `:section`: one of
      `sections`, for a Host named by a common name) and
      `Questions.picked_decision/2` builds the map from the pick; `as` is
      the decision key a picked Trait value goes under, for a `:plant`
      `"common_name"`: the Host is a common name, so no synonym is added,
      or for a `{:reading, name}` `"host_taxon_id"`: the Host is above
      species rank, so the plant picked is chosen for the dispute's
      statements only, its name not read as it.
    * `base` — for a `:statements` or `{:reading, name}` choice, the
      decision the picks add to (`%{"gall_id" => id}`, `%{"keep" => true}`).
    * `proposed` — it is the item's proposed answer.
    * `tally` — who chose it, shown beside it whether recommended or not
      ("Chosen by the producer and checker 1, for all 10 Galls").
    * `effect` — what Decide does with it, when that is more than its
      hint; for a value picked, `%{value}` stands for the value (or the
      values) picked, `%{taxon}` for the plant a `{:reading, name}` reads.
    * `values` — for a `{:trait_values, trait}` choice, the values the
      readers chose, listed first and ticked to start with.
    * `sections` — for a `:section` choice, the sections to choose from;
      for a `{:reading, name}` choice, or a `:statements` choice's Host
      above species rank, those its search lists first (the Host is a
      genus with sections): `%{id, name, common_name}` each,
      `common_name` nil when the tree holds none.
    * `pending` — the backend doesn't take this decision yet (`6611`
      Task 3): hide it until it does.

  What an answer shows besides its label (matter `d213`, Names and Galls
  steps):

    * `identity` — a taxon's or plant's identity line: `%{family, galls,
      hosts, host_count, synonyms, path, held}`, any key nil;
      `holding` — whether that taxon already holds the Source's name, in a
      line: `%{kind: :yes | :near | :no, text}`.
    * `comparison` — a Gall's side-by-side rows against what the Source
      says: `%{who, gall, rows: [%{label, source, gall, mark}],
      description: {source_text, gall_text}, meta, quoted_in, path}`.
    * `tags` — short labels beside it (`%{text, kind: :best | :conflict}`).
    * `statements` — for a `:statements` choice, the Source's statements
      the Gall disagrees with: `%{key, label, refs, keep, reading, as,
      other, note, left, read}` (`reading` the Host name a curator may
      read as another plant, `other` that option's label and `note` the
      line under its search; `as` `"host_taxon_id"` for a Host above
      species rank, the plant picked going in for this Gall only).
    * `generations` — for a `:generation` choice, `%{value, held}` each.
    * `prefill` — for a `{:parent, rank}` choice, the taxon picked to
      start with (`%{id, name}`: the tree's genus of a new species).
    * `note` — a line under the follow-up once chosen (where a new taxon
      goes in the tree).
    * `effects` — for a `:tree` choice, what each pick does (`:split`,
      `:synonym_of`, `%{taxon}` standing for the taxon picked).
  """

  @enforce_keys [:label]
  defstruct [
    :label,
    :hint,
    :decision,
    :picker,
    :as,
    :base,
    :identity,
    :holding,
    :comparison,
    :note,
    :tally,
    :effect,
    :prefill,
    values: [],
    effects: %{},
    tags: [],
    statements: [],
    generations: [],
    sections: [],
    proposed: false,
    pending: false
  ]

  @type picker ::
          :plant
          | :taxon
          | :gall
          | :place
          | :statement
          | :galls
          | :tree
          | :statements
          | :generation
          | :reason
          | :keep_galls
          | {:trait_value, String.t()}
          | {:trait_values, String.t()}
          | {:parent, Gallformers.Taxa.Rank.t()}
          | {:reading, String.t()}
          | :section

  @type t :: %__MODULE__{
          label: String.t(),
          hint: String.t() | nil,
          decision: map() | nil,
          picker: picker() | nil,
          as: String.t() | nil,
          base: map() | nil,
          identity: map() | nil,
          holding: %{kind: :yes | :near | :no, text: String.t()} | nil,
          comparison: map() | nil,
          note: String.t() | nil,
          tally: String.t() | nil,
          effect: String.t() | nil,
          prefill: %{id: integer(), name: String.t()} | nil,
          values: [String.t()],
          effects: %{optional(atom()) => String.t()},
          tags: [%{text: String.t(), kind: :best | :conflict}],
          statements: [map()],
          generations: [%{value: String.t(), held: boolean()}],
          sections: [%{id: integer(), name: String.t(), common_name: String.t() | nil}],
          proposed: boolean(),
          pending: boolean()
        }
end
