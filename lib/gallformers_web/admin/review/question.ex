defmodule GallformersWeb.Admin.Review.Question do
  @moduledoc """
  A queue item as the curator reads it
  (`GallformersWeb.Admin.Review.Questions.present/2`):

    * `section` — the `GallformersWeb.Admin.Review.Section` it is shown in;
      `topic` — the kind of question within it (`:called_new`, `:not_held`,
      `:several_species` in "Which taxon is it"), whose copy it takes.
    * `written` — the Source's own words for what it is about; `context` —
      a short line beside them (the Galls it covers, the name as printed).
    * `question` — the question in plain words; `scope` — a line on what it
      covers or what is known, before what leaving it means (`leave`).
    * `proposal` — the proposed answer, or nil: `%{label, why, firm,
      decision, pending, check}`; `firm` is false for a suggestion to check,
      which bulk accept leaves alone, and `check` (when set) is what the row
      says of it instead ("Best match: confirm it"). With none, `undecided`
      (`%{label, why}`) is what the row shows instead.
    * `choices` — every answer (`GallformersWeb.Admin.Review.Choice`).
    * `holds_approval` and `leave` — whether it holds the Source's approval
      while open, and what leaving it open means.
    * `covers` — how many Galls one answer settles.
    * `candidates` — the entries it may be (`%{id, name}`); `more` — a line
      on the candidates not offered as answers (at most three are), which
      the search lists first (`others`).
    * `tag` — a short label beside the Source's words (a Trait term's
      status: "New term", "Used in more than one sense").
    * `galls` — for a Trait term, each Gall it covers: `%{ref, name,
      quotes, said, default}`, `said` being what the producer and each
      checker said (in plain words), `default` what most of them chose
      for that Gall (a category, or `:text`: no category), or nil when
      they split. `ref` is only for the decision.
    * `sides` — for a dispute, each side's position in a sentence
      (`%{producer: [text], checker: [text]}`): its one-sentence summary,
      else its first sentence; `voices` holds the full arguments.
    * `statement` — for a dispute, the statement without the Gall it is
      about ("Quercus is the Host"), for a question that covers several
      Galls (`GallformersWeb.Admin.Review.Questions.group/2`); `about` — the
      Gall it is about, in the Source's words.
    * `trait`, `definitions` (`%{who, value, definition}`), `voices`
      (`%{checker: [text], producer: [text]}`) and `warning` — evidence for
      the kinds that have it.
    * `technical` — the item's kind, ref, method and reason, for the
      tucked-away details; `ref` and `kind` as stored.
  """

  @enforce_keys [:section, :question, :choices]
  defstruct [
    :section,
    :topic,
    :kind,
    :ref,
    :written,
    :context,
    :question,
    :scope,
    :more,
    :proposal,
    :undecided,
    :trait,
    :tag,
    :voices,
    :warning,
    :sides,
    :statement,
    :about,
    :leave,
    :technical,
    choices: [],
    candidates: [],
    others: [],
    galls: [],
    definitions: [],
    covers: 1,
    holds_approval: true
  ]

  @type proposal :: %{
          label: String.t(),
          why: String.t() | nil,
          firm: boolean(),
          decision: map(),
          pending: boolean(),
          check: String.t() | nil
        }

  @type t :: %__MODULE__{
          section: GallformersWeb.Admin.Review.Section.t(),
          topic: atom(),
          kind: atom(),
          ref: String.t() | nil,
          written: String.t() | nil,
          context: String.t() | nil,
          question: String.t(),
          scope: String.t() | nil,
          more: String.t() | nil,
          proposal: proposal() | nil,
          undecided: %{label: String.t(), why: String.t() | nil} | nil,
          choices: [GallformersWeb.Admin.Review.Choice.t()],
          candidates: [%{id: integer(), name: String.t()}],
          others: [%{id: integer(), name: String.t()}],
          trait: String.t() | nil,
          tag: String.t() | nil,
          galls: [
            %{
              ref: String.t(),
              name: String.t(),
              quotes: [%{text: String.t(), item: String.t() | nil}],
              said: [String.t()],
              default: String.t() | :text | nil
            }
          ],
          definitions: [%{who: String.t() | nil, value: String.t(), definition: String.t() | nil}],
          voices: %{checker: [String.t()], producer: [String.t()]} | nil,
          sides: %{checker: [String.t()], producer: [String.t()]} | nil,
          statement: String.t() | nil,
          about: String.t() | nil,
          warning: String.t() | nil,
          covers: pos_integer(),
          holds_approval: boolean(),
          leave: String.t() | nil,
          technical: String.t()
        }
end
