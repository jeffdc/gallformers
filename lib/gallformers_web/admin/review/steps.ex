defmodule GallformersWeb.Admin.Review.Steps do
  @moduledoc """
  A Source's review in five steps, one page each, in a fixed order (matter
  `d213`, "Navigation within a Source"):

    1. **Names**: which organisms the Source means.
    2. **Galls**: which Gall each description is.
    3. **Disputes**: which disputed statements go in.
    4. **Traits**: what the Source's words mean.
    5. **Hedges**: whether a hedged statement is stated.

  Each step shows the presenter's sections
  (`GallformersWeb.Admin.Review.Questions`) it lists, in its order; the
  steps follow the sections, so a question shows in the step its section
  belongs to. Names has three (Host plants; Which taxon is it; Where the
  Source and the tree differ), Galls two of its own (Galls of named
  species; Undescribed Galls) besides generations outside their group and
  Gall renames: a section shows several kinds of question together (their
  `topic`). Traits shows the disputed Trait terms with the terms; Hedges
  groups the statements set aside by what each is about (names and
  species, the Inducer, Hosts, range, the Gall itself, other). "Which Source this is" (`:source`) belongs to no step: the
  overview shows it as a banner, with any section no step lists.

  `summarize/1` counts, per step, the questions in it (`total`), the open
  ones (`left`), the open ones with a recommended answer (`recommended`) and
  the open ones that hold approval (`holding`), from the page's entries
  (`GallformersWeb.Admin.ReviewLive.Loader.entries/2`).
  """

  @typedoc "One step of a Source's review."
  @type step :: %{
          id: atom(),
          slug: String.t(),
          n: pos_integer(),
          title: String.t(),
          question: String.t(),
          holds_approval: boolean(),
          sections: [atom()]
        }

  @typedoc "What is left in a step."
  @type summary :: %{
          step: step(),
          total: non_neg_integer(),
          left: non_neg_integer(),
          recommended: non_neg_integer(),
          holding: non_neg_integer()
        }

  @steps [
    %{
      id: :names,
      slug: "names",
      n: 1,
      title: "Names",
      question: "Which organisms does the Source mean?",
      holds_approval: true,
      sections: [:hosts, :which_taxon, :differ]
    },
    %{
      id: :galls,
      slug: "galls",
      n: 2,
      title: "Galls",
      question: "Which Gall is each description?",
      holds_approval: true,
      sections: [:named_galls, :undescribed_galls, :generation_outside, :gall_rename]
    },
    %{
      id: :disputes,
      slug: "disputes",
      n: 3,
      title: "Disputes",
      question: "Which disputed statements go in?",
      holds_approval: true,
      sections: [:disputes, :same_date]
    },
    %{
      id: :traits,
      slug: "traits",
      n: 4,
      title: "Traits",
      question: "What do the Source's words mean?",
      holds_approval: false,
      sections: [:trait_terms]
    },
    %{
      id: :hedges,
      slug: "hedges",
      n: 5,
      title: "Hedges",
      question: "Should a hedged statement be stated?",
      holds_approval: false,
      sections: [
        :hedge_names,
        :hedge_inducer,
        :hedge_host,
        :hedge_range,
        :hedge_gall,
        :hedge_other
      ]
    }
  ]

  @by_section for step <- @steps, section <- step.sections, into: %{}, do: {section, step.id}

  @doc "The five steps, in order."
  @spec all() :: [step()]
  def all, do: @steps

  @doc "The step whose slug is `slug` (\"names\"), or nil."
  @spec get(String.t()) :: step() | nil
  def get(slug), do: Enum.find(@steps, &(&1.slug == slug))

  @doc "The id of the step the section `section_id` belongs to, or nil."
  @spec step_of(atom()) :: atom() | nil
  def step_of(section_id), do: Map.get(@by_section, section_id)

  @doc "The step before and after `step`, each nil at the ends."
  @spec neighbours(step()) :: {step() | nil, step() | nil}
  def neighbours(%{n: n}), do: {if(n > 1, do: Enum.at(@steps, n - 2)), Enum.at(@steps, n)}

  @doc "The entries whose section belongs to `step`, in the page's order."
  @spec entries([map()], step()) :: [map()]
  def entries(entries, step), do: Enum.filter(entries, &(section_id(&1) in step.sections))

  @doc "The entries in no step: the Source's own question, and any section no step lists."
  @spec unplaced([map()]) :: [map()]
  def unplaced(entries), do: Enum.filter(entries, &(step_of(section_id(&1)) == nil))

  @doc "What is left in each step, in order."
  @spec summarize([map()]) :: [summary()]
  def summarize(entries) do
    for step <- @steps do
      all = entries(entries, step)
      open = Enum.filter(all, &open?/1)

      %{
        step: step,
        total: length(all),
        left: length(open),
        recommended: Enum.count(open, &recommended?/1),
        holding: Enum.count(open, & &1.holds)
      }
    end
  end

  @doc "The first step with an open question, or nil."
  @spec first_open([summary()]) :: step() | nil
  def first_open(summaries), do: Enum.find_value(summaries, &(&1.left > 0 && &1.step))

  @doc "The steps with an open question that holds approval."
  @spec holding([summary()]) :: [step()]
  def holding(summaries), do: for(s <- summaries, s.holding > 0, do: s.step)

  @doc "Whether `entry` is open with an answer recommended (its proposal, not rejected)."
  @spec recommended?(map()) :: boolean()
  def recommended?(entry) do
    open?(entry) and not entry.rejected and
      match?(%{pending: false}, entry.question.proposal)
  end

  defp open?(entry), do: entry.item.status == :open
  defp section_id(entry), do: entry.question.section.id
end
