defmodule GallformersWeb.Admin.Review.Questions do
  @moduledoc """
  The review queue's items (`Gallformers.Import.QueueItem`) as the curator
  reads them (`6611` Task 5): the section each is shown in, its question in
  plain words and in the Source's own words, the proposed answer, and every
  choice with what it does and the decision it sends. Batch refs (`t24`,
  `g1`, `f5`), method codes and file names stay out of all of that; they go
  only in `technical`, for the tucked-away details.

  The copy follows the approved design (`docs/plans/review-redesign.html`,
  version 3), with the Source's name for "Ashmead" or "Floate".

  ## What the caller passes

  Nothing here reads the database. `present/2` takes, besides the item, a
  context map, every key optional:

    * `:source` — what the Source is called in the copy ("Ashmead"); nil
      reads "the Source".
    * `:names` — the catalog's names by ID, `%{taxa: %{id => name}, galls:
      %{id => name}, sources: %{id => title}}`, for candidates and
      proposals.
    * `:statement` — the item's batch statement
      (`Gallformers.Import.BatchStatement`, or a map with `method`, `flags`
      and `detail`): how a name was suggested and whether the Source calls
      it new decide its section.
    * `:fact` — for a dispute, the disputed statement as the batch states
      it (decoded, `%{"kind" => "trait", "trait" => "form", ...}`).
    * `:written` — the batch's names as written, by ref, so a Fact or act
      reads in the Source's words.
    * `:definitions` — the Trait values' definitions, `%{trait => %{value
      => definition}}`.
    * `:batch_type` — `:taxonomy` or `:gall`: a name held valid holds
      approval only in a gall batch.
    * `:covers` — how many Galls the item decides, where the caller counts
      them (a name's Galls waiting on it); otherwise taken from
      `subject["covers"]`, a dispute's `subject["also"]`, or a pair (2).
    * `:content` — the item's batch content (decoded): what leaving a name
      or Gall out drops, and where a new taxon goes in the tree.
    * `:taxa_info` — the candidate taxa's identity lines by ID
      (`Gallformers.Import.ReviewContext.taxon/1`): each taxon answer shows
      its family, Galls and Hosts, and whether it already holds the
      Source's name (`Gallformers.Import.ReviewContext.holds_name/2`).
    * `:held_genera` — the genera the tree holds, by name in lower case
      (`%{"andricus" => %{id, name}}`): a new species' create choice
      starts with its genus (its name's first word) as the parent picked.
    * `:host_sections` — for a Host dispute whose Host is a genus, or a
      Gall question whose Source Host is one, its sections (`%{id, name,
      common_name}`), listed first in the search for the plant meant.
    * `:host_rank` — for a Host dispute, its Host's rank (nil unknown):
      one above species rank is kept on the plant picked for its
      statements only, not read as it throughout the Source.
    * `:gall_view` — for a Gall question, what the Source says of the Gall
      and what each candidate is, to compare side by side: `%{source,
      galls: %{id => gall}, generations}` (`GallformersWeb.Admin.ReviewLive.Loader`).

  ## Sections

  In the steps' order (`sections/1`, matter `d213`): Host plants; Which
  taxon is it (names called new that Gallformers holds, names Gallformers
  doesn't hold, names held by several species: the question's `topic`);
  Where the Source and the tree differ (names now treated as synonyms,
  taxonomic acts that differ from the tree); Galls of named species (Galls
  whose generation isn't named, Galls that match several entries,
  generation pairs); Undescribed Galls (undescribed Galls, Galls
  Gallformers doesn't hold); generations outside their group; Gall rename
  proposals; disputed statements; same-date conflicts; Trait terms to
  settle (the disputed terms among them, topic `:trait_dispute`); the
  statements set aside as hedged, by what each is about
  (`subject["topic"]`: About names and species, About the Inducer, About
  Hosts, About range, About the Gall itself, Other, which also takes those
  with no topic; topic `:set_aside_statements`); the Source match. A
  question takes its topic's copy and its topic's say on approval.

  A taxon answer shows at most three candidates; the others are listed in
  the search (`others`). A Gall answer compares the candidate with what the
  Source says field by field (`proposal["comparisons"]`), is tagged as the
  best match or with what it conflicts on, and, when the Source disagrees
  with it, asks of each such statement whether to keep it, leave it out
  (`"drop"`), or for a Host read it as another plant (`"host_reading"`).
  A Source Host above species rank (a genus, `source.hosts[].rank`) is the
  Source's name for many Galls: it is not read so, but goes "On another
  plant", the plant picked for this Gall only (`"host_taxon_id"`), the
  genus's sections listed first in the search (`Choice.sections`).

  ## Decisions

  A choice's decision is what `Gallformers.Import.Queue` accepts, plus the
  shapes `6611` Tasks 2–4 add: a Host as a plant with the Source's
  spelling as its synonym (`%{"taxon_id" => id, "add_synonym" => true}`)
  or added from WCVP (`%{"wcvp_id" => id}`), for a statement set aside
  `keep` and `state`, and for a Trait term (`Gallformers.Import.TraitTerms`,
  matter `d213`) `place` (for every Source: a value, or a list of the
  values a term's words name), `categories` (per Gall, `%{gall_ref =>
  category | nil}`), `no_fit` and `keep`; for identical disputes
  (`group/2`) `%{"keep" => true, "except" => ids}` or `%{"skip" => true}`
  (`Gallformers.Import.decide_group/3`), a Host dispute kept with its Host
  read as another plant `%{"keep" => true, "host_reading" => %{"name",
  "taxon_id"}}`, and a new taxon under the parent picked `%{"new" => true,
  "parent_id" => id}`, a new Gall of the generation picked `%{"new" =>
  true, "generation" => value}`. A choice the backend doesn't take
  yet is flagged `pending`, and the page leaves it out.

  A Host the Source names only by a common name (`subject["common_name"]`,
  `d213` Task 6) takes no synonym. An unnamed oak is usually a section's,
  not the genus's, so when the genus the name points to has sections
  (`proposal["genus"]` and `proposal["sections"]`, from the tree) "A
  section of Quercus" comes first, a section picked from the list (`:section`);
  then its plants (Gallformers' plants of that common name, never firmly),
  "Another plant…", and the genus last (the resolver's, else the one every
  suggestion shares, else a search). All send a plain `%{"taxon_id" =>
  id}`, or `%{"wcvp_id" => id}`.

  A Trait term's question (matter `d213`, Traits step) asks what the words
  mean. Its readers are named: the producer, and each checker ("checker
  1", "checker 2"; "the checker" when one placed the terms). What most of
  a Gall's readers chose (more than half; so a silent producer gives way
  to two checkers agreeing) is that Gall's recommended value; the term's
  recommendation is one value (or set) for every Gall, keeping it as text
  when most chose none, or "It depends on the Gall" when the Galls'
  differ, are said to depend on the Gall, or the term has several senses;
  with a Gall split, none. Its options: each value (or set) a reader chose,
  defined, with who chose it (`tally`); another value (searched); more
  than one value (ticked, the readers' first); a value per Gall (the
  recommended ones filled on request); fits none; keep as text. A term
  used in more than one sense offers only the per-Gall choices and keeping
  it as text. Each option says what Decide does (`effect`).

  A dispute shows each side's position in a sentence (`sides`: the
  finding's and its response's `summary`, else each one's first sentence)
  and keeps the full arguments (`voices`); nothing is recommended. A
  dispute about a Host may also be kept with the Host read as another
  plant, picked (`{:reading, name}`: `%{"keep" => true, "host_reading" =>
  %{"name", "taxon_id"}}`), for one Gall or for every Gall of a group. A
  Host above species rank (`context[:host_rank]`: a genus, its name the
  Source's for many Galls) is not read so: the plant picked goes in for
  these Galls only (`as: "host_taxon_id"`: `%{"keep" => true,
  "host_taxon_id" => id}`). When the disputed Host is a genus with
  sections (`context[:host_sections]`), its search lists them first
  (`Choice.sections`). A
  dispute about a Trait Fact (format 3, from before Trait terms) is a
  disputed statement. A dispute about a format 4 Trait term
  (`subject["trait"]` and `subject["term"]`, `Gallformers.Import.Disputes`)
  is asked with the Trait terms, keep or drop, and holds no approval.
  Disputes about the same statement are asked as one (`group/2`).

  A hedge (a statement set aside) names its Galls and the producer's note,
  and recommends leaving it out, or stating it.
  """

  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.ReviewContext
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.Review.Choice
  alias GallformersWeb.Admin.Review.Question
  alias GallformersWeb.Admin.Review.Section

  # The page's sections, in the steps' order.
  @order [
    :hosts,
    :which_taxon,
    :differ,
    :named_galls,
    :undescribed_galls,
    :generation_outside,
    :gall_rename,
    :disputes,
    :same_date,
    :trait_terms,
    :hedge_names,
    :hedge_inducer,
    :hedge_host,
    :hedge_range,
    :hedge_gall,
    :hedge_other,
    :taxonomy_acceptance,
    :split_inducer,
    :source
  ]

  # A hedge's section, by what it is about (`subject["topic"]`, d213 Task
  # 11); one with no topic is under Other.
  @hedge_sections %{
    "names" => :hedge_names,
    "inducer" => :hedge_inducer,
    "host" => :hedge_host,
    "range" => :hedge_range,
    "gall" => :hedge_gall,
    "other" => :hedge_other
  }

  # The kinds of question shown together in one section.
  @group %{
    called_new: :which_taxon,
    not_held: :which_taxon,
    several_species: :which_taxon,
    synonyms: :differ,
    acts: :differ,
    gall_generation: :named_galls,
    gall_match: :named_galls,
    generation_pairs: :named_galls,
    undescribed: :undescribed_galls,
    new_galls: :undescribed_galls,
    trait_dispute: :trait_terms,
    set_aside_statements: :hedge_other
  }

  # How many candidates are offered as answers; the rest are searched.
  @shown 3

  # A Host at these ranks is one plant: a Host dispute may read its name as
  # another throughout the Source. Above them it is kept on a plant picked.
  @species_level Rank.species_and_below()

  # Resolver methods for a name the tree holds in another spelling or genus.
  @suggestion_methods ~w(cynips_name spelling_variant epithet_in_family)

  @blocks "If you leave it: the Source can't be approved."
  @nothing_waits "If you leave it: nothing waits; the Facts are recorded either way."
  @acknowledge "Doesn't hold approval: acknowledge when ready"
  @hedges_hold "Doesn't hold approval: left alone, they stay out"
  @hedges_leave "If you leave it: it stays out; approval doesn't wait on it."

  @typedoc "What a curator picked for a choice with a picker (`picked_decision/2`)."
  @type picked ::
          {:taxon, integer()}
          | {:gall, integer()}
          | {:wcvp, String.t()}
          | {:trait_value, String.t()}
          | {:trait_values, [String.t()]}
          | {:place, String.t()}
          | {:host, integer()}
          | {:trait, String.t(), String.t()}
          | {:galls, %{String.t() => String.t() | nil}}
          | {:except, [integer()]}
          | :split
          | :unplaced
          | {:synonym_of, integer()}
          | {:generation, String.t()}
          | {:statements, %{String.t() => :keep | :leave | {:reading, integer()}}}
          | {:reason, String.t()}

  # -- sections ------------------------------------------------------------------

  @doc "Every section, in the steps' order, with `source` (its name, or nil) in the copy."
  @spec sections(String.t() | nil) :: [Section.t()]
  def sections(source \\ nil), do: Enum.map(@order, &section(&1, source))

  @doc """
  The section `id` (or the copy of a kind of question shown in one, a
  topic), with `source` (its name, or nil) in the copy.
  """
  @spec section(atom(), String.t() | nil) :: Section.t()
  def section(id, source) when id in @order or is_map_key(@group, id) do
    who = who(source)
    {title, explanation, holds_approval, holds, leave} = copy(id, who)

    %Section{
      id: id,
      title: title,
      explanation: explanation,
      holds_approval: holds_approval,
      holds: holds,
      leave: leave
    }
  end

  defp copy(:hosts, who),
    do:
      {"Host plants",
       "Which plant does #{who} mean? Accepting adds #{poss(who)} spelling as a synonym, so the " <>
         "next Source that uses it resolves on its own. Until each is settled, the Galls' Host " <>
         "statements wait.", true, "Holds the Galls' statements until each is settled",
       "If you leave it: every Gall statement in this Source waits, because a Host statement " <>
         "can't be applied without its plant."}

  defp copy(:which_taxon, who),
    do:
      {"Which taxon is it",
       "Names Gallformers doesn't hold as #{who} writes them: species #{who} describes as new " <>
         "that Gallformers holds under a later name, names in another spelling or genus, and " <>
         "names Gallformers holds for more than one species.", true, "Holds approval", @blocks}

  defp copy(:differ, who),
    do:
      {"Where #{who} and the tree differ",
       "#{cap(who)} treats these names as valid species; Gallformers' tree holds them as " <>
         "synonyms. Following Gallformers puts #{poss(who)} statements on the current species " <>
         "and keeps #{poss(who)} name as the original combination. Taxonomic acts that differ " <>
         "from the tree are kept as history.", true,
       "Its synonym questions hold approval; acts that differ don't", @blocks}

  defp copy(:named_galls, who),
    do:
      {"Galls of named species",
       "#{cap(who)} names the Inducer of these Galls. Gallformers holds one or more Galls for " <>
         "each species: is it one of them, or another generation's Gall?", true,
       "Holds these Galls' statements", @blocks}

  defp copy(:undescribed_galls, who),
    do:
      {"Undescribed Galls",
       "#{cap(who)} describes these without naming their Inducer, or Gallformers holds no Gall " <>
         "that matches. Gallformers may hold them as undescribed Galls. A match is never firm: " <>
         "confirm it, or create a new Gall.", true, "Holds these Galls' statements", @blocks}

  defp copy(:called_new, who),
    do:
      {"Names #{who} calls new that Gallformers already holds",
       "#{cap(who)} describes these as new. Gallformers holds the same species under a later " <>
         "genus or another spelling. Accepting uses that taxon and creates no duplicate.", true,
       "Holds approval: a wrong choice creates a duplicate taxon", @blocks}

  defp copy(:not_held, who),
    do:
      {"Names Gallformers doesn't hold",
       "Gallformers has no taxon by these names. Where it holds one in another spelling or " <>
         "genus, that is proposed; otherwise choose the taxon #{who} means, or create it.", true,
       "Holds approval", @blocks}

  defp copy(:several_species, who),
    do:
      {"Names Gallformers holds under more than one species",
       "Gallformers holds this name for more than one species, as happens with misapplied or " <>
         "invalid names. Compare what each species is with what #{who} describes. (A name held " <>
         "twice by the same species is no question: it resolves to that species.)", true,
       "Holds approval", @blocks}

  defp copy(:synonyms, who),
    do:
      {"#{cap(poss(who))} names that Gallformers now treats as synonyms",
       "#{cap(who)} treats these as valid species; later work sank them into other species. " <>
         "Following Gallformers puts #{poss(who)} statements on the current species. " <>
         "#{cap(poss(who))} name is kept as the original combination.", true,
       "Holds the statements about these Galls", @blocks}

  defp copy(:gall_generation, who),
    do:
      {"Galls whose generation #{who} doesn't name",
       "These Inducers alternate between two generations, each with its own Gall. #{cap(who)} " <>
         "describes one Gall without saying which generation; the Galls Gallformers holds for " <>
         "the species are shown.", true, "Holds these Galls' statements", @blocks}

  defp copy(:gall_match, who),
    do:
      {"Galls that match more than one Gall entry",
       "Gallformers holds several Galls each of these could be. Pick the one #{who} describes.",
       true, "Holds these Galls' statements", @blocks}

  defp copy(:generation_pairs, who),
    do:
      {"Generation pairs",
       "#{cap(who)} describes two Galls of different generations, and Gallformers holds one " <>
         "Gall for them with no generation. Pick which one it is; the other becomes a new Gall.",
       true, "Holds these Galls' statements", @blocks}

  defp copy(:undescribed, who),
    do:
      {"Undescribed Galls",
       "Gallformers may already hold the Gall #{who} describes as undescribed, with its Inducer " <>
         "unknown or named only to genus. Pick the entry, or create a new Gall.", true,
       "Holds these Galls' statements", @blocks}

  defp copy(:new_galls, _who),
    do:
      {"Galls Gallformers doesn't hold",
       "No Gall Gallformers holds matches these. Create each one, or pick the entry it is.", true,
       "Holds these Galls' statements", @blocks}

  defp copy(:disputes, _who),
    do:
      {"Statements the producer and a checker disagree on",
       "A checker questioned these; the producer kept them. You decide whether each goes in. " <>
         "Disputes about the same statement are one question.", true, "Holds approval", @blocks}

  defp copy(:trait_terms, who),
    do:
      {"Trait terms to settle",
       "Words #{who} uses for a Trait (a color, a form, a texture…) that Gallformers doesn't " <>
         "know yet. Until you settle a term, the Galls that use it show the Source's own words " <>
         "for that Trait and have no Gallformers value for it, so the ID tool can't find them " <>
         "by it. You can approve the Source with terms still open. They stay on this page, and " <>
         "the Galls get their values whenever you settle them. Each term was read three times: " <>
         "by the producer, the AI that read the Source and wrote its Facts, and by checker 1 " <>
         "and checker 2, two other AI models that each placed the term on their own, without " <>
         "seeing the producer's answer. A term a checker disputed is here too: keep it or drop " <>
         "it.", false, "Doesn't hold approval: left alone, each stays as text",
       "If you leave it: the Galls show the term without a category, and the ID tool doesn't " <>
         "use it; approval doesn't wait on it."}

  defp copy(:trait_dispute, _who),
    do:
      {"Disputed Trait terms",
       "A checker questioned a term the producer kept. You decide whether it goes in.", false,
       "Doesn't hold approval",
       "If you leave it: its Fact waits, unwritten; approval doesn't wait on it."}

  defp copy(:set_aside_statements, who),
    do:
      {"Statements set aside as hedged",
       "#{cap(who)} hedges these, so they are left out unless you state them.", false,
       @hedges_hold, @hedges_leave}

  defp copy(:hedge_names, _who),
    do:
      {"About names and species", "Hedged synonymies, splits, new genera and species groups.",
       false, @hedges_hold, @hedges_leave}

  defp copy(:hedge_inducer, _who),
    do:
      {"About the Inducer", "Who induces the Gall, and other organisms associated with it.",
       false, @hedges_hold, @hedges_leave}

  defp copy(:hedge_host, _who),
    do: {"About Hosts", "Which plants the Gall is on.", false, @hedges_hold, @hedges_leave}

  defp copy(:hedge_range, _who),
    do: {"About range", "Where the Gall occurs.", false, @hedges_hold, @hedges_leave}

  defp copy(:hedge_gall, _who),
    do:
      {"About the Gall itself", "Where on the plant it forms, its shape and its form.", false,
       @hedges_hold, @hedges_leave}

  defp copy(:hedge_other, _who),
    do:
      {"Other", "Hedges about anything else, and those the producer gave no topic.", false,
       @hedges_hold, @hedges_leave}

  defp copy(:acts, who),
    do:
      {"Taxonomic acts that differ from the tree",
       "#{cap(who)} places or names these taxa differently from Gallformers' tree. They are " <>
         "kept as history; the tree doesn't change.", false, @acknowledge,
       "If you leave it: nothing waits; the acts are kept as history either way."}

  defp copy(:same_date, _who),
    do:
      {"Sources of the same date that disagree",
       "Another Source of the same date says the opposite. The Fact keeps its standing until a " <>
         "dated Gallformers statement settles it.", false, @acknowledge, @nothing_waits}

  defp copy(:generation_outside, who),
    do:
      {"Generations outside their group",
       "#{cap(who)} gives these Galls a generation that isn't among those that apply to the " <>
         "Inducer. Check the generation or the Inducer later.", false, @acknowledge,
       @nothing_waits}

  defp copy(:source, _who),
    do:
      {"Which Source this is",
       "Gallformers can't tell whether it already holds this Source. Pick it, or add it as a " <>
         "new Source.", true, "Holds approval", @blocks}

  defp copy(:taxonomy_acceptance, _who),
    do:
      {"Taxonomic statements to accept or decline",
       "A newer paper places, names, synonymizes or splits these taxa differently from the " <>
         "tree. Its statement counts only once you accept it: the tree then follows it, and " <>
         "older papers' questions about the same taxon close as history. Declining keeps the " <>
         "tree on the paper it follows, with your reason shown beside the declined one.", false,
       "Doesn't hold approval: the tree waits until you decide",
       "If you leave it: the tree keeps following the paper it follows now."}

  defp copy(:split_inducer, who),
    do:
      {"Galls whose Inducer was split",
       "#{cap(who)} splits the taxon these Galls are on, and #{poss(who)} own statements don't " <>
         "say which daughter induces them. Choose the taxon that induces each Gall now, or " <>
         "keep it on the old name in its broad sense until a later Source settles it. Only " <>
         "the Inducer changes: the Gall's other Facts and their Sources stay, and older " <>
         "papers keep the name they wrote.", false,
       "Doesn't hold approval: the Gall stays on the old name until you decide",
       "If you leave it: the Gall stays on the old name."}

  defp copy(:gall_rename, _who),
    do:
      {"Gall names a change in the tree would change",
       "A change in the tree gives these Galls new names. Each Gall keeps its name until you " <>
         "decide.", false, "Doesn't hold approval: the Gall keeps its name until decided",
       "If you leave it: the Gall keeps its name."}

  # -- one item --------------------------------------------------------------------

  @doc """
  `item` as the curator reads it: a `GallformersWeb.Admin.Review.Question`.
  `context` is described in the moduledoc.
  """
  @spec present(QueueItem.t(), map()) :: Question.t()
  def present(%QueueItem{} = item, context \\ %{}) do
    item = %{item | subject: item.subject || %{}, proposal: item.proposal || %{}}
    ctx = context |> context() |> Map.update!(:fact, &(&1 || dispute_fact(item)))
    id = section_id(item, ctx)
    own = section(id, ctx.source)

    fields =
      %{
        section: section(page_section(id, item), ctx.source),
        topic: id,
        kind: item.kind,
        ref: item.statement_ref,
        holds_approval: own.holds_approval,
        leave: own.leave,
        covers: covers(id, item, ctx),
        technical: technical(item, ctx)
      }
      |> Map.merge(build(id, item, ctx))

    fields =
      case fields do
        %{proposal: nil} -> fields
        %{proposal: proposal, choices: choices} -> %{fields | choices: mark(choices, proposal)}
      end

    struct!(Question, fields)
  end

  @doc """
  The decision for `choice` (one with a picker) once the curator has
  picked: a plant (`{:taxon, id}`: the Source's spelling becomes its
  synonym, unless the choice is `as: "common_name"`, a Host the Source
  names only by a common name; `{:wcvp, id}`: added from WCVP), a taxon
  (for a new taxon its parent, or `:unplaced`), a Gall, a Trait
  value or several (`{:trait_values, values}`), a place, or for a statement set aside what to state: a Trait value
  (`{:trait, trait, value}`), a Host (`{:host, taxon_id}`) or a place
  (`{:place, code}`), as `Gallformers.Import.SetAside` takes them.
  """
  @spec picked_decision(Choice.t(), picked()) :: map()
  def picked_decision(%Choice{picker: :plant, as: "common_name"}, {:taxon, id}),
    do: %{"taxon_id" => id}

  def picked_decision(%Choice{picker: :plant}, {:taxon, id}),
    do: %{"taxon_id" => id, "add_synonym" => true}

  def picked_decision(%Choice{picker: :plant}, {:wcvp, id}), do: %{"wcvp_id" => id}
  def picked_decision(%Choice{picker: :taxon}, {:taxon, id}), do: %{"taxon_id" => id}
  def picked_decision(%Choice{picker: :gall}, {:gall, id}), do: %{"gall_id" => id}

  def picked_decision(%Choice{picker: {:trait_value, _}, as: key}, {:trait_value, value}),
    do: %{key => value}

  def picked_decision(%Choice{picker: {:trait_values, _}, as: key}, {:trait_values, values})
      when is_list(values),
      do: %{key => values}

  def picked_decision(%Choice{picker: picker}, {:place, code})
      when picker in [:place, :statement],
      do: %{"state" => %{"kind" => "occurrence", "place" => code}}

  def picked_decision(%Choice{picker: :statement}, {:host, id}),
    do: %{"state" => %{"kind" => "host_of", "taxon_id" => id}}

  def picked_decision(%Choice{picker: :statement}, {:trait, trait, value}),
    do: %{"state" => %{"kind" => "trait", "trait" => trait, "value" => value}}

  # A section of the genus a common-name Host points to.
  def picked_decision(%Choice{picker: :section}, {:taxon, id}) when is_integer(id),
    do: %{"taxon_id" => id}

  # A Host dispute kept on the plant picked, for its statements only (a
  # Host above species rank), or its Host read as the plant picked.
  def picked_decision(%Choice{picker: {:reading, _name}, as: "host_taxon_id", base: base}, {
        :taxon,
        id
      })
      when is_integer(id),
      do: Map.put(base, "host_taxon_id", id)

  def picked_decision(%Choice{picker: {:reading, name}, base: base}, {:taxon, id})
      when is_integer(id),
      do: Map.put(base, "host_reading", %{"name" => name, "taxon_id" => id})

  # Identical disputes kept for every Gall but those unticked (`group/2`).
  def picked_decision(%Choice{picker: :keep_galls}, {:except, ids}) when is_list(ids),
    do: %{"keep" => true, "except" => ids}

  def picked_decision(%Choice{picker: :galls}, {:galls, by_gall}) when is_map(by_gall),
    do: %{"categories" => by_gall}

  # The Source is right about a synonym: the name is a species of its own
  # again, or another species' synonym (`Gallformers.Import.SynonymDecisions`).
  def picked_decision(%Choice{picker: :reason}, {:reason, reason}) when is_binary(reason),
    do: %{"decline" => true, "reason" => String.trim(reason)}

  def picked_decision(%Choice{picker: :tree}, :split), do: %{"split" => true}

  def picked_decision(%Choice{picker: :tree}, {:synonym_of, id}) when is_integer(id),
    do: %{"synonym_of" => id}

  # A new taxon under the parent picked, or (none picked) unplaced.
  def picked_decision(%Choice{picker: {:parent, _rank}}, {:taxon, id}) when is_integer(id),
    do: %{"new" => true, "parent_id" => id}

  def picked_decision(%Choice{picker: {:parent, _rank}}, :unplaced), do: %{"new" => true}

  # A new Gall of the generation picked (`Gallformers.Import.GallDecisions`).
  def picked_decision(%Choice{picker: :generation}, {:generation, value}) when is_binary(value),
    do: %{"new" => true, "generation" => value}

  # A Gall the Source disagrees with: the statements left out are dropped,
  # and a Host read as another plant is read so, or (above species rank)
  # goes on the plant picked for this Gall only (`Gallformers.Import.GallDecisions`).
  def picked_decision(%Choice{picker: :statements, base: base, statements: statements}, {
        :statements,
        settled
      })
      when is_map(settled) do
    drop = for s <- statements, settled[s.key] == :leave, ref <- s.refs, do: ref

    host =
      Enum.find_value(statements, fn s ->
        case settled[s.key] do
          {:reading, id} when is_binary(s.reading) -> {Map.get(s, :as), s.reading, id}
          _ -> nil
        end
      end)

    base
    |> then(&if(drop == [], do: &1, else: Map.put(&1, "drop", drop)))
    |> then(fn decision ->
      case host do
        {"host_taxon_id", _name, id} -> Map.put(decision, "host_taxon_id", id)
        {_as, name, id} -> Map.put(decision, "host_reading", %{"name" => name, "taxon_id" => id})
        nil -> decision
      end
    end)
  end

  # The page section a kind of question is shown in: a hedge's by its topic.
  defp page_section(:set_aside_statements, item),
    do: Map.get(@hedge_sections, item.subject["topic"], :hedge_other)

  defp page_section(id, _item), do: Map.get(@group, id, id)

  # A dispute about a Trait Fact carries the Fact (`Gallformers.Import.Disputes`).
  defp dispute_fact(%QueueItem{kind: :dispute, subject: %{"fact" => fact}}) when is_map(fact),
    do: fact

  defp dispute_fact(_item), do: nil

  defp context(context) do
    content = context[:content] || %{}

    %{
      source: context[:source],
      who: who(context[:source]),
      names: Map.merge(%{taxa: %{}, galls: %{}, sources: %{}}, context[:names] || %{}),
      statement: context[:statement],
      fact: context[:fact],
      written: Map.merge(written_in(content), context[:written] || %{}),
      definitions: context[:definitions] || %{},
      batch_type: context[:batch_type],
      covers: context[:covers],
      content: content,
      taxa_info: context[:taxa_info] || %{},
      held_genera: context[:held_genera] || %{},
      host_sections: context[:host_sections] || [],
      host_rank: context[:host_rank],
      gall_view: context[:gall_view]
    }
  end

  # The batch's names as written, by ref.
  defp written_in(content) do
    for key <- ["taxa", "galls"],
        entry <- List.wrap(content[key]),
        is_map(entry) and is_binary(entry["ref"]) and is_binary(entry["name_as_written"]),
        into: %{},
        do: {entry["ref"], entry["name_as_written"]}
  end

  # -- which section -------------------------------------------------------------

  defp section_id(%QueueItem{kind: :gall_rename}, _ctx), do: :gall_rename
  defp section_id(%QueueItem{kind: :taxonomy_acceptance}, _ctx), do: :taxonomy_acceptance
  defp section_id(%QueueItem{kind: :split_inducer}, _ctx), do: :split_inducer

  defp section_id(%QueueItem{statement_ref: ref}, _ctx) when ref in ["source", "retracts"],
    do: :source

  defp section_id(%QueueItem{kind: :unresolved_host}, _ctx), do: :hosts

  defp section_id(%QueueItem{kind: kind}, _ctx) when kind in [:trait_term, :set_aside_term],
    do: :trait_terms

  defp section_id(%QueueItem{kind: :set_aside_statement}, _ctx), do: :set_aside_statements
  defp section_id(%QueueItem{kind: :same_date_conflict}, _ctx), do: :same_date
  defp section_id(%QueueItem{kind: :generation_outside_group}, _ctx), do: :generation_outside

  # A dispute about a Trait term is settled with the Trait terms, holding
  # no approval (`Gallformers.Import.Disputes`).
  defp section_id(%QueueItem{kind: :dispute, subject: %{"trait" => t, "term" => term}}, _ctx)
       when is_binary(t) and is_binary(term),
       do: :trait_dispute

  defp section_id(%QueueItem{kind: :dispute}, _ctx), do: :disputes

  defp section_id(%QueueItem{kind: :taxonomy_disagreement, statement_ref: "t" <> _}, _ctx),
    do: :synonyms

  defp section_id(%QueueItem{kind: :taxonomy_disagreement}, _ctx), do: :acts
  defp section_id(%QueueItem{kind: :undescribed_gall}, _ctx), do: :undescribed

  defp section_id(%QueueItem{kind: :unresolved_name, statement_ref: "g" <> _}, _ctx),
    do: :new_galls

  defp section_id(%QueueItem{kind: :unresolved_name}, _ctx), do: :not_held

  defp section_id(%QueueItem{kind: :ambiguous_match, statement_ref: "g" <> _} = item, ctx) do
    cond do
      is_map(item.proposal["pair"]) -> :generation_pairs
      method(ctx) in ["undescribed", "emerged_from"] -> :undescribed
      item.subject["generation"] -> :gall_match
      true -> :gall_generation
    end
  end

  defp section_id(%QueueItem{kind: :ambiguous_match} = item, ctx) do
    cond do
      item.subject["host"] == true -> :hosts
      method(ctx) in @suggestion_methods and new_status(ctx) -> :called_new
      method(ctx) in @suggestion_methods -> :not_held
      length(candidate_ids(item)) > 1 -> :several_species
      true -> :not_held
    end
  end

  defp method(%{statement: %{method: method}}), do: method
  defp method(_ctx), do: nil

  defp new_status(%{statement: %{detail: %{"new_status" => status}}}) when is_binary(status),
    do: status

  defp new_status(_ctx), do: nil

  # -- the questions, by section -------------------------------------------------

  defp build(:hosts, item, ctx) do
    written = written_name(item)
    common? = common_name?(item)
    targets = item |> host_targets(written, ctx) |> not_the_genus(item, common?)
    proposal = host_proposal(item, targets, common?)
    suffix = covers_suffix(covers(:hosts, item, ctx), :host)

    choices =
      targets
      |> Enum.with_index()
      |> Enum.map(fn {t, i} ->
        lead = if i > 0 and t.why, do: cap(t.why) <> ". ", else: ""

        %Choice{
          label: t.choice,
          hint: lead <> t.does <> suffix <> ".",
          decision: t.decision,
          pending: t.pending,
          identity: t.identity
        }
      end)

    %{
      written: written,
      context: printed_as(item),
      question: "Which plant does #{ctx.who} mean by “#{written}”?",
      proposal: proposal,
      undecided: undecided(item, ctx, :taxa),
      candidates: candidates(item, ctx, :taxa),
      choices:
        section_choices(item, ctx, common?) ++
          choices ++
          [another_plant(written, common?)] ++
          genus_choices(item, ctx, common?) ++
          [
            %Choice{
              label: "Leave this Host out",
              hint: drops_text(item.statement_ref, ctx) <> " The Galls' other statements go in.",
              decision: %{"skip" => true}
            }
          ]
    }
  end

  defp build(:called_new, item, ctx) do
    written = written_name(item)
    rank = rank_noun(item)
    proposal = taxon_proposal(item, ctx, method_why(method(ctx)))

    question =
      if proposal,
        do:
          "Is #{poss(ctx.who)} new #{rank} “#{written}” the one Gallformers holds as " <>
            "#{proposal.label}?",
        else: "Is #{poss(ctx.who)} new #{rank} “#{written}” one Gallformers already holds?"

    use_hint =
      "No new taxon is created; #{poss(ctx.who)} name is kept as the original combination."

    %{
      written: written,
      context: printed_as(item),
      question: question,
      proposal: proposal,
      undecided: undecided(item, ctx, :taxa),
      choices:
        taxon_choices(item, ctx, &"Use #{&1}", fn _ -> use_hint end) ++
          [
            create_taxon("It really is new: create #{title(written)}", rank, item, ctx),
            another_taxon(),
            leave_name(item, ctx)
          ]
    }
    |> Map.merge(shown(item, ctx))
  end

  defp build(:not_held, item, ctx) do
    written = written_name(item)

    held =
      if candidate_ids(item) == [],
        do: " Gallformers holds none by that name.",
        else: " Gallformers holds it only in another spelling or genus."

    %{
      written: written,
      context: printed_as(item),
      question: "Which taxon does #{ctx.who} mean by “#{written}”?" <> held,
      proposal: taxon_proposal(item, ctx, method_why(method(ctx))),
      undecided: undecided(item, ctx, :taxa),
      choices:
        taxon_choices(item, ctx, &"Use #{&1}", fn _ ->
          "#{cap(poss(ctx.who))} statements about it go on this taxon."
        end) ++
          [
            another_taxon(),
            create_taxon("It's new: create #{title(written)}", rank_noun(item), item, ctx),
            leave_name(item, ctx)
          ]
    }
    |> Map.merge(shown(item, ctx))
  end

  defp build(:several_species, item, ctx) do
    written = written_name(item)
    rank = rank_noun(item)

    why =
      "the only one that holds it as its accepted name; the others hold it as a synonym"

    hint =
      "Records that #{poss(ctx.who)} “#{title(written)}” means this #{rank}, so the name is no " <>
        "longer ambiguous for this Source."

    %{
      written: written,
      context: printed_as(item),
      question: "Which #{rank} is #{poss(ctx.who)} “#{written}”?",
      scope:
        "Gallformers holds this name for #{length(candidate_ids(item))} species, as happens " <>
          "with misapplied or reassigned names.",
      proposal: taxon_proposal(item, ctx, why),
      undecided: undecided(item, ctx, :taxa),
      choices:
        taxon_choices(item, ctx, &"It's #{&1}", fn _ -> hint end) ++
          [
            another_taxon(),
            create_taxon("It really is new: create #{title(written)}", rank, item, ctx),
            leave_name(item, ctx)
          ]
    }
    |> Map.merge(shown(item, ctx))
  end

  defp build(:synonyms, item, ctx) do
    written = written_name(item)
    {target, proposal, follow} = follow_gallformers(item, ctx)
    {note, taxonomy_batch} = taxonomy_note(ctx)

    %{
      written: written,
      context: printed_as(item),
      question:
        "#{cap(ctx.who)} treats “#{written}” as a valid #{rank_noun(item)}. Gallformers holds " <>
          "it as a synonym of #{target || "another species"}.",
      # The tree's synonyms record no Source (`taxon_names`, from the old data).
      scope:
        "No Source is recorded for Gallformers' synonymy: it came over with the old " <>
          "Gallformers data.",
      proposal: proposal,
      undecided: undecided(item, ctx, :taxa),
      candidates: candidates(item, ctx, :taxa),
      choices:
        follow ++
          [another_taxon(), change_tree(item, target, ctx)] ++ note ++ [leave_name(item, ctx)]
    }
    |> Map.merge(taxonomy_batch)
  end

  defp build(:gall_generation, item, ctx) do
    written = written_name(item)
    n = length(candidate_ids(item))

    %{
      written: written,
      context: gall_context(item, ctx),
      question: "Which Gall is #{poss(ctx.who)} “#{written}”?",
      scope:
        "#{cap(ctx.who)} doesn't name its generation. Gallformers holds #{n} " <>
          "#{plural(n, "Gall", "Galls")} for the species.",
      proposal: gall_proposal(item, ctx, firm_gall_why(item)),
      undecided: gall_undecided(item, ctx),
      choices:
        gall_choices(item, ctx) ++
          [another_generation(item, ctx), another_gall(item, ctx), leave_gall(item, ctx)]
    }
    |> Map.merge(shown_galls(item, ctx))
  end

  defp build(:gall_match, item, ctx) do
    written = written_name(item)
    n = length(candidate_ids(item))

    %{
      written: written,
      context: gall_context(item, ctx),
      question: "Which Gall is #{poss(ctx.who)} “#{written}”?",
      scope: "Gallformers holds #{n} #{plural(n, "Gall", "Galls")} it could be.",
      proposal: gall_proposal(item, ctx, firm_gall_why(item)),
      undecided: gall_undecided(item, ctx),
      choices:
        gall_choices(item, ctx) ++
          [create_gall(ctx), another_gall(item, ctx), leave_gall(item, ctx)]
    }
    |> Map.merge(shown_galls(item, ctx))
  end

  defp build(:generation_pairs, item, ctx) do
    pair = item.proposal["pair"]
    entry_id = List.first(candidate_ids(item))
    entry = name(ctx, :galls, entry_id)
    this = "“#{written_name(item)}”"
    mate = "“#{pair["name_as_written"]}”"
    this_gen = generation_label(this, item.subject["generation"])
    mate_gen = generation_label(mate, pair["generation"])

    %{
      written: written_name(item),
      context: "and #{mate}, of another generation",
      question:
        "Which of #{poss(ctx.who)} Galls is #{entry}: #{this_gen} or #{mate_gen}? The other " <>
          "becomes a new Gall.",
      proposal: nil,
      undecided: %{label: "No proposal", why: "One of them is #{entry}; the other is new"},
      candidates: candidates(item, ctx, :galls),
      choices: [
        %Choice{
          label: "It's #{this_gen}",
          hint: "Its statements go on #{entry}; #{mate} becomes a new Gall.",
          decision: %{"gall_id" => entry_id}
        },
        %Choice{
          label: "It's #{mate_gen}",
          hint: "Its statements go on #{entry}; #{this} becomes a new Gall.",
          decision: %{"new" => true}
        },
        %Choice{
          label: "Another Gall for #{this}…",
          hint: "Search Galls by name, Inducer or Host. #{mate} is then matched on its own.",
          picker: :gall
        },
        %Choice{
          label: "Leave #{this} out of the import",
          hint: "Its statements are dropped; #{mate} is matched on its own.",
          decision: %{"skip" => true}
        }
      ]
    }
  end

  defp build(:undescribed, item, ctx) do
    written = written_name(item)

    why =
      if method(ctx) == "emerged_from",
        do: "a Gall whose Inducer #{ctx.who} says emerged from it",
        else: "the undescribed Gall that best matches #{poss(ctx.who)} description"

    n = length(candidate_ids(item))

    %{
      written: written,
      context: gall_context(item, ctx),
      question: "Is #{poss(ctx.who)} “#{written}” a Gall Gallformers holds?",
      scope: "Gallformers holds #{n} undescribed #{plural(n, "Gall", "Galls")} that could be it.",
      proposal: gall_proposal(item, ctx, why),
      undecided: gall_undecided(item, ctx),
      choices:
        gall_choices(item, ctx) ++
          [create_gall(ctx), another_gall(item, ctx), leave_gall(item, ctx)]
    }
    |> Map.merge(shown_galls(item, ctx))
  end

  defp build(:new_galls, item, ctx) do
    written = written_name(item)

    proposal =
      if item.proposal["proposed"] == "new",
        do:
          proposal(
            "Create it as a new Gall",
            "no Gall Gallformers holds matches it",
            %{"new" => true}
          ),
        else: gall_proposal(item, ctx, nil)

    %{
      written: written,
      context: gall_context(item, ctx),
      question: "Gallformers holds no Gall that matches “#{written}”. Create it?",
      proposal: proposal,
      undecided: gall_undecided(item, ctx),
      choices:
        gall_choices(item, ctx) ++
          [
            %Choice{
              label: "Create it as a new Gall",
              hint: "Adds a new Gall for #{poss(ctx.who)} description.",
              decision: %{"new" => true}
            },
            another_gall(item, ctx),
            leave_gall(item, ctx)
          ]
    }
    |> Map.merge(shown_galls(item, ctx))
  end

  defp build(:disputes, item, ctx) do
    statement = describe_statement(item, ctx)

    %{
      written: statement,
      question:
        if(statement,
          do: "Should this statement go in: #{statement}?",
          else: "Should this statement go in?"
        ),
      proposal: nil,
      undecided: disputed(),
      sides: sides(item),
      voices: voices(item),
      statement: group_statement(ctx.fact, ctx),
      about: disputed_gall(ctx.fact, ctx),
      choices:
        [
          %Choice{
            label: "Keep it",
            hint: "It goes in as the producer wrote it, credited to #{ctx.who}.",
            decision: %{"keep" => true}
          },
          read_host(ctx.fact, ctx.who, ctx),
          %Choice{
            label: "Drop it",
            hint: "It is left out; #{poss(ctx.who)} words stay in the Source's text.",
            decision: %{"skip" => true}
          }
        ]
        |> Enum.filter(& &1)
    }
  end

  # A dispute about a Trait term (`Gallformers.Import.Disputes`): whether
  # the term goes in, shown with the Trait terms.
  defp build(:trait_dispute, item, ctx) do
    term = item.subject["term"]
    trait = item.subject["trait"]
    tn = trait_name(trait)
    gall = disputed_gall(ctx.fact, ctx)

    %{
      written: term,
      trait: trait,
      tag: "Disputed",
      context: gall,
      question: "Should “#{term}” go in as #{if gall, do: poss(gall), else: "the Gall's"} #{tn}?",
      proposal: nil,
      undecided: disputed(),
      sides: sides(item),
      voices: voices(item),
      statement: "“#{term}” (#{tn})",
      about: gall,
      choices: [
        %Choice{
          label: "Keep it",
          hint:
            "It goes in as the producer wrote it: the Gall gets the #{tn} value “#{term}” is " <>
              "placed under.",
          decision: %{"keep" => true}
        },
        %Choice{
          label: "Drop it",
          hint: "The Gall keeps “#{term}” as text, with no #{tn} value.",
          decision: %{"skip" => true}
        }
      ]
    }
  end

  # A question about a Trait term (`Gallformers.Import.TraitTerms`, matter
  # d213's Traits step): what the words mean.
  defp build(:trait_terms, %QueueItem{kind: :trait_term} = item, ctx) do
    term = item.subject["term"]
    trait = item.subject["trait"]
    tn = trait_name(trait)
    ambiguous? = item.subject["status"] == "ambiguous"
    reading = term_reading(item, ctx)
    galls = term_galls(item, reading)
    rec = recommendation(item, reading, galls)
    n = max(length(galls), 1)

    %{
      written: term,
      context: covered_names(item),
      trait: trait,
      tag: if(ambiguous?, do: "Used in more than one sense", else: "New term"),
      question:
        if(ambiguous?,
          do: "What #{tn} value does “#{term}” mean, Gall by Gall?",
          else: "What #{tn} value is “#{term}”?"
        ),
      scope:
        if(ambiguous?,
          do: "“#{term}” is used in more than one sense, so it is never placed for every Source.",
          else:
            "You're deciding what these words mean. #{here_use(n)} get the value now, and " <>
              "any Source that writes “#{term}” later gets it automatically. Galls described " <>
              "in other words don't change."
        ),
      leave: nil,
      proposal: term_proposal(rec, item, reading, galls),
      undecided: %{label: "No recommendation", why: "The readers split"},
      galls: galls,
      definitions: term_definitions(item, reading),
      choices: term_choices(item, ctx, reading, galls, rec)
    }
  end

  # A Trait term set aside before terms were settled this way: there is
  # nothing left to decide.
  defp build(:trait_terms, item, ctx) do
    term = item.subject["term"]
    tn = trait_name(item.subject["slot"])

    %{
      written: term,
      context: covered_names(item),
      trait: item.subject["slot"],
      question:
        "“#{term}” (#{tn}) was set aside before Trait terms were settled on this page; it " <>
          "stays as #{poss(ctx.who)} words on the Gall.",
      proposal: nil,
      undecided: acknowledged(),
      choices: [acknowledge("It stays as text on the Gall.")]
    }
  end

  # A statement the producer set aside as hedged (d213, Hedges step).
  defp build(:set_aside_statements, item, _ctx) do
    term = item.subject["term"]
    picker = if item.subject["slot"] == "place", do: :place, else: :statement

    state = %Choice{
      label: "State it…",
      hint: "Use this when you judge the Source states it outright. You choose what it says.",
      picker: picker
    }

    leave = %Choice{
      label: "Leave it out",
      hint: "It stays out; the words remain in the Source's text.",
      decision: %{"keep" => true}
    }

    # Its Galls, then the producer's note on it.
    context =
      case {covered_names(item), producer_note(item)} do
        {names, nil} -> names
        {nil, note} -> note
        {names, note} -> "#{names}. #{note}"
      end

    %{
      written: term,
      context: context,
      question: "Should this hedged statement go in as a Fact?",
      proposal:
        proposal("Leave it out", "A hedge stays out unless you state it", %{"keep" => true}),
      choices: [leave | if(covered_galls(item) == [], do: [], else: [state])]
    }
  end

  defp build(:acts, item, ctx) do
    act = act_text(item.subject, ctx)
    reason = item.reason && " " <> cap(String.trim_trailing(item.reason, ".")) <> "."

    %{
      written: act,
      question: "#{act}.#{reason}",
      proposal: nil,
      undecided: acknowledged(),
      choices: [
        acknowledge("The act is kept as history; the tree doesn't change.")
      ]
    }
  end

  # One a merge left (`Gallformers.Import.Merge`): of no Source; the Gall
  # (or plant) kept, the Facts that tie, and the merge in its reason.
  defp build(:same_date, %QueueItem{subject: %{"merge" => _}} = item, ctx) do
    facts =
      item.statement_ref
      |> String.replace_prefix("merge:", "")
      |> String.split(" | ")
      |> Enum.join(" · ")

    written =
      case item.subject["gall_id"] do
        nil -> facts
        id -> "#{name(ctx, :galls, id)}: #{facts}"
      end

    %{
      written: written,
      question: "#{item.reason}. Acknowledge it for a curator to follow up?",
      proposal: nil,
      undecided: acknowledged(),
      choices: [
        acknowledge("The Fact keeps its standing until a dated Gallformers statement settles it.")
      ]
    }
  end

  defp build(:same_date, item, ctx) do
    what = describe_statement(item, ctx) || "this #{humanize(item.subject["type"] || "Fact")}"

    %{
      written: what,
      question:
        "Another Source of the same date says the opposite about #{what}. Acknowledge it for a " <>
          "curator to follow up?",
      proposal: nil,
      undecided: acknowledged(),
      choices: [
        acknowledge("The Fact keeps its standing until a dated Gallformers statement settles it.")
      ]
    }
  end

  defp build(:generation_outside, item, ctx) do
    gall = name(ctx, :galls, item.subject["gall_id"])
    inducer = name(ctx, :taxa, item.subject["inducer_id"])
    generation = item.subject["generation"]

    %{
      written: gall,
      question:
        "#{gall} has the #{generation} generation, which isn't among those that apply to its " <>
          "Inducer, #{inducer}.",
      proposal: nil,
      undecided: acknowledged(),
      choices: [acknowledge("Nothing changes; check the generation or the Inducer later.")]
    }
  end

  defp build(:source, %QueueItem{statement_ref: "retracts"} = item, ctx) do
    written = item.subject["citation_as_written"] || item.subject["citation"]

    %{
      written: written,
      question: "Which Source does this notice retract: “#{written}”?",
      proposal: nil,
      undecided: undecided(item, ctx, :sources),
      candidates: candidates(item, ctx, :sources),
      choices:
        source_choices(item, ctx, "That Source is marked as retracted.") ++
          [
            %Choice{
              label: "Leave the retraction out",
              hint: "No Source is marked as retracted.",
              decision: %{"skip" => true}
            }
          ]
    }
  end

  defp build(:source, item, ctx) do
    written = item.subject["title"] || item.subject["citation"]

    %{
      written: written,
      context: if(item.subject["title"], do: item.subject["citation"]),
      question: "Is “#{written}” a Source Gallformers already holds?",
      proposal: nil,
      undecided: undecided(item, ctx, :sources),
      candidates: candidates(item, ctx, :sources),
      choices:
        source_choices(item, ctx, "The statements are attributed to this Source.") ++
          [
            %Choice{
              label: "It's a new Source: add it",
              hint: "Adds “#{written}” as a new Source.",
              decision: %{"new" => true}
            }
          ]
    }
  end

  # A Source's taxonomic statement newer than what the tree follows
  # (`Gallformers.Import.TaxonomyQueue`): accept it (the tree follows), or
  # decline it with a reason, asked only once Decline is chosen. What the
  # tree holds now is the page's fresh reading (`subject["now"]`), else
  # what it held when the question was raised.
  defp build(:taxonomy_acceptance, item, ctx) do
    s = item.subject
    claim = statement_claim(s, ctx)
    now = s["now"] || item.reason
    now_text = if now, do: " " <> cap(String.trim_trailing(now, ".")) <> "."
    follow = "Accept: follow #{ctx.who}"

    %{
      written: statement_written(s, ctx),
      context: s["stated"] && "Stated #{s["stated"]}",
      question: "#{cap(ctx.who)} #{claim}.#{now_text} Follow #{ctx.who}?",
      scope:
        "The tree follows the newest statement a curator has accepted; this one is newer. " <>
          "Facts about Galls attach to the taxa, so they are right either way.",
      proposal:
        proposal(
          follow,
          "The literature decides: a newer paper is followed unless you have " <>
            "reason not to.",
          %{"accept" => true}
        ),
      choices: [
        %Choice{
          label: follow,
          hint: accept_effect(s, ctx),
          decision: %{"accept" => true}
        },
        %Choice{
          label: "Decline",
          hint:
            "The tree keeps following the paper it follows now. #{cap(poss(ctx.who))} " <>
              "statement stays on record as declined, with your reason.",
          picker: :reason,
          note: "Why you don't follow it; readers see it beside the declined statement."
        }
      ]
    }
  end

  # A Gall on a taxon an accepted split divided, which the splitting paper's
  # own statements don't settle (`Gallformers.Import.SplitQuestions`): each
  # daughter (the split taxon itself in its narrow sense), or not known yet.
  # A daughter the paper's Galls share a Host with is suggested, never firm.
  defp build(:split_inducer, item, ctx) do
    s = item.subject
    gall = name(ctx, :galls, s["gall_id"])
    split_id = s["taxon_id"]
    split = name(ctx, :taxa, split_id)
    into = List.wrap(s["into_taxon_ids"])
    daughters = and_list(Enum.map(into, &name(ctx, :taxa, &1)))
    suggested = item.proposal["taxon_id"]

    %{
      written: gall,
      context: "Its Inducer: #{split}",
      question:
        "#{cap(ctx.who)} splits #{split} into #{daughters}. Which taxon induces #{gall} now?",
      scope:
        "Only the Gall's Inducer changes. Older papers' statements move with it and keep the " <>
          "name they wrote.",
      proposal:
        suggested &&
          proposal(
            name(ctx, :taxa, suggested),
            item.proposal["why"],
            %{
              "taxon_id" => suggested
            },
            firm: false
          ),
      choices:
        Enum.map(into, &daughter_choice(ctx, &1, split_id, gall)) ++
          [
            %Choice{
              label: "Not known yet",
              hint:
                "It stays on #{split}, marked as the name in its old broad sense (before " <>
                  "#{poss(ctx.who)} split), until a later Source settles it.",
              decision: %{"not_known" => true}
            }
          ]
    }
  end

  defp build(:gall_rename, item, _ctx) do
    %{"from" => from, "to" => to} = item.proposal
    collision? = item.proposal["collision"] == true

    %{
      written: from,
      question: "A change in the tree renames #{from} to #{to}. Rename the Gall?",
      proposal:
        unless(collision?,
          do: proposal("Rename it to #{to}", nil, %{"accept" => true})
        ),
      undecided: %{label: "Keep #{from}?", why: "#{to} is already another Gall's name"},
      warning:
        if(collision?,
          do:
            "#{to} is already another Gall's name: renaming is refused until that Gall's name " <>
              "changes."
        ),
      choices: [
        %Choice{
          label: "Rename it to #{to}",
          hint: "#{from} is kept as a former name.",
          decision: %{"accept" => true}
        },
        %Choice{
          label: "Keep the name #{from}",
          hint: "The name is fixed, so later changes to the tree propose nothing for it.",
          decision: %{"reject" => true}
        }
      ]
    }
  end

  defp daughter_choice(ctx, split_id, split_id, _gall) do
    split = name(ctx, :taxa, split_id)

    %Choice{
      label: "#{split}, in its narrow sense",
      hint: "It stays on #{split}, as the split leaves it: no rename.",
      decision: %{"taxon_id" => split_id}
    }
  end

  defp daughter_choice(ctx, taxon_id, _split_id, gall) do
    taxon = name(ctx, :taxa, taxon_id)

    %Choice{
      label: taxon,
      hint: "#{gall}'s Inducer becomes #{taxon}; the Gall gets a rename proposal.",
      decision: %{"taxon_id" => taxon_id}
    }
  end

  # -- Hosts ---------------------------------------------------------------------

  # A Host the Source names only by a common name ("the black oak"): its
  # suggestions are Gallformers' plants of that common name; it takes no
  # synonym, and may be only the genus.
  defp common_name?(item), do: item.subject["common_name"] == true

  defp another_plant(written, true),
    do: %Choice{
      label: "Another plant…",
      hint:
        "Search Gallformers and WCVP by name. “#{written}” is a common name: " <>
          "it is not added as a synonym.",
      picker: :plant,
      as: "common_name"
    }

  defp another_plant(_written, false),
    do: %Choice{
      label: "Another plant…",
      hint: "Search Gallformers and WCVP by name.",
      picker: :plant
    }

  # A common name that is the genus's own ("oaks") is the genus: offered
  # last, as "Only the genus", never proposed.
  defp not_the_genus(targets, item, true) do
    case common_genus(item) do
      %{"taxon_id" => id} -> Enum.reject(targets, &(&1.taxon_id == id))
      nil -> targets
    end
  end

  defp not_the_genus(targets, _item, false), do: targets

  # A section of the genus a common name points to, picked from its
  # sections: an unnamed oak is usually a section's (d213).
  defp section_choices(item, ctx, true) do
    case {common_genus(item), host_sections(item)} do
      {%{"name" => name}, [_ | _] = sections} ->
        [
          %Choice{
            label: "A section of #{name}",
            hint:
              "#{cap(poss(ctx.who))} Host statements go on the section you pick: an unnamed " <>
                "plant of a genus is usually placed in one of its sections.",
            effect: "#{cap(poss(ctx.who))} Host statements go on %{taxon}, not a species.",
            picker: :section,
            sections: sections
          }
        ]

      _ ->
        []
    end
  end

  defp section_choices(_item, _ctx, false), do: []

  defp host_sections(item) do
    for %{"taxon_id" => id, "name" => name} = s <- List.wrap(item.proposal["sections"]),
        is_integer(id),
        do: %{id: id, name: name, common_name: s["common_name"]}
  end

  # The genus a common name points to (the resolver's), else the one every
  # suggestion is in.
  defp common_genus(item) do
    case item.proposal["genus"] do
      %{"taxon_id" => id} = genus when is_integer(id) ->
        genus

      _ ->
        item.proposal
        |> Map.get("suggestions")
        |> List.wrap()
        |> Enum.map(& &1["genus"])
        |> Enum.uniq()
        |> case do
          [%{"taxon_id" => id} = genus] when is_integer(id) -> genus
          _ -> nil
        end
    end
  end

  # The genus, last (only when no section fits); else a search.
  defp genus_choices(item, ctx, true) do
    case common_genus(item) do
      %{"taxon_id" => id, "name" => name} ->
        last =
          if host_sections(item) == [], do: "", else: ", only when no section fits"

        [
          %Choice{
            label: "Only the genus: #{name}",
            hint:
              "#{cap(poss(ctx.who))} Host statements go on the genus #{name}, not a species" <>
                "#{last}.",
            decision: %{"taxon_id" => id}
          }
        ]

      _ ->
        [
          %Choice{
            label: "Only the genus…",
            hint:
              "Search the tree for the genus: #{poss(ctx.who)} Host statements go on it, " <>
                "not a species.",
            picker: :taxon
          }
        ]
    end
  end

  defp genus_choices(_item, _ctx, false), do: []

  # Each plant a Host may be, from its suggestions (or, for a Host held by
  # several plants, its candidates), once each.
  defp host_targets(item, written, ctx) do
    from_suggestions =
      item.proposal
      |> Map.get("suggestions")
      |> List.wrap()
      |> Enum.filter(&offered?/1)
      |> Enum.map(&host_target(&1, written, ctx))
      |> Enum.uniq_by(& &1.key)

    if from_suggestions == [],
      do:
        for(
          id <- candidate_ids(item),
          name = name(ctx, :taxa, id),
          do: %{
            key: {:taxon, id},
            label: name,
            choice: "Use #{name}",
            does: "#{cap(poss(ctx.who))} Host statements go on this plant",
            decision: %{"taxon_id" => id},
            pending: false,
            why: nil,
            taxon_id: id,
            identity: plant_identity(id)
          }
        ),
      else: from_suggestions
  end

  # A WCVP record no one can add (an unplaced name) is not a choice.
  defp offered?(s), do: is_integer(s["taxon_id"]) or s["action"] == "add_from_wcvp"

  defp host_target(%{"match" => "common_name", "taxon_id" => id} = s, _written, ctx)
       when is_integer(id) do
    label = Map.get(ctx.names.taxa, id) || s["name"]

    %{
      key: {:taxon, id},
      label: label,
      choice: "Use #{label}: Gallformers' “#{s["common_name"]}”",
      does: "#{cap(poss(ctx.who))} Host statements go on this plant",
      decision: %{"taxon_id" => id},
      pending: false,
      why:
        "Gallformers' common name “#{s["common_name"]}”: a common name may mean another " <>
          "plant, so check it",
      taxon_id: id,
      identity: plant_identity(id)
    }
  end

  defp host_target(%{"taxon_id" => id} = s, written, ctx) when is_integer(id) do
    {name, authors} = accepted_record(s)
    label = full_name(Map.get(ctx.names.taxa, id) || name, authors)

    %{
      key: {:taxon, id},
      label: label,
      choice: "Use #{label}",
      does: "Adds “#{written}” to it as a synonym",
      decision: %{"taxon_id" => id, "add_synonym" => true},
      pending: false,
      why: host_why(s, ctx),
      taxon_id: id,
      identity: plant_identity(id)
    }
  end

  defp host_target(s, _written, ctx) do
    {name, authors} = accepted_record(s)
    label = full_name(name, authors)
    wcvp_id = get_in(s, ["accepted", "wcvp_id"]) || s["wcvp_id"]

    %{
      key: {:wcvp, wcvp_id},
      label: label,
      choice: "Add #{label} from WCVP",
      does: "Adds this plant to Gallformers from WCVP",
      decision: %{"wcvp_id" => wcvp_id},
      pending: false,
      why: not_held(host_why(s, ctx)),
      taxon_id: nil,
      identity: nil
    }
  end

  # A plant Gallformers holds: a link to it.
  defp plant_identity(id), do: %{identity(nil) | path: taxon_path(id), held: true}

  # A plant Gallformers doesn't hold yet: accepting it adds it.
  defp not_held(nil), do: "Not in Gallformers yet: accepting adds it from WCVP"
  defp not_held(why), do: why <> ". Not in Gallformers yet: accepting adds it from WCVP"

  defp accepted_record(%{"accepted" => %{"name" => name} = accepted}),
    do: {name, accepted["authors"]}

  defp accepted_record(s), do: {s["name"], s["authors"]}

  defp full_name(name, nil), do: name
  defp full_name(name, authors), do: "#{name} #{authors}"

  # The proposed plant, or failing that the first suggestion, only to check.
  # A common name's only plant is a suggestion to check; of several, none.
  defp host_proposal(item, targets, common?) do
    proposed = item.proposal["proposed"]
    target = Enum.find(targets, &(is_integer(proposed) and &1.taxon_id == proposed))
    suggestion? = item.kind == :unresolved_host and targets != []

    cond do
      common? and length(targets) != 1 ->
        nil

      target ->
        proposal(target.label, target.why, target.decision, pending: target.pending)

      suggestion? ->
        [first | _] = targets
        proposal(first.label, first.why, first.decision, firm: false, pending: first.pending)

      true ->
        nil
    end
  end

  defp host_why(%{"match" => "synonym", "source" => "wcvp"} = s, _ctx),
    do: "WCVP lists #{full_name(s["name"], s["authors"])} as a synonym of it"

  defp host_why(%{"match" => "exact"}, _ctx), do: "the name as WCVP holds it"

  defp host_why(%{"match" => "spelling_variant", "source" => "wcvp"}, _ctx),
    do: "another spelling or ending of a name WCVP holds"

  defp host_why(%{"match" => "spelling_variant"}, _ctx),
    do: "another spelling or ending of a name Gallformers holds"

  defp host_why(%{"match" => "species_of_infraspecies"}, _ctx),
    do: "the species of this variety or subspecies"

  defp host_why(%{"match" => "infraspecies_as_species"}, _ctx),
    do: "the variety's own name as a species, so check it"

  # A near spelling names the WCVP record that was near, and whether it is
  # a synonym of the plant offered.
  defp host_why(%{"match" => "edit_distance", "name" => name} = s, ctx) when is_binary(name) do
    near = "WCVP's #{full_name(name, s["authors"])}, a near spelling of #{poss(ctx.who)} name"

    if is_map(s["accepted"]),
      do: near <> ", is a synonym of it: check it",
      else: near <> ": a likely misspelling, so check it"
  end

  defp host_why(%{"match" => "edit_distance"}, _ctx),
    do: "a near spelling in WCVP: a likely misspelling, so check it"

  defp host_why(_suggestion, _ctx), do: nil

  # -- names held valid ------------------------------------------------------------

  # The taxon Gallformers holds the name under: {its name, the proposal,
  # the choice to follow it}. Proposed only when the resolver proposed it;
  # otherwise a suggestion to check.
  defp follow_gallformers(item, ctx) do
    proposed = item.proposal["proposed"]
    firm = is_integer(proposed)

    case proposed || List.first(candidate_ids(item)) do
      nil ->
        {nil, nil, []}

      id ->
        target = name(ctx, :taxa, id)
        decision = %{"taxon_id" => id}

        {why, hint} =
          if firm,
            do:
              {"current name in Gallformers",
               "#{cap(poss(ctx.who))} name is kept as the original combination."},
            else:
              {"Gallformers holds it as a synonym of this species: check that synonymy",
               "Only once the synonymy has been checked."}

        follow = %Choice{
          label: "Follow Gallformers: it's #{target}",
          hint: "#{cap(poss(ctx.who))} statements go on #{target}. " <> hint,
          decision: decision,
          identity: identity(ctx, id),
          holding: holding(ctx, id, written_name(item))
        }

        {target, proposal(target, why, decision, firm: firm), [follow]}
    end
  end

  # In a taxonomy batch a name held valid holds nothing and may only be
  # noted: {the extra choice, what the question says instead}.
  defp taxonomy_note(%{batch_type: :taxonomy} = ctx) do
    history = "#{poss(ctx.who)} acts about it are kept as history"

    {[
       %Choice{
         label: "Note the disagreement only",
         hint: "The tree stays as it is; #{history}.",
         decision: %{}
       }
     ], %{holds_approval: false, leave: "If you leave it: nothing waits; #{history}."}}
  end

  defp taxonomy_note(_ctx), do: {[], %{}}

  # -- taxa, Galls and Sources -----------------------------------------------------

  defp taxon_proposal(item, ctx, why) do
    case item.proposal["proposed"] do
      id when is_integer(id) -> proposal(name(ctx, :taxa, id), why, %{"taxon_id" => id})
      _ -> nil
    end
  end

  # The proposed Gall: firm only when the matcher proposed it and nothing
  # conflicts with what the Source says (`Gallformers.Import.Proposals`);
  # an undescribed match, or only a best match, is to confirm.
  defp gall_proposal(item, ctx, why) do
    conflicts = List.wrap(item.proposal["conflicts"])

    case {item.proposal["proposed"], item.proposal["best"]} do
      {id, _best} when is_integer(id) ->
        cond do
          conflicts != [] -> conflicted(ctx, id, conflicts)
          item.kind == :undescribed_gall -> best(ctx, id, why)
          true -> proposal(name(ctx, :galls, id), why, %{"gall_id" => id})
        end

      {_proposed, id} when is_integer(id) ->
        if conflicts != [], do: conflicted(ctx, id, conflicts), else: best(ctx, id, why)

      _ ->
        nil
    end
  end

  defp conflicted(ctx, id, conflicts),
    do:
      proposal(name(ctx, :galls, id), nil, %{"gall_id" => id},
        firm: false,
        check: "Check: it conflicts on #{field_labels(conflicts)}"
      )

  defp best(ctx, id, why),
    do:
      proposal(name(ctx, :galls, id), why, %{"gall_id" => id},
        firm: false,
        check: "Best match: confirm it"
      )

  defp firm_gall_why(item) do
    if match?([_], candidate_ids(item)),
      do: "the only Gall Gallformers holds for the species",
      else: "the Gall that agrees best"
  end

  # No proposal: which Gall, and whether every candidate conflicts with
  # what the Source says (a reason to look, not a verdict).
  defp gall_undecided(item, ctx) do
    ids = candidate_ids(item)
    n = length(ids)
    every = n > 0 and Enum.all?(ids, &(gall_conflicts(item, &1) != []))

    cond do
      every and n == 1 ->
        %{label: "Which Gall?", why: "Check: it conflicts with what #{ctx.who} says"}

      every and n == 2 ->
        %{label: "Which Gall?", why: "Check: both Galls conflict with what #{ctx.who} says"}

      every ->
        %{label: "Which Gall?", why: "Check: all #{n} Galls conflict with what #{ctx.who} says"}

      n > 0 ->
        %{undecided(item, ctx, :galls) | label: "Which Gall?"}

      true ->
        undecided(item, ctx, :galls)
    end
  end

  defp taxon_choices(item, ctx, label, hint) do
    written = written_name(item)

    for id <- Enum.take(proposed_first(item), @shown),
        name = name(ctx, :taxa, id),
        do: %Choice{
          label: label.(name),
          hint: hint.(name),
          decision: %{"taxon_id" => id},
          identity: identity(ctx, id),
          holding: holding(ctx, id, written)
        }
  end

  # The candidates offered as answers (at most three) and the others.
  defp shown(item, ctx) do
    others = for id <- Enum.drop(proposed_first(item), @shown), do: candidate(ctx, :taxa, id)

    %{
      candidates: candidates(item, ctx, :taxa),
      others: others,
      more:
        if(others != [],
          do:
            "#{length(others)} more possible #{plural(length(others), "match", "matches")}: " <>
              "choose “Another taxon” to see them all"
        )
    }
  end

  defp shown_galls(item, ctx) do
    %{
      candidates: candidates(item, ctx, :galls),
      others: for(id <- Enum.drop(proposed_first(item), @shown), do: candidate(ctx, :galls, id))
    }
  end

  defp candidate(ctx, kind, id), do: %{id: id, name: name(ctx, kind, id)}

  # Each Gall offered: compared with what the Source says, tagged, and,
  # when the Source disagrees with it, its statements to settle first.
  defp gall_choices(item, ctx) do
    for id <- Enum.take(proposed_first(item), @shown) do
      name = name(ctx, :galls, id)
      fields = gall_fields(item, id)
      base = %{"gall_id" => id}
      disagree = disagreeing(fields, ctx)

      %Choice{
        label: "It's #{name}",
        hint: "#{cap(poss(ctx.who))} statements go on #{name}.",
        decision: if(disagree == [], do: base),
        base: base,
        picker: if(disagree != [], do: :statements),
        statements: disagree,
        sections:
          if(Enum.any?(disagree, &(&1.as == "host_taxon_id")), do: ctx.host_sections, else: []),
        comparison: gall_table(ctx, id, name, fields),
        tags: gall_tags(item, id)
      }
    end
  end

  defp source_choices(item, ctx, hint) do
    for id <- candidate_ids(item),
        do: %Choice{
          label: "It's #{name(ctx, :sources, id)}",
          hint: hint,
          decision: %{"source_id" => id}
        }
  end

  # The candidates, the proposed (or a Gall's best match) first.
  defp proposed_first(item) do
    ids = candidate_ids(item)

    case item.proposal["proposed"] || item.proposal["best"] do
      id when is_integer(id) -> [id | List.delete(ids, id)]
      _ -> ids
    end
  end

  # A new taxon. Where the Source places it, it goes there; else the
  # curator may pick its parent (`{:parent, rank}`: a taxon ranked above
  # it, the tree's genus of its first word to start with), or leave it
  # unplaced (`Gallformers.Import.ApplyTaxonomy`), for a curator to place.
  defp create_taxon(label, rank, item, ctx) do
    choice = %Choice{
      label: label,
      hint: "Adds a new #{rank} to the tree.",
      decision: %{"new" => true},
      note: placed_note(item, ctx)
    }

    case {source_parent(item, ctx), item_rank(item)} do
      {nil, rank} when rank != nil ->
        %{choice | decision: nil, picker: {:parent, rank}, prefill: held_genus(item, rank, ctx)}

      _ ->
        choice
    end
  end

  defp item_rank(item) do
    rank = (item.subject || %{})["rank"]
    Enum.find(Rank.all(), &(to_string(&1) == rank))
  end

  # The genus the tree holds by the name's first word, for a taxon below a genus.
  defp held_genus(item, rank, ctx) do
    with true <- Rank.below?(rank, :genus),
         [genus, _ | _] <- item |> written_name() |> title() |> String.split() do
      ctx.held_genera[String.downcase(genus)]
    else
      _ -> nil
    end
  end

  # The parent the Source places taxon `item` under, as the batch writes it.
  defp source_parent(item, ctx) do
    ref = item.statement_ref

    ctx.content
    |> Map.get("acts")
    |> List.wrap()
    |> Enum.find_value(fn a ->
      is_map(a) and a["kind"] == "placement" and a["taxon"] == ref and
        a["stance"] != "deny" and a["parent"]
    end)
  end

  # Where a new taxon goes: under the parent the Source places it under,
  # else unplaced unless the curator picks its parent.
  defp placed_note(item, ctx) do
    case {source_parent(item, ctx), item |> written_name() |> title() |> String.split()} do
      {parent, _words} when is_binary(parent) ->
        "It goes under #{written_ref(ctx, parent, "its parent")}, where #{ctx.who} places it."

      {_none, [genus, _ | _]} ->
        "#{cap(ctx.who)} places it nowhere in this Source, so it is added unplaced: place it " <>
          "under its genus, #{genus}, from the taxonomy admin after."

      _ ->
        "#{cap(ctx.who)} places it nowhere in this Source, so it is added unplaced: place it " <>
          "in the tree from the taxonomy admin after."
    end
  end

  defp another_taxon,
    do: %Choice{
      label: "Another taxon…",
      hint: "Search the tree by name or synonym.",
      picker: :taxon
    }

  defp leave_name(item, ctx),
    do: %Choice{
      label: "Leave this name out",
      hint: drops_text(item.statement_ref, ctx),
      decision: %{"skip" => true}
    }

  # The Source is right about a name the tree holds as a synonym: the name
  # becomes a species of its own again, or another species' synonym
  # (`Gallformers.Import.SynonymDecisions`), for every Source.
  defp change_tree(item, target, ctx) do
    name = item |> written_name() |> title()
    genus = name |> String.split() |> List.first()
    from = if target, do: " of #{target}", else: ""
    instead = if target, do: " instead of #{target}", else: ""

    %Choice{
      label: "#{cap(ctx.who)} is right: change the tree",
      hint:
        "“#{name}” stops being a synonym#{from}, for every Source. You choose what it becomes.",
      picker: :tree,
      note:
        "Adds #{name} to the tree under #{genus}. This is a tree change, so it is recorded " <>
          "and replayed like any taxonomy edit.",
      effects: %{
        split:
          "#{name} becomes a species of its own again, no longer a synonym#{from}, in every " <>
            "Source. #{cap(poss(ctx.who))} statements go on it; Facts already on " <>
            "#{target || "the species"} stay there.",
        synonym_of:
          "#{name} becomes a synonym of %{taxon}#{instead}, in " <>
            "every Source. #{cap(poss(ctx.who))} statements go on %{taxon}."
      }
    }
  end

  defp create_gall(ctx),
    do: %Choice{
      label: "It's a Gall Gallformers doesn't hold: create it",
      hint: "Adds a new Gall for #{poss(ctx.who)} description.",
      decision: %{"new" => true}
    }

  # Another generation's Gall of the species: its generation is chosen
  # among those Gallformers holds no Gall of, and the new Gall is created
  # with it (`Gallformers.Import.GallDecisions`).
  defp another_generation(item, ctx) do
    generations = generations(item, ctx.gall_view)
    choose? = Enum.any?(generations, &(not &1.held))

    %Choice{
      label: "It's another generation's Gall: create it",
      hint:
        "A new Gall of this species, of a generation Gallformers doesn't hold a Gall for yet.",
      decision: if(choose?, do: nil, else: %{"new" => true}),
      picker: if(choose?, do: :generation),
      generations: if(choose?, do: generations, else: [])
    }
  end

  # The generations of the candidates' group, each held or not by a candidate.
  defp generations(item, %{galls: galls} = view) do
    held = for id <- candidate_ids(item), g = galls[id][:generation], is_binary(g), do: g
    for v <- Map.get(view, :generations, []), do: %{value: v, held: v in held}
  end

  defp generations(_item, _view), do: []

  defp another_gall(item, ctx) do
    case length(candidate_ids(item)) - @shown do
      more when more > 0 ->
        %Choice{
          label: "Choose from #{more} more possible #{plural(more, "Gall", "Galls")}…",
          hint:
            "They agree on fewer fields with what #{ctx.who} says. Or search Galls by name, " <>
              "Inducer or Host.",
          picker: :gall
        }

      _ ->
        %Choice{
          label: "Another Gall…",
          hint: "Search Galls by name, Inducer or Host.",
          picker: :gall
        }
    end
  end

  defp leave_gall(item, ctx) do
    n = length(about_gall(ctx, item.statement_ref))

    hint =
      if n > 0,
        do:
          "Its #{n} #{plural(n, "statement is", "statements are")} dropped: its Host, where it " <>
            "is, its description and its traits.",
        else: "Its statements are dropped."

    %Choice{label: "Leave this Gall out", hint: hint, decision: %{"skip" => true}}
  end

  # -- identity lines (matter d213, "Research burden") ------------------------------

  defp taxon_path(id), do: "/admin/taxonomy/#{id}"

  # A taxon answer's identity line: its family, its Galls and their Hosts
  # in Gallformers, and a link to its page.
  defp identity(nil),
    do: %{
      family: nil,
      galls: nil,
      hosts: [],
      host_count: nil,
      synonyms: [],
      path: nil,
      held: true
    }

  defp identity(ctx, id) do
    case ctx.taxa_info[id] do
      nil ->
        %{identity(nil) | path: taxon_path(id)}

      info ->
        %{
          family: info.family,
          galls: length(info.galls),
          hosts: info.hosts |> Enum.take(3) |> Enum.map(& &1.name),
          host_count: length(info.hosts),
          synonyms: info.synonyms,
          path: taxon_path(id),
          held: true
        }
    end
  end

  # Whether the taxon already holds the Source's name, in a line.
  defp holding(ctx, id, written) do
    case ctx.taxa_info[id] do
      nil -> nil
      info -> holding_line(ReviewContext.holds_name(info, title(written)), title(written), ctx)
    end
  end

  defp holding_line(:exact, name, _ctx),
    do: %{kind: :yes, text: "✓ Already holds “#{name}” as a synonym"}

  defp holding_line({:close_spelling, held}, _name, ctx),
    do: %{kind: :near, text: "Holds “#{held}”: a close spelling of #{poss(ctx.who)} name"}

  defp holding_line({:same_epithet_other_genus, held}, _name, _ctx),
    do: %{kind: :near, text: "Holds “#{held}”: the same species name in another genus"}

  defp holding_line(:no, name, _ctx),
    do: %{kind: :no, text: "Doesn't hold “#{name}”: matched on the species name only"}

  # -- what leaving a name out drops -------------------------------------------------

  defp drops_text(ref, ctx) do
    facts =
      for f <- List.wrap(ctx.content["facts"]),
          is_map(f) and ref in [f["subject"], f["object"]],
          do: f

    acts =
      for a <- List.wrap(ctx.content["acts"]),
          is_map(a) and ref in Enum.map(~w(taxon parent name accepted), &a[&1]),
          do: a

    case length(facts) + length(acts) do
      0 ->
        "No statement in this Source uses the name, so nothing is dropped."

      n ->
        parts = [facts_part(facts, ref, ctx), acts_part(acts)] |> Enum.filter(& &1)
        "Drops #{n} #{plural(n, "statement", "statements")}: #{and_list(parts)}."
    end
  end

  defp facts_part([], _ref, _ctx), do: nil

  defp facts_part(facts, ref, ctx) do
    roles = facts |> Enum.map(&role(&1, ref)) |> Enum.uniq() |> and_list()

    galls =
      facts
      |> Enum.map(&if(&1["subject"] == ref, do: &1["object"], else: &1["subject"]))
      |> Enum.uniq()
      |> Enum.map(&written_ref(ctx, &1, "a Gall"))
      |> and_list()

    "#{roles} of #{galls}"
  end

  defp acts_part([]), do: nil

  defp acts_part(acts),
    do: "#{length(acts)} #{plural(length(acts), "taxonomic act", "taxonomic acts")}"

  defp role(%{"type" => "host_of", "subject" => ref}, ref), do: "the Host"
  defp role(%{"type" => "inducer_of", "subject" => ref}, ref), do: "the Inducer"

  defp role(%{"type" => type}, _ref) when is_binary(type),
    do: "the #{type |> String.split("_") |> List.first()}"

  defp role(_fact, _ref), do: "a statement"

  # The batch's Facts about Gall `ref`.
  defp about_gall(ctx, ref) do
    for f <- List.wrap(ctx.content["facts"]),
        is_map(f) and ref in [f["gall"], f["subject"], f["object"]],
        do: f
  end

  # -- Galls compared with what the Source says (matter d213, Galls step) ------------

  @gall_fields [
    {"host", "Host"},
    {"where", "Where on the plant"},
    {"detachable", "Detachable"},
    {"generation", "Generation · season"},
    {"form", "Form"}
  ]

  @marks %{"agree" => :agree, "differ" => :differ, "conflict" => :conflict}

  # A candidate's comparison from the proposal (`"comparisons"`), field to result.
  defp gall_fields(item, id) do
    item.proposal
    |> Map.get("comparisons")
    |> List.wrap()
    |> Enum.find_value(%{}, &(is_map(&1) and &1["gall_id"] == id and (&1["fields"] || %{})))
  end

  # The fields a candidate conflicts on: its comparison's, else the
  # proposal's for the picked candidate.
  defp gall_conflicts(item, id) do
    from_comparison =
      item.proposal
      |> Map.get("comparisons")
      |> List.wrap()
      |> Enum.find_value(&(is_map(&1) and &1["gall_id"] == id and List.wrap(&1["conflicts"])))

    picked = item.proposal["proposed"] || item.proposal["best"]

    cond do
      is_list(from_comparison) -> from_comparison
      picked == id -> List.wrap(item.proposal["conflicts"])
      true -> []
    end
  end

  defp field_labels(fields), do: fields |> Enum.map(&field_label/1) |> and_list()

  defp field_label("host"), do: "Host"
  defp field_label("where"), do: "where on the plant"
  defp field_label("detachable"), do: "detachable"
  defp field_label("generation"), do: "generation and season"
  defp field_label("form"), do: "form"
  defp field_label(other), do: humanize(to_string(other))

  defp gall_tags(item, id) do
    conflicts = gall_conflicts(item, id)

    best =
      if item.proposal["best"] == id and not is_integer(item.proposal["proposed"]) and
           conflicts == [],
         do: [%{text: "Best match: confirm it", kind: :best}],
         else: []

    conflict =
      if conflicts != [],
        do: [%{text: "Conflicts: #{field_labels(conflicts)}", kind: :conflict}],
        else: []

    best ++ conflict
  end

  # The side-by-side table: what the Source says and what the Gall is, field
  # by field, then the descriptions. Nil without what to compare.
  defp gall_table(%{gall_view: %{source: source, galls: galls}} = ctx, id, name, fields)
       when map_size(fields) > 0 do
    gall = Map.get(galls, id, %{})

    rows =
      for {key, label} <- @gall_fields,
          key != "form" or Map.get(fields, "form", "none") != "none",
          do: %{
            label: label,
            source: source_value(key, source),
            gall: gall_value(key, gall),
            mark: Map.get(@marks, fields[key], :none)
          }

    stated = Enum.count(rows, &(&1.mark != :none))
    agrees = Enum.count(rows, &(&1.mark == :agree))

    meta =
      [
        "Agrees on #{agrees} of #{stated} stated #{plural(stated, "field", "fields")}",
        gall[:photos] && "#{gall.photos} #{plural(gall.photos, "photo", "photos")}",
        gall[:sources] && "#{gall.sources} #{plural(gall.sources, "Source", "Sources")}"
      ]
      |> Enum.filter(& &1)
      |> Enum.join(" · ")

    %{
      who: ctx.who,
      gall: name,
      rows: rows,
      description: {source[:text], gall[:description]},
      meta: meta,
      quoted_in: gall[:quoted_in] && "✓ Gallformers' description comes from #{gall.quoted_in}",
      path: "/gall/#{id}?edit"
    }
  end

  defp gall_table(_ctx, _id, _name, _fields), do: nil

  defp source_value("host", source) do
    case List.wrap(source[:hosts]) do
      [] ->
        nil

      hosts ->
        Enum.map_join(hosts, ", ", &host_text/1)
    end
  end

  defp source_value("generation", source) do
    seasons = terms_text(source[:season])
    Enum.join(Enum.filter([source[:generation] || "not named", seasons], & &1), " · ")
  end

  defp source_value(key, source), do: terms_text(source[source_key(key)])

  defp host_text(%{written: written, name: name}) when is_binary(written) and written != name,
    do: "#{name} (written “#{written}”)"

  defp host_text(%{name: name}), do: name

  defp source_key("where"), do: :where
  defp source_key("detachable"), do: :detachable
  defp source_key("form"), do: :form

  defp terms_text(entries) do
    case List.wrap(entries) do
      [] ->
        nil

      entries ->
        Enum.map_join(entries, ", ", &term_text/1)
    end
  end

  defp term_text(%{term: term, value: value}) when is_binary(term) and term != value,
    do: "#{value} (“#{term}”)"

  defp term_text(%{value: value}), do: value

  defp gall_value("host", gall), do: list_text(gall[:hosts], 3)
  defp gall_value("where", gall), do: list_text(gall[:where], 4)
  defp gall_value("detachable", gall), do: list_text(gall[:detachable], 4)
  defp gall_value("form", gall), do: list_text(gall[:form], 4)

  defp gall_value("generation", gall) do
    seasons = list_text(gall[:season], 4)
    Enum.join(Enum.filter([gall[:generation] || "none", seasons], & &1), " · ")
  end

  defp list_text(values, n) do
    case List.wrap(values) do
      [] ->
        nil

      values when length(values) > n ->
        "#{Enum.join(Enum.take(values, n), ", ")} and #{length(values) - n} more"

      values ->
        and_list(values)
    end
  end

  # The Source's statements a candidate disagrees with (a field that differs
  # or conflicts) that a curator can leave out: each field's Facts, and for
  # the Host its name, to read as another plant.
  defp disagreeing(fields, %{gall_view: %{source: source}} = ctx) do
    for {key, _label} <- @gall_fields,
        Map.get(fields, key) in ["differ", "conflict"],
        entry = settle(key, source, ctx),
        do: entry
  end

  defp disagreeing(_fields, _ctx), do: []

  # A Host above species rank (a genus: the Source's name for many Galls)
  # goes on the plant picked for this Gall only (`"host_taxon_id"`); one at
  # species rank is read as the plant throughout the Source.
  defp settle("host", source, ctx) do
    hosts = List.wrap(source[:hosts])
    refs = Enum.flat_map(hosts, &List.wrap(&1[:refs]))
    written = hosts |> Enum.map(&(&1.written || &1.name)) |> Enum.uniq()
    what = "“#{Enum.join(written, ", ")}”"
    who = cap(poss(ctx.who))

    if refs != [] do
      %{
        key: "host",
        label: "Host: #{what}",
        refs: refs,
        keep: "Keep it as #{hosts |> Enum.map(& &1.name) |> Enum.uniq() |> and_list()}",
        reading: if(match?([_], written), do: hd(written)),
        left: "#{who} #{what} is left out."
      }
      |> Map.merge(
        if above_species?(hosts),
          do: %{
            as: "host_taxon_id",
            other: "On another plant",
            note:
              "Puts this Gall's #{what} on the plant you pick, for this Gall only: " <>
                "#{who} other #{what} statements stay as they are.",
            read:
              "#{who} #{what} goes in on %{taxon}, for this Gall only. " <>
                "#{who} other #{what} statements stay as they are."
          },
          else: %{
            as: nil,
            other: "He means another plant",
            note: "Records what #{ctx.who} means by #{what}, for every use of it in #{ctx.who}.",
            read: "#{who} #{what} is read as %{taxon} throughout #{ctx.who}."
          }
      )
    end
  end

  defp settle(key, source, ctx) do
    entries = List.wrap(source[settle_key(key)])
    refs = Enum.flat_map(entries, &List.wrap(&1[:refs]))
    what = "“#{Enum.map_join(entries, ", ", &(&1.term || &1.value))}”"

    if refs != [] do
      %{
        key: key,
        label: "#{settle_label(key)}: #{what}",
        refs: refs,
        keep: "Keep it",
        reading: nil,
        as: nil,
        other: nil,
        note: nil,
        left: "#{cap(poss(ctx.who))} #{what} is left out.",
        read: nil
      }
    end
  end

  defp above_species?(hosts),
    do: Enum.any?(hosts, &(Map.get(&1, :rank) not in [nil | @species_level]))

  # The season is the part of "generation and season" a Source states as Facts.
  defp settle_key("generation"), do: :season
  defp settle_key(key), do: source_key(key)

  defp settle_label("where"), do: "Where on the plant"
  defp settle_label("detachable"), do: "Detachable"
  defp settle_label("generation"), do: "Season"
  defp settle_label("form"), do: "Form"

  # A Gall question's line beside the Source's words: its Host and where.
  defp gall_context(item, %{gall_view: %{source: source}}) do
    names = source |> Map.get(:hosts, []) |> Enum.map(& &1.name) |> Enum.uniq()
    n = length(candidate_ids(item))

    [
      if(names == [], do: "Host not stated", else: "On #{and_list(names)}"),
      terms_text(source[:where]) && Enum.map_join(source.where, ", ", & &1.value),
      n > 0 && "#{n} #{plural(n, "candidate", "candidates")}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp gall_context(_item, _ctx), do: nil

  defp acknowledge(hint), do: %Choice{label: "Acknowledge", hint: hint, decision: %{}}
  defp acknowledged, do: %{label: "Acknowledge when you've looked", why: nil}

  defp candidate_ids(item),
    do: item.proposal |> Map.get("candidate_ids") |> List.wrap() |> Enum.filter(&is_integer/1)

  defp candidates(item, ctx, kind),
    do: for(id <- candidate_ids(item), do: %{id: id, name: name(ctx, kind, id)})

  defp undecided(item, ctx, kind) do
    case candidates(item, ctx, kind) do
      [] ->
        %{label: "No proposal", why: nil}

      [one] ->
        %{label: "No proposal: 1 candidate", why: one.name}

      several ->
        %{
          label: "No proposal: #{length(several)} candidates",
          why: Enum.map_join(several, " or ", & &1.name)
        }
    end
  end

  defp name(ctx, :taxa, id), do: Map.get(ctx.names.taxa, id) || "taxon #{id}"
  defp name(ctx, :galls, id), do: Map.get(ctx.names.galls, id) || "Gall #{id}"
  defp name(ctx, :sources, id), do: Map.get(ctx.names.sources, id) || "Source #{id}"

  defp method_why("epithet_in_family"), do: "the same species name, in the same family"
  defp method_why("spelling_variant"), do: "another spelling or ending of the same name"
  defp method_why("cynips_name"), do: "the same name, read as an old Cynips name"
  defp method_why(_method), do: nil

  # -- Trait terms ------------------------------------------------------------------

  # Who read a term and what each chose, per Gall it covers (matter d213,
  # Traits step): `%{readers: [{key, name}], covers: [%{cover, readings,
  # most}], defs, depends?}`. A reading is the set of values a reader chose
  # (sorted; `[]` for none), or `:unknown` for a format 3 checker's finding
  # (it disagreed, naming no value). `most` is what more than half of a
  # Gall's readers chose, or nil: so a silent producer gives way to two
  # checkers agreeing, as `Gallformers.Import.TraitTerms.agreement/1` has it,
  # and a two-to-one split is decided by the two.
  defp term_reading(item, ctx) do
    covers = item.subject |> Map.get("covers") |> List.wrap() |> Enum.filter(&is_map/1)

    reviewers =
      covers
      |> Enum.flat_map(&List.wrap(&1["placements"]))
      |> Enum.map(& &1["reviewer"])
      |> Enum.uniq()

    names = reviewer_names(reviewers)
    checkers = Enum.map(reviewers, &{&1, uncap(names[&1])})
    finding? = Enum.any?(covers, &(List.wrap(&1["findings"]) != []))

    %{
      readers:
        [{:producer, "the producer"} | checkers] ++
          if(finding?, do: [{:finding, "the checker"}], else: []),
      names: names,
      covers:
        for cover <- covers do
          readings = readings(cover, reviewers)
          %{cover: cover, readings: readings, most: most(readings)}
        end,
      defs: Map.get(ctx.definitions, item.subject["trait"], %{}),
      depends?: Enum.any?(covers, &depends?/1)
    }
  end

  defp readings(cover, reviewers) do
    producer =
      if is_binary(cover["note"]),
        do: [],
        else: cover |> Map.get("suggestions") |> List.wrap() |> value_set()

    placements = List.wrap(cover["placements"])

    checkers =
      for r <- reviewers,
          placed = Enum.filter(placements, &(&1["reviewer"] == r)),
          placed != [],
          do: {r, placed |> Enum.map(& &1["category"]) |> value_set()}

    finding = if List.wrap(cover["findings"]) != [], do: [{:finding, :unknown}], else: []

    [{:producer, producer} | checkers] ++ finding
  end

  defp value_set(values), do: values |> Enum.filter(&is_binary/1) |> Enum.uniq() |> Enum.sort()

  defp depends?(cover) do
    cover["depends_on_gall"] == true or
      Enum.any?(List.wrap(cover["placements"]), &(&1["depends_on_gall"] == true))
  end

  # The set more than half of a Gall's readers chose, or nil.
  defp most(readings) do
    total = length(readings)

    readings
    |> Enum.map(&elem(&1, 1))
    |> Enum.reject(&(&1 == :unknown))
    |> Enum.frequencies()
    |> Enum.find_value(fn {set, n} -> if n * 2 > total, do: set end)
  end

  # Each covered Gall: its name, its quotes, what the readers said, and
  # what most of them chose (a category, `:text` for none, or nil).
  defp term_galls(item, reading) do
    v3? = item.subject["format_version"] == 3

    for %{cover: cover, most: most} <- reading.covers, is_binary(cover["gall"]) do
      %{
        ref: cover["gall"],
        name: cover["name_as_written"] || "a Gall",
        quotes: cover_quotes(cover),
        said: producer_said(cover) ++ checkers_said(cover, reading.names, v3?),
        default: gall_default(most)
      }
    end
  end

  defp gall_default([]), do: :text
  defp gall_default([value]), do: value
  defp gall_default(_most), do: nil

  # What most readers chose for the term: one value (or set of values) for
  # every Gall (`{:values, set}`), keeping it as text (`:keep`), or that it
  # depends on the Gall (`:per_gall`, each Gall's own); nil when they split.
  # A term used in more than one sense is always decided Gall by Gall.
  defp recommendation(%QueueItem{subject: %{"status" => "ambiguous"}}, _reading, []), do: nil

  defp recommendation(%QueueItem{subject: %{"status" => "ambiguous"}}, _reading, _galls),
    do: :per_gall

  defp recommendation(_item, reading, galls) do
    most = Enum.map(reading.covers, & &1.most)
    per_gall = if galls != [] and Enum.all?(galls, &(&1.default != nil)), do: :per_gall

    cond do
      most == [] or nil in most -> nil
      reading.depends? -> per_gall
      true -> one_for_all(Enum.uniq(most)) || per_gall
    end
  end

  defp one_for_all([[]]), do: :keep
  defp one_for_all([set]), do: {:values, set}
  defp one_for_all(_sets), do: nil

  defp term_proposal(nil, _item, _reading, _galls), do: nil

  defp term_proposal({:values, set}, _item, reading, _galls),
    do: proposal(and_list(set), tally(reading, set), %{"place" => placed(set)})

  defp term_proposal(:keep, _item, _reading, _galls),
    do: proposal("Keep as text", "No reader placed it", %{"keep" => true})

  defp term_proposal(:per_gall, item, _reading, galls) do
    why =
      if item.subject["status"] == "ambiguous",
        do: "Used in more than one sense",
        else: "The readers chose differently for different Galls"

    decision =
      if Enum.all?(galls, &(&1.default != nil)),
        do: %{"categories" => Map.new(galls, &{&1.ref, text_nil(&1.default)})}

    proposal("It depends on the Gall", why, decision)
  end

  defp text_nil(:text), do: nil
  defp text_nil(value), do: value

  # One value as itself, several as the list (`%{"place" => ...}`).
  defp placed([value]), do: value
  defp placed(set), do: set

  # Who chose `set`: by name, when the same readers chose it for every
  # Gall; else for how many Galls most readers, or any, did.
  defp tally(reading, set) do
    n = length(reading.covers)

    choosers =
      for %{readings: readings} <- reading.covers,
          do: for({key, ^set} <- readings, do: key)

    cond do
      match?([[_ | _] | _], choosers) and length(Enum.uniq(choosers)) == 1 ->
        "Chosen by #{reader_list(hd(choosers), reading.readers)}#{for_galls(n)}"

      (most = Enum.count(reading.covers, &(&1.most == set))) > 0 ->
        "Most readers chose it for #{most} of the #{n} Galls"

      true ->
        "Chosen for #{Enum.count(choosers, &(&1 != []))} of the #{n} Galls"
    end
  end

  defp reader_list(keys, readers) do
    if length(keys) == 3 and length(readers) == 3,
      do: "all three readers",
      else: readers |> Enum.filter(&(elem(&1, 0) in keys)) |> Enum.map(&elem(&1, 1)) |> and_list()
  end

  defp for_galls(1), do: ""
  defp for_galls(2), do: ", for both Galls"
  defp for_galls(n), do: ", for all #{n} Galls"

  # The sets of values the readers chose, most often first.
  defp reader_sets(reading) do
    reading.covers
    |> Enum.flat_map(& &1.readings)
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&(match?([_ | _], &1) and valid?(&1, reading.defs)))
    |> Enum.frequencies_by(& &1)
    |> then(fn counts ->
      reading.covers
      |> Enum.flat_map(& &1.readings)
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&Map.has_key?(counts, &1))
      |> Enum.uniq()
      |> Enum.sort_by(&(-counts[&1]))
    end)
  end

  # Values of the Trait (when its values are known).
  defp valid?(set, defs), do: defs == %{} or Enum.all?(set, &Map.has_key?(defs, &1))

  # The readers' values, one by one, most often first.
  defp reader_values(reading), do: reading |> reader_sets() |> List.flatten() |> Enum.uniq()

  # "The 2 Galls here that use them", as the question's scope says.
  defp here_use(1), do: "The Gall here that uses them"
  defp here_use(n), do: "The #{n} Galls here that use them"

  defp here_get(1, value), do: "The Gall here gets #{value}."
  defp here_get(n, value), do: "The #{n} Galls here get #{value}."

  defp galls_word(1), do: "This Gall"
  defp galls_word(2), do: "Both Galls"
  defp galls_word(n), do: "All #{n} Galls"

  defp term_choices(item, ctx, reading, galls, rec) do
    term = item.subject["term"]
    trait = item.subject["trait"]
    tn = trait_name(trait)
    n = max(length(galls), 1)
    means = &(here_get(n, &1) <> " From now on, “#{term}” means #{&1} in every Source.")

    per_gall = %Choice{
      label: "It depends on the Gall",
      hint:
        "The words mean different things for different Galls. You choose for each Gall here; " <>
          "nothing is set for other Sources, so the next Source that uses them is asked again.",
      picker: :galls,
      effect:
        "“#{term}” stays undecided for every Source: each new Gall that uses it is asked again.",
      tally: if(rec == :per_gall, do: "The readers chose differently for different Galls"),
      proposed: rec == :per_gall
    }

    keep = %Choice{
      label: "Keep as text",
      hint:
        "The Galls here keep the Source's words, with no #{tn} value. Nothing is set for " <>
          "other Sources.",
      decision: %{"keep" => true},
      effect:
        "#{galls_word(n)} show “#{term}” in #{poss(ctx.who)} words, with no #{tn} value. " <>
          "Nothing changes for other Sources.",
      tally: if(rec == :keep, do: "No reader placed it")
    }

    if item.subject["status"] == "ambiguous" do
      [
        %{
          per_gall
          | label: "Choose for each Gall",
            hint:
              "“#{term}” means different #{tn} values in different Galls, so each Gall is " <>
                "decided here. New Galls that use it are asked again.",
            tally: nil
        },
        %{keep | hint: "These Galls show the Source's words, with no #{tn} value."}
      ]
    else
      values =
        for set <- reader_sets(reading) do
          label = and_list(set)

          %Choice{
            label: label,
            hint: set |> Enum.map(&reading.defs[&1]) |> Enum.filter(& &1) |> Enum.join(" "),
            decision: %{"place" => placed(set)},
            tally: tally(reading, set),
            effect: means.(label)
          }
        end

      another = %Choice{
        label: "Another #{tn}",
        hint: "The words mean a #{tn} value no reader chose; pick it from the list.",
        picker: {:trait_value, trait},
        as: "place",
        effect: means.("%{value}")
      }

      several = %Choice{
        label: "More than one #{tn}",
        hint:
          "The words name several values at once, like “green-yellow” or “on both sides”; " <>
            "tick each one.",
        picker: {:trait_values, trait},
        as: "place",
        values: reader_values(reading),
        effect: means.("%{value}")
      }

      no_fit = %Choice{
        label: "Fits no #{tn}",
        hint:
          "None of Gallformers' #{tn} values says this. The Galls keep the Source's words, and " <>
            "the term goes to the superadmins, who may add a value for it.",
        decision: %{"no_fit" => true},
        effect:
          "#{galls_word(n)} keep the Source's words. “#{term}” goes to the superadmins' list " <>
            "of terms that fit no #{tn}, where one may be added."
      }

      values ++
        [another, several] ++ if(galls == [], do: [], else: [per_gall]) ++ [no_fit, keep]
    end
  end

  # A covered Gall's quotes, each with the document item it is from.
  defp cover_quotes(cover) do
    for(
      e <- List.wrap(cover["evidence"]),
      is_map(e) and is_binary(e["quote"]),
      do: %{text: e["quote"], item: e["item"]}
    )
    |> Enum.uniq_by(& &1.text)
  end

  defp producer_said(cover) do
    depends =
      if cover["depends_on_gall"] == true, do: ", and says it depends on the gall", else: ""

    note = cover["note"]

    case cover |> Map.get("suggestions") |> List.wrap() |> Enum.uniq() do
      _ when is_binary(note) ->
        ["The producer set it aside: #{sentence(note)}"]

      [nil] ->
        ["The producer suggested no category#{depends}."]

      suggested ->
        named = and_list(Enum.map(suggested, &(&1 || "no category")))
        ["The producer suggested #{named}#{depends}."]
    end
  end

  defp checkers_said(cover, reviewers, v3?) do
    placed = Enum.map(List.wrap(cover["placements"]), &placed_said(&1, reviewers))

    found =
      for f <- List.wrap(cover["findings"]), is_binary(f["reason"]), do: finding_said(f)

    cond do
      placed != [] or found != [] -> placed ++ found
      v3? -> []
      true -> ["No checker placed it."]
    end
  end

  defp placed_said(placement, reviewers) do
    who = Map.get(reviewers, placement["reviewer"], "The checker")
    category = placement["category"]
    under = if category, do: "under #{category}", else: "under no category"
    depends = if placement["depends_on_gall"] == true, do: ", and says it depends on the gall"
    reason = placement["reason"]
    why = if is_binary(reason), do: ": #{sentence(reason)}", else: "."
    "#{who} placed it #{under}#{depends}#{why}"
  end

  # A format 3 checker's finding, and the producer's answer.
  defp finding_said(finding) do
    answer = get_in(finding, ["response", "reason"])
    answered = if is_binary(answer), do: " The producer answered: #{sentence(answer)}"
    "The checker: #{sentence(finding["reason"])}#{answered}"
  end

  # "The checker", or "Checker 1", "Checker 2" when several placed the terms.
  defp reviewer_names([]), do: %{}
  defp reviewer_names([one]), do: %{one => "The checker"}

  defp reviewer_names(several),
    do: several |> Enum.with_index(1) |> Map.new(fn {r, i} -> {r, "Checker #{i}"} end)

  defp sentence(text) do
    text = String.trim(text)
    if String.ends_with?(text, [".", "!", "?"]), do: text, else: text <> "."
  end

  # The values to choose from Gall by Gall, each defined once: an
  # ambiguous term's senses, then the readers' values.
  defp term_definitions(item, reading) do
    for value <- Enum.uniq(List.wrap(item.subject["candidates"]) ++ reader_values(reading)),
        is_binary(value),
        do: %{who: nil, value: value, definition: reading.defs[value]}
  end

  # -- disputes ------------------------------------------------------------------

  defp disputed, do: %{label: "Keep or drop?", why: "The producer and a checker disagree"}

  # A Host dispute kept with the Host read as another plant
  # (`Gallformers.Import.Disputes`): the plant is picked. A Host above
  # species rank (a genus, a section) is the Source's name for many Galls:
  # the plant goes in for this statement only (`"host_taxon_id"`).
  defp read_host(%{"kind" => "relationship", "type" => "host_of", "subject" => ref}, who, ctx) do
    case ctx.written[ref] do
      name when is_binary(name) and ctx.host_rank not in [nil | @species_level] ->
        %Choice{
          label: "Keep it, as another plant",
          hint: "#{cap(who)} names only “#{name}” here: it goes in on the plant you pick.",
          picker: {:reading, name},
          as: "host_taxon_id",
          base: %{"keep" => true},
          sections: ctx.host_sections,
          effect:
            "It goes in on %{taxon}, for this Gall only. #{cap(poss(who))} other “#{name}” " <>
              "statements stay as they are."
        }

      name when is_binary(name) ->
        %Choice{
          label: "Keep it, as another plant",
          hint: "#{cap(who)} means another plant by “#{name}”: it goes in on the plant you pick.",
          picker: {:reading, name},
          base: %{"keep" => true},
          sections: ctx.host_sections,
          effect:
            "It goes in on %{taxon}. #{cap(poss(who))} “#{name}” is read as %{taxon} " <>
              "throughout this Source, and the tree records it as a synonym of %{taxon} in " <>
              "#{poss(who)} sense."
        }

      _ ->
        nil
    end
  end

  defp read_host(_fact, _who, _ctx), do: nil

  # Each side's position in a sentence: its one-sentence summary, else its
  # first sentence (matter d213, Disputes step).
  defp sides(item) do
    findings = List.wrap(item.subject["findings"])

    %{
      producer:
        for(
          f <- findings,
          r = f["response"],
          is_map(r),
          text = summary(r["summary"], r["reason"]),
          do: text
        ),
      checker: for(f <- findings, text = summary(f["summary"], f["reason"]), do: text)
    }
  end

  defp summary(summary, _reason) when is_binary(summary) and summary != "", do: summary
  defp summary(_summary, reason) when is_binary(reason), do: first_sentence(reason)
  defp summary(_summary, _reason), do: nil

  defp first_sentence(text) do
    text |> String.trim() |> String.split(~r/(?<=[.!?])\s+/, parts: 2) |> hd()
  end

  @doc """
  One question for disputes about the same statement
  (`Gallformers.Import.Disputes`, `subject["group"]`), from each one's
  question (`present/2`), in order: it lists every Gall; "Keep it" keeps
  the statement for each Gall left ticked (`:keep_galls`, an unticked Gall
  dropped: `%{"keep" => true, "except" => ids}`), "Drop it" drops it for
  all (`Gallformers.Import.decide_group/3`). `source` names the Source in
  the copy.
  """
  @spec group([Question.t()], String.t() | nil) :: Question.t()
  def group([first | _] = questions, source \\ nil) do
    n = length(questions)
    who = who(source)
    statement = first.statement || first.written
    trait? = first.topic == :trait_dispute

    question =
      if trait?,
        do:
          "Should “#{first.written}” go in as the #{trait_name(first.trait)} of these #{n} Galls?",
        else: "Should this statement go in for these #{n} Galls: #{statement}?"

    %{
      first
      | written: if(trait?, do: first.written, else: statement),
        context:
          questions |> Enum.map(& &1.about) |> Enum.filter(& &1) |> Enum.uniq() |> and_list(),
        covers: n,
        question: question,
        choices:
          Enum.filter(
            [
              %Choice{
                label: "Keep it: #{statement}, for these #{n} Galls",
                hint: "Untick any Gall to drop its statement on its own.",
                picker: :keep_galls
              },
              group_reading(first, n, who),
              %Choice{
                label: if(n == 2, do: "Drop it for both", else: "Drop it for all #{n}"),
                hint: "None of them goes in; #{poss(who)} words stay in the Source's text.",
                decision: %{"skip" => true}
              }
            ],
            & &1
          )
    }
  end

  # Host disputes kept for every Gall, the Host read as the plant picked,
  # or (a Host above species rank) on the plant picked for these Galls only.
  defp group_reading(first, n, who) do
    case Enum.find(first.choices, &match?(%Choice{picker: {:reading, _}}, &1)) do
      %Choice{picker: {:reading, name}, as: "host_taxon_id"} = choice ->
        %{
          choice
          | label: "Keep it for these #{n} Galls, as another plant",
            hint:
              "#{cap(who)} names only “#{name}” here: it goes in for every Gall, on the plant " <>
                "you pick.",
            effect:
              "It goes in on %{taxon}, for these #{n} Galls only. #{cap(poss(who))} other " <>
                "“#{name}” statements stay as they are."
        }

      %Choice{picker: {:reading, name}} = choice ->
        %{
          choice
          | label: "Keep it for these #{n} Galls, as another plant",
            hint:
              "#{cap(who)} means another plant by “#{name}”: it goes in for every Gall, on " <>
                "the plant you pick.",
            effect:
              "It goes in for every Gall, on %{taxon}. #{cap(poss(who))} “#{name}” is read as " <>
                "%{taxon} throughout this Source, and the tree records it as a synonym of " <>
                "%{taxon} in #{poss(who)} sense."
        }

      nil ->
        nil
    end
  end

  # The statement a dispute is about, without its Gall, for a question
  # covering several Galls.
  defp group_statement(%{"kind" => "trait", "term" => term} = f, _ctx) when is_binary(term),
    do: "“#{term}” (#{trait_name(f["trait"])})"

  defp group_statement(%{"kind" => "trait"} = f, _ctx),
    do: "#{trait_name(f["trait"])} is #{value_of(f["value"])}"

  defp group_statement(%{"kind" => "relationship", "type" => "host_of"} = f, ctx),
    do: "#{written_ref(ctx, f["subject"], "a plant")} is the Host"

  defp group_statement(%{"kind" => "relationship", "type" => "inducer_of"} = f, ctx),
    do: "#{written_ref(ctx, f["subject"], "a taxon")} is the Inducer"

  defp group_statement(%{"kind" => "relationship"} = f, ctx),
    do:
      "#{written_ref(ctx, f["subject"], "a taxon")} is " <>
        humanize(f["type"] || "related to it")

  defp group_statement(%{"kind" => "range"} = f, _ctx) do
    place = get_in(f, ["place", "as_written"]) || value_of(f["place"])
    if f["adjustment"] == "exclude", do: "not found in #{place}", else: "recorded in #{place}"
  end

  defp group_statement(%{"kind" => "alias", "name" => name}, _ctx), do: "also called “#{name}”"

  defp group_statement(%{"kind" => "qualifier"} = f, _ctx),
    do: "the #{humanize(f["qualifier"] || "qualifier")} is #{value_of(f["value"])}"

  defp group_statement(_fact, _ctx), do: nil

  # The Gall a disputed statement is about, in the Source's words.
  defp disputed_gall(%{"kind" => "relationship"} = f, ctx),
    do: written_ref(ctx, f["object"], nil)

  defp disputed_gall(%{"gall" => ref}, ctx), do: written_ref(ctx, ref, nil)
  defp disputed_gall(_fact, _ctx), do: nil

  defp voices(item) do
    findings = List.wrap(item.subject["findings"])

    %{
      checker:
        for f <- findings, is_binary(f["reason"]) do
          if f["suggestion"],
            do: "#{f["reason"]} It suggests: #{f["suggestion"]}.",
            else: f["reason"]
        end,
      producer: for(f <- findings, r = get_in(f, ["response", "reason"]), is_binary(r), do: r)
    }
  end

  # A Fact, act, taxon or Gall statement in the Source's words, or nil.
  defp describe_statement(_item, %{fact: fact} = ctx) when is_map(fact) do
    text = fact_text(fact, ctx)

    if text && fact["stance"] == "deny",
      do: "#{cap(ctx.who)} denies that #{text}",
      else: text
  end

  defp describe_statement(%QueueItem{statement_ref: ref}, ctx) do
    case Map.get(ctx.written, ref) do
      nil -> nil
      written -> "“#{written}”"
    end
  end

  defp fact_text(%{"kind" => "trait"} = f, ctx),
    do:
      "#{written_ref(ctx, f["gall"], "the Gall")} has #{trait_name(f["trait"])} " <>
        value_of(f["value"])

  defp fact_text(%{"kind" => "relationship", "type" => "host_of"} = f, ctx),
    do:
      "#{written_ref(ctx, f["object"], "the Gall")} has " <>
        "#{written_ref(ctx, f["subject"], "a plant")} as its Host"

  defp fact_text(%{"kind" => "relationship", "type" => "inducer_of"} = f, ctx),
    do:
      "#{written_ref(ctx, f["subject"], "a taxon")} induces #{written_ref(ctx, f["object"], "the Gall")}"

  defp fact_text(%{"kind" => "relationship"} = f, ctx),
    do:
      "#{written_ref(ctx, f["subject"], "a taxon")} is #{humanize(f["type"] || "related to")} " <>
        written_ref(ctx, f["object"], "the Gall")

  defp fact_text(%{"kind" => "range"} = f, ctx) do
    place = get_in(f, ["place", "as_written"]) || value_of(f["place"])
    found = if f["adjustment"] == "exclude", do: "is not found in", else: "is recorded in"
    "#{written_ref(ctx, f["gall"], "the Gall")} #{found} #{place}"
  end

  defp fact_text(%{"kind" => "alias"} = f, ctx),
    do: "#{written_ref(ctx, f["gall"], "the Gall")} is also called “#{f["name"]}”"

  defp fact_text(%{"kind" => "description"} = f, ctx),
    do: "the description of #{written_ref(ctx, f["gall"], "the Gall")}"

  defp fact_text(%{"kind" => "qualifier"} = f, _ctx),
    do: "the #{humanize(f["qualifier"] || "qualifier")} is #{value_of(f["value"])}"

  defp fact_text(_fact, _ctx), do: nil

  defp act_text(act, ctx), do: "#{cap(ctx.who)} #{act_claim(act, act["stance"] == "deny", ctx)}"

  # What the act says, after the Source's name.
  defp act_claim(%{"kind" => "placement"} = act, deny?, ctx) do
    t = written_ref(ctx, act["taxon"], "a taxon")
    p = written_ref(ctx, act["parent"], "another taxon")
    if deny?, do: "denies that #{t} belongs under #{p}", else: "places #{t} under #{p}"
  end

  defp act_claim(%{"kind" => "name"} = act, deny?, ctx) do
    t = written_ref(ctx, act["taxon"], "a taxon")
    if deny?, do: "denies the name #{t}", else: "names #{t}"
  end

  defp act_claim(%{"kind" => "synonymy"} = act, deny?, ctx) do
    n = written_ref(ctx, act["name"], "a name")
    a = written_ref(ctx, act["accepted"], "another taxon")

    if deny?,
      do: "denies that #{n} is a synonym of #{a}",
      else: "treats #{n} as a synonym of #{a}"
  end

  defp act_claim(%{"kind" => "split"} = act, _deny?, ctx) do
    into = act["into"] |> List.wrap() |> Enum.map(&written_ref(ctx, &1, "a taxon"))
    "splits #{written_ref(ctx, act["taxon"], "a taxon")} into #{and_list(into)}"
  end

  defp act_claim(%{"kind" => "common_name"} = act, deny?, ctx) do
    t = written_ref(ctx, act["taxon"], "a taxon")
    name = act["common_name"]
    if deny?, do: "denies that #{t} is called “#{name}”", else: "calls #{t} “#{name}”"
  end

  defp act_claim(_act, _deny?, _ctx), do: "states a taxonomic act"

  # -- taxonomic statements to accept (`Gallformers.Import.TaxonomyQueue`) --------

  # A statement's taxa in the Source's words (`subject["written"]`, by
  # role), else by the tree's name.
  defp stated_name(s, role, id_key, ctx) do
    case get_in(s, ["written", role]) do
      name when is_binary(name) -> name
      _ -> s[id_key] && name(ctx, :taxa, s[id_key])
    end
  end

  defp stated_into(s, ctx) do
    case get_in(s, ["written", "into"]) do
      [_ | _] = names -> names
      _ -> Enum.map(List.wrap(s["into_taxon_ids"]), &name(ctx, :taxa, &1))
    end
  end

  # What the statement says, after the Source's name.
  defp statement_claim(%{"kind" => kind, "stance" => stance} = s, ctx),
    do: claim(kind, stance == "deny", s, ctx)

  defp statement_claim(_s, _ctx), do: "states a taxonomic act"

  defp claim("placement", deny?, s, ctx) do
    {t, p} = {stated_taxon(s, ctx), stated_parent(s, ctx)}
    if deny?, do: "denies that #{t} belongs under #{p}", else: "places #{t} under #{p}"
  end

  defp claim("name", true, s, _ctx), do: "denies the name #{stated_full_name(s)}"

  defp claim("name", false, s, _ctx),
    do: "names it #{stated_full_name(s)}#{s["rank"] && " at rank #{s["rank"]}"}"

  defp claim("synonymy", deny?, s, ctx) do
    {n, a} = {stated_synonym(s, ctx), stated_accepted(s, ctx)}

    if deny?,
      do: "denies that #{n} is a synonym of #{a}",
      else: "treats #{n} as a synonym of #{a}"
  end

  defp claim("split", _deny?, s, ctx),
    do: "splits #{stated_taxon(s, ctx)} into #{and_list(stated_into(s, ctx)) || "other taxa"}"

  defp claim("common_name", true, s, ctx),
    do: "denies that #{stated_taxon(s, ctx)} is called “#{s["common_name"]}”"

  defp claim("common_name", false, s, ctx),
    do: "calls #{stated_taxon(s, ctx)} “#{s["common_name"]}”"

  defp claim(_kind, _deny?, _s, _ctx), do: "states a taxonomic act"

  # The statement in a few words, for its row.
  defp statement_written(%{"kind" => kind, "stance" => stance} = s, ctx) do
    written = written_act(kind, s, ctx)
    if stance == "deny", do: "Not: #{written}", else: written
  end

  defp statement_written(_s, _ctx), do: "A taxonomic act"

  defp written_act("placement", s, ctx),
    do: "#{stated_taxon(s, ctx)} under #{stated_parent(s, ctx)}"

  defp written_act("name", s, _ctx), do: stated_full_name(s)

  defp written_act("synonymy", s, ctx),
    do: "#{stated_synonym(s, ctx)}, a synonym of #{stated_accepted(s, ctx)}"

  defp written_act("split", s, ctx),
    do: "#{stated_taxon(s, ctx)}, split into #{and_list(stated_into(s, ctx)) || "other taxa"}"

  defp written_act("common_name", s, ctx), do: "#{stated_taxon(s, ctx)}: “#{s["common_name"]}”"
  defp written_act(_kind, _s, _ctx), do: "A taxonomic act"

  defp stated_taxon(s, ctx), do: stated_name(s, "taxon", "taxon_id", ctx) || "a taxon"
  defp stated_parent(s, ctx), do: stated_name(s, "parent", "parent_id", ctx) || "the root"

  defp stated_accepted(s, ctx),
    do: stated_name(s, "accepted", "accepted_taxon_id", ctx) || "another taxon"

  defp stated_synonym(s, ctx), do: s["name"] || stated_name(s, "name", nil, ctx) || "a name"

  defp stated_full_name(s),
    do: Enum.join(Enum.reject([s["name"], s["authorship"]], &is_nil/1), " ")

  # What accepting does to the tree.
  defp accept_effect(%{"stance" => "deny"}, _ctx),
    do:
      "The statement counts: the tree drops what it denies once no newer accepted " <>
        "statement holds it."

  defp accept_effect(%{"kind" => "placement"} = s, ctx),
    do:
      "The tree moves #{stated_taxon(s, ctx)} under #{stated_parent(s, ctx)}; the Galls " <>
        "named after it get rename proposals."

  defp accept_effect(%{"kind" => "name"} = s, _ctx),
    do:
      "The tree names it #{s["name"]}#{s["authorship"] && " " <> s["authorship"]}; an old " <>
        "name stays as a synonym, and the Galls named after it get rename proposals."

  defp accept_effect(%{"kind" => "synonymy"} = s, ctx),
    do:
      "#{stated_synonym(s, ctx)} becomes a synonym of #{stated_accepted(s, ctx)}. " <>
        "If it is a species of its own today, it is merged in: its Galls follow, with rename " <>
        "proposals."

  defp accept_effect(%{"kind" => "split"} = s, ctx),
    do:
      "The tree splits #{stated_taxon(s, ctx)}: each Gall on it then asks " <>
        "which taxon induces it."

  defp accept_effect(%{"kind" => "common_name"} = s, ctx),
    do:
      "The tree gives #{stated_taxon(s, ctx)} the common name " <>
        "“#{s["common_name"]}”."

  defp accept_effect(_s, _ctx), do: "The tree follows the statement."

  # A batch ref in the Source's words; never the ref itself.
  defp written_ref(ctx, ref, fallback) when is_binary(ref) do
    case Map.get(ctx.written, ref) do
      nil -> if ref =~ ~r/\A[tgfa]\d+\z/, do: fallback, else: ref
      written -> written
    end
  end

  defp written_ref(_ctx, _ref, fallback), do: fallback

  defp value_of(%{"value" => value}), do: to_string(value)
  defp value_of(value) when is_binary(value), do: value
  defp value_of(_value), do: ""

  # -- shared pieces -------------------------------------------------------------

  defp proposal(label, why, decision, opts \\ []) do
    %{
      label: label,
      why: why,
      firm: Keyword.get(opts, :firm, true),
      decision: decision,
      pending: Keyword.get(opts, :pending, false),
      check: Keyword.get(opts, :check)
    }
  end

  # The choice that is the proposal, marked so; not a Gall only to check
  # (tagged as the best match, or with what it conflicts on, instead).
  defp mark(choices, %{check: check}) when is_binary(check), do: choices

  defp mark(choices, proposal) do
    case Enum.find_index(choices, &((&1.decision || &1.base) == proposal.decision)) do
      nil -> choices
      i -> List.update_at(choices, i, &%{&1 | proposed: true})
    end
  end

  defp covers(_id, _item, %{covers: n}) when is_integer(n) and n > 0, do: n

  defp covers(id, item, _ctx) do
    cond do
      covered_galls(item) != [] -> length(covered_galls(item))
      item.kind == :dispute -> 1 + length(List.wrap(item.subject["also"]))
      id == :generation_pairs -> 2
      true -> 1
    end
  end

  # What a choice adds when one answer covers several Galls.
  defp covers_suffix(n, :host) when n > 1, do: "; settles the Host of all #{n} Galls"
  defp covers_suffix(_n, _how), do: ""

  # The Galls `subject["covers"]` names, once each: {ref, name as written}.
  defp covered_galls(item) do
    item.subject
    |> Map.get("covers")
    |> List.wrap()
    |> Enum.filter(&(is_map(&1) and is_binary(&1["gall"])))
    |> Enum.uniq_by(& &1["gall"])
    |> Enum.map(&{&1["gall"], &1["name_as_written"]})
  end

  defp covered_names(item) do
    item |> covered_galls() |> Enum.map(&elem(&1, 1)) |> Enum.filter(& &1) |> and_list()
  end

  # The producer's note on why it set the term aside, if any.
  defp producer_note(item) do
    item.subject
    |> Map.get("covers")
    |> List.wrap()
    |> Enum.find_value(&(is_map(&1) and is_binary(&1["note"]) and &1["note"]))
  end

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  defp and_list([]), do: nil
  defp and_list([one]), do: one
  defp and_list(list), do: Enum.join(Enum.drop(list, -1), ", ") <> " and " <> List.last(list)

  defp technical(item, ctx) do
    statement = ctx.statement || %{}

    [
      item.kind && Atom.to_string(item.kind),
      item.statement_ref,
      statement[:method] && "method #{statement[:method]}",
      match?([_ | _], statement[:flags]) && Enum.join(statement[:flags], ", "),
      item.reason
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" · ")
  end

  defp written_name(item),
    do: item.subject["name_reading"] || item.subject["name_as_written"] || "this name"

  defp printed_as(item) do
    reading = item.subject["name_reading"]
    printed = item.subject["name_as_written"]
    if reading && printed && reading != printed, do: "printed as “#{printed}”"
  end

  defp rank_noun(item) do
    case item.subject["rank"] do
      rank when is_binary(rank) and rank != "" -> rank
      _ -> "taxon"
    end
  end

  defp generation_label(name, generation) when is_binary(generation),
    do: "#{name} (#{generation})"

  defp generation_label(name, _generation), do: name

  defp trait_name(nil), do: "Trait"
  defp trait_name(trait), do: humanize(trait)

  defp humanize(text), do: String.replace(text, "_", " ")

  # An old name printed in capitals, as a name reads ("ANDRICUS
  # IMBRECARIÆ" → "Andricus imbrecariae").
  defp title(name) do
    if name == String.upcase(name) do
      name |> String.downcase() |> String.replace("æ", "ae") |> cap()
    else
      name
    end
  end

  defp who(source) when is_binary(source) and source != "", do: source
  defp who(_source), do: "the Source"

  defp poss(who), do: who <> "'s"

  defp uncap(text) do
    {first, rest} = String.split_at(text, 1)
    String.downcase(first) <> rest
  end

  defp cap(text) do
    {first, rest} = String.split_at(text, 1)
    String.upcase(first) <> rest
  end
end
