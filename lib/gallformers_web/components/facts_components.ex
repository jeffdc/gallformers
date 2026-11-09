defmodule GallformersWeb.FactsComponents do
  @moduledoc """
  A Source's Facts, grouped by Gall then by category (matter `f14c`,
  item 4; the shape is `Gallformers.Import.FactsView`'s), one view for
  three uses:

    * `:preview` — the review's Facts page
      (`GallformersWeb.Admin.ReviewLive.Facts`): what approving would
      write, each Fact marked new, held, in conflict, waiting on a question
      (a link to it) or dropped, with the curator's edits and, when
      `editable`, a small menu of edits on each;
    * `:applied` — the same page once the Source is approved: its applied
      Facts, read-only, each Fact's standing marked when not current; and,
      with `corrections`, the admin Source page
      (`GallformersWeb.Admin.SourceLive.Facts`): a small menu of
      corrections on each Fact that can be corrected (withdraw the
      Source's statement, or move it to another Host, Trait value, parent
      or accepted taxon), its form in the `editor` slot;
    * `:public` — the public Source page (`GallformersWeb.SourceLive`):
      as `:applied`, linking only to public pages; and the public Gall
      page (`GallformersWeb.GallLive`, `Gallformers.Import.facts_for_gall/1`),
      one Gall without its header (`gall_header={false}`), each Fact with
      the Sources stating it (an entry's `sources`) and the Facts no longer
      current collapsed as its history (`history`).

  Each Fact is one tight row: its value in Gallformers' terms, the
  Source's words muted beside it, its mark, and its quotes behind a toggle
  (with "Show the passage" where the page gives `on_passage`). A Gall's
  categories sit in two columns on a wide screen.

  Also here: a Fact-backed value on a page (`fact_ref/1`) and who says so
  about it (`fact_inspector/1`; matter `87a1`); the line saying whether the
  Source is ready to approve
  (`facts_readiness/1`), the counts as filter chips (`facts_filter/1`),
  the taxonomy changes (`facts_taxonomy/1`): once applied, each
  taxonomic statement with the curator's mark (accepted, declined with the
  reason, or awaiting a curator; matter `f923`), and the form of an edit
  or correction open on a Fact (`fact_editor/1`).
  """
  use Phoenix.Component

  import GallformersWeb.ActionComponents, only: [button: 1]
  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.DataComponents, only: [chip: 1, fact_list: 1]
  import GallformersWeb.DataDisplayComponents, only: [taxon_name: 1]
  import GallformersWeb.DomainComponents, only: [source_quote: 1]
  import GallformersWeb.FormComponents, only: [typeahead: 1]

  import GallformersWeb.ReviewComponents,
    only: [review_quote: 1, review_passage: 1, review_value_list: 1]

  alias Gallformers.Catalog.RelationshipTypes
  alias GallformersWeb.FactKey
  alias GallformersWeb.TaxonomyURL
  alias Phoenix.LiveView.JS

  @category_titles [
    inducer: "Inducer",
    hosts: "Hosts",
    traits: "Traits",
    range: "Range",
    descriptions: "Descriptions",
    aliases: "Aliases",
    other: "Other"
  ]

  @statuses [:new, :held, :conflict, :waiting, :dropped]

  # The standings of a Fact no longer current, as its history counts them.
  @past_order [:withdrawn, :superseded, :retracted, :unsupported]

  @status_text %{
    new: "new",
    held: "held",
    conflict: "conflict",
    waiting: "waiting",
    dropped: "dropped"
  }

  @status_title %{
    new: "Gallformers holds no such Fact: approving adds it",
    held: "Gallformers holds this Fact already: approving adds this Source to it",
    conflict: "Gallformers holds the contrary",
    waiting: "A question holds it: answered, it is written",
    dropped: "Approving does not write it"
  }

  @filter_text %{
    new: "New",
    held: "Already held",
    conflict: "Conflicts",
    waiting: "Waiting",
    dropped: "Dropped"
  }

  # -- keys ------------------------------------------------------------------------

  @doc """
  A Fact entry's key, unique on the page and safe in a DOM id: its batch
  and statement ref (`"b62-f3"`), a Trait Fact's with its value
  (`"b62-f6-globular"`, one entry per value), else its Fact ID (`"f123"`).
  """
  @spec fact_key(map()) :: String.t()
  def fact_key(%{kind: :trait, ref: ref, batch_id: batch_id, value: value})
      when is_binary(ref) and is_integer(batch_id) do
    statement = ref |> String.split("+") |> hd()
    "b#{batch_id}-#{dom(statement)}-#{dom(value[:value] || value[:suggested] || "none")}"
  end

  def fact_key(%{ref: ref, batch_id: batch_id}) when is_binary(ref) and is_integer(batch_id),
    do: "b#{batch_id}-#{dom(ref)}"

  def fact_key(%{fact_id: id}) when is_integer(id), do: "f#{id}"
  def fact_key(%{ref: ref}) when is_binary(ref), do: "r-#{dom(ref)}"

  @doc ~s(The key of the passage around a quote of a Fact of batch `batch_id`: `"<batch>|<item>"`.)
  @spec passage_key(integer() | nil, String.t() | nil) :: String.t() | nil
  def passage_key(batch_id, item) when is_integer(batch_id) and is_binary(item),
    do: "#{batch_id}|#{item}"

  def passage_key(_batch_id, _item), do: nil

  defp dom(value), do: value |> to_string() |> String.replace(~r/[^A-Za-z0-9_-]+/, "-")

  @doc "Every Fact entry of `galls` (their `facts`, Traits flattened)."
  @spec entries([map()]) :: [map()]
  def entries(galls) do
    for g <- galls, {_category, list} <- g.facts, e <- flatten(list), do: e
  end

  defp flatten(list) when is_list(list), do: list
  defp flatten(by_trait) when is_map(by_trait), do: by_trait |> Map.values() |> List.flatten()

  # -- the readiness line and the counts ---------------------------------------------

  @doc """
  Whether the Source is ready to approve: "Ready to approve: this is what
  approving writes." or "Not ready to approve: N questions still hold it",
  with the steps they are in (`steps`: `%{title, path, n}`), each a link.
  """
  attr :id, :string, default: "facts-readiness"
  attr :ready, :boolean, required: true
  attr :count, :integer, default: 0, doc: "the questions holding approval"
  attr :steps, :list, default: [], doc: "`%{title, path, n}`: where those questions are"
  attr :blocked, :list, default: [], doc: "batches held by an unsettled Host name"

  def facts_readiness(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "mt-4 rounded-ctl border px-3 py-2 text-meta",
        if(@ready,
          do: "border-line bg-ok-bg text-ok",
          else: "border-line bg-warn-bg text-warn"
        )
      ]}
    >
      <%= if @ready do %>
        <span class="font-semibold">Ready to approve:</span> this is what approving writes.
      <% else %>
        <span class="font-semibold">Not ready to approve:</span>
        {questions_text(@count)} still {if @count == 1, do: "holds", else: "hold"} it<span :if={
          @steps != []
        }>
          (<span :for={{s, i} <- Enum.with_index(@steps)}><span :if={i > 0}>, </span><.link
              navigate={s.path}
              class="underline hover:text-brand"
            >{s.title} {s.n}</.link></span>)</span>. What waits on them is marked waiting.
      <% end %>
    </div>
    """
  end

  defp questions_text(1), do: "1 question"
  defp questions_text(n), do: "#{n} questions"

  @doc """
  The counts (`%{new, held, conflict, waiting, dropped}`) as filter chips,
  "All" first; the chip of `filter` pressed. Each sends `on_filter` with
  `phx-value-status` (`"all"` for All).
  """
  attr :id, :string, default: "facts-filter"
  attr :counts, :map, required: true
  attr :filter, :atom, default: nil
  attr :on_filter, :any, required: true

  def facts_filter(assigns) do
    assigns =
      assign(assigns,
        total: assigns.counts |> Map.take(@statuses) |> Map.values() |> Enum.sum(),
        statuses: @statuses
      )

    ~H"""
    <div id={@id} class="mt-3 flex flex-wrap items-center gap-1.5" role="group" aria-label="Show">
      <button
        id={"#{@id}-all"}
        type="button"
        phx-click={@on_filter}
        phx-value-status="all"
        aria-pressed={to_string(@filter == nil)}
        class={["gf-pill text-caption px-2 py-0.5", pill_class(@filter == nil)]}
      >
        All <span class="tabular-nums">{@total}</span>
      </button>
      <button
        :for={status <- @statuses}
        id={"#{@id}-#{status}"}
        type="button"
        phx-click={@on_filter}
        phx-value-status={status}
        aria-pressed={to_string(@filter == status)}
        class={[
          "gf-pill text-caption px-2 py-0.5 inline-flex items-center gap-1",
          pill_class(@filter == status),
          Map.get(@counts, status, 0) == 0 && "opacity-60"
        ]}
      >
        <span class={["inline-block size-2 rounded-full", dot_class(status)]} aria-hidden="true">
        </span>
        {filter_text(status)} <span class="tabular-nums">{Map.get(@counts, status, 0)}</span>
      </button>
    </div>
    """
  end

  defp pill_class(true), do: "gf-pill-selected"
  defp pill_class(false), do: "gf-pill-unselected"

  defp dot_class(:new), do: "bg-ok"
  defp dot_class(:held), do: "bg-muted"
  defp dot_class(:conflict), do: "bg-danger"
  defp dot_class(:waiting), do: "bg-warn"
  defp dot_class(:dropped), do: "border border-line-strong"

  defp filter_text(status), do: Map.fetch!(@filter_text, status)

  # -- the Galls -----------------------------------------------------------------------

  @doc """
  The Facts, grouped by Gall then category.

  `questions` maps a question's ID to `%{title, path}` (its step and its
  row there), for the waiting marks. `editing` is the key (`fact_key/1`)
  of the Fact whose `editor` slot shows under it. `passages` holds the
  passages loaded (`passage_key/2` to blocks), `on_passage` loads one.
  """
  attr :id, :string, default: "facts"
  attr :galls, :list, required: true
  attr :mode, :atom, default: :preview, values: [:preview, :applied, :public]
  attr :editable, :boolean, default: false
  attr :filter, :atom, default: nil, doc: "a status to show only"
  attr :questions, :map, default: %{}
  attr :editing, :string, default: nil
  attr :passages, :map, default: %{}
  attr :on_passage, :any, default: nil
  attr :empty, :string, default: "No Facts."
  attr :gall_header, :boolean, default: true, doc: "each Gall's name over its Facts"

  attr :history, :boolean,
    default: false,
    doc: "the Facts not current (withdrawn, superseded, retracted) collapsed under the rest"

  attr :corrections, :boolean,
    default: false,
    doc: "(`:applied`) a menu of corrections on each Fact that can be corrected"

  attr :target, :any, default: nil, doc: "where the menus send their events (`@myself`)"

  attr :refs, :map,
    default: %{},
    doc:
      "Facts to open in the inspector, by Fact ID (`Gallformers.Import.gall_facts/1`'s): " <>
        "each such row's value is a `fact_ref` sending `on_select`"

  attr :on_select, :string, default: nil
  attr :selected, :any, default: nil

  slot :editor, doc: "the open edit's form, given the entry"

  def facts_view(assigns) do
    shown =
      for g <- assigns.galls,
          g = filter_gall(g, assigns.filter),
          g.facts != %{} or (assigns.filter == nil and assigns.mode == :preview),
          do: g

    assigns = assign(assigns, shown: shown)

    ~H"""
    <div id={@id} class="grid gap-3">
      <p :if={@shown == []} class="text-meta italic text-muted" data-role="empty">{@empty}</p>
      <.facts_gall
        :for={g <- @shown}
        id={"#{@id}-gall-#{dom(g.key)}"}
        gall={g}
        mode={@mode}
        editable={@editable}
        questions={@questions}
        editing={@editing}
        passages={@passages}
        on_passage={@on_passage}
        editor={@editor}
        header={@gall_header}
        history={@history}
        corrections={@corrections}
        target={@target}
        refs={@refs}
        on_select={@on_select}
        selected={@selected}
      />
    </div>
    """
  end

  # The Gall with only the Facts shown, its empty categories gone.
  defp filter_gall(g, filter) do
    facts =
      for {category, list} <- g.facts,
          list = keep(list, filter),
          list not in [[], %{}],
          into: %{},
          do: {category, list}

    %{g | facts: facts}
  end

  defp keep(list, filter) when is_list(list), do: Enum.filter(list, &shown?(&1, filter))

  defp keep(by_trait, filter) when is_map(by_trait) do
    for {trait, list} <- by_trait,
        list = keep(list, filter),
        list != [],
        into: %{},
        do: {trait, list}
  end

  defp shown?(_entry, nil), do: true
  defp shown?(entry, filter), do: entry.status == filter

  attr :id, :string, required: true
  attr :gall, :map, required: true
  attr :mode, :atom, required: true
  attr :editable, :boolean, required: true
  attr :questions, :map, required: true
  attr :editing, :string, default: nil
  attr :passages, :map, required: true
  attr :on_passage, :any, default: nil
  attr :editor, :list, default: []
  attr :header, :boolean, default: true
  attr :history, :boolean, default: false
  attr :corrections, :boolean, default: false
  attr :target, :any, default: nil
  attr :refs, :map, default: %{}
  attr :on_select, :string, default: nil
  attr :selected, :any, default: nil

  defp facts_gall(assigns) do
    {facts, past} =
      if assigns.history,
        do: split_history(assigns.gall.facts),
        else: {assigns.gall.facts, %{}}

    past_entries = past |> Map.values() |> Enum.flat_map(&flatten/1)

    assigns =
      assign(assigns,
        categories: categories(facts),
        past: categories(past),
        past_counts:
          past_entries
          |> Enum.frequencies_by(& &1.standing)
          |> Enum.sort_by(fn {standing, _n} ->
            Enum.find_index(@past_order, &(&1 == standing))
          end)
      )

    ~H"""
    <section id={@id} class="gf-card overflow-hidden" data-role="facts-gall">
      <header :if={@header} class="px-3 py-2 bg-surface-2 border-b border-line">
        <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <h3 class="gf-facts-title text-ink">
            <%= cond do %>
              <% @mode == :public and is_integer(@gall.gall_id) -> %>
                <.link navigate={"/gall/#{@gall.gall_id}"} class="hover:underline">
                  <.taxon_name name={gall_name(@gall)} />
                </.link>
              <% @gall.name -> %>
                <.taxon_name name={@gall.name} />
              <% true -> %>
                <span>{gall_name(@gall)}</span>
            <% end %>
          </h3>
          <span :if={@mode == :preview and @gall.new} class="gf-mark gf-mark-new">new Gall</span>
          <.link
            :if={@mode == :preview and is_integer(@gall.gall_id)}
            href={"/gall/#{@gall.gall_id}"}
            target="_blank"
            rel="noopener"
            class="text-caption text-brand hover:underline"
          >
            matches {@gall.name || "Gall #{@gall.gall_id}"} ↗
          </.link>
        </div>
        <p
          :if={@gall.name_as_written && @gall.name_as_written != @gall.name}
          class="text-caption text-muted"
        >
          The Source: “{@gall.name_as_written}”
        </p>
        <p :if={@mode == :preview and @gall.status == :waiting} class="mt-0.5 text-caption text-warn">
          <span class="gf-mark gf-mark-waiting">waiting</span>
          Which Gall this is waits on
          <.question_link
            id={"#{@id}-question"}
            question={@gall.question}
            questions={@questions}
          />; its Facts wait with it.
        </p>
        <p :if={@mode == :preview and @gall.status == :dropped} class="mt-0.5 text-caption text-ink-2">
          <span class="gf-mark gf-mark-dropped">dropped</span>
          Left out{if @gall.why, do: ": #{@gall.why}"}; its Facts are not written.
        </p>
      </header>
      <div class="px-3 py-2 lg:columns-2 lg:gap-6" data-role="current">
        <.facts_category
          :for={{category, title, list} <- @categories}
          category={category}
          title={title}
          list={list}
          mode={@mode}
          editable={@editable}
          questions={@questions}
          editing={@editing}
          passages={@passages}
          on_passage={@on_passage}
          editor={@editor}
          corrections={@corrections}
          target={@target}
        />
        <p :if={@categories == []} class="text-caption italic text-muted">
          {if @past == [], do: "No Facts.", else: "No current Facts."}
        </p>
      </div>
      <details :if={@past != []} data-role="history" class="border-t border-line px-3 py-2">
        <summary class="cursor-pointer text-meta text-link">
          History: {Enum.map_join(@past_counts, ", ", fn {standing, n} -> "#{n} #{standing}" end)}
        </summary>
        <div class="mt-1 lg:columns-2 lg:gap-6">
          <.facts_category
            :for={{category, title, list} <- @past}
            category={category}
            title={title}
            list={list}
            mode={@mode}
            editable={false}
            questions={@questions}
            passages={@passages}
            on_passage={@on_passage}
            refs={@refs}
            on_select={@on_select}
            selected={@selected}
          />
        </div>
      </details>
    </section>
    """
  end

  # The categories that have Facts, in the page's order.
  defp categories(facts) do
    for {category, title} <- @category_titles,
        list = Map.get(facts, category),
        list not in [nil, [], %{}],
        do: {category, title, list}
  end

  # The Facts current (or not yet written) and those no longer current.
  defp split_history(facts) do
    current = fn e -> e.standing in [nil, :current] end

    split =
      for {category, list} <- facts, into: %{} do
        {category, split_list(list, current)}
      end

    {Map.new(split, fn {c, {now, _past}} -> {c, now} end),
     Map.new(split, fn {c, {_now, past}} -> {c, past} end)}
  end

  defp split_list(list, current) when is_list(list), do: Enum.split_with(list, current)

  defp split_list(by_trait, current) when is_map(by_trait) do
    split = for {trait, list} <- by_trait, do: {trait, Enum.split_with(list, current)}

    {for({trait, {now, _past}} <- split, now != [], into: %{}, do: {trait, now}),
     for({trait, {_now, past}} <- split, past != [], into: %{}, do: {trait, past})}
  end

  # One category of a Gall's Facts: its title and count, then its rows
  # (Traits by Trait).
  attr :category, :atom, required: true
  attr :title, :string, required: true
  attr :list, :any, required: true
  attr :mode, :atom, required: true
  attr :editable, :boolean, required: true
  attr :questions, :map, required: true
  attr :editing, :string, default: nil
  attr :passages, :map, required: true
  attr :on_passage, :any, default: nil
  attr :editor, :list, default: []
  attr :corrections, :boolean, default: false
  attr :target, :any, default: nil
  attr :refs, :map, default: %{}
  attr :on_select, :string, default: nil
  attr :selected, :any, default: nil

  defp facts_category(assigns) do
    ~H"""
    <div class="break-inside-avoid mb-2" data-category={@category}>
      <h4 class="gf-facts-category">
        {@title} <span class="font-normal tabular-nums">{count(@list)}</span>
      </h4>
      <%= if @category == :traits do %>
        <div
          :for={{trait, rows} <- Enum.sort_by(@list, fn {t, _} -> to_string(t) end)}
          class="flex flex-col gap-x-2 border-t border-line first-of-type:border-t-0 sm:flex-row"
          data-trait={trait}
        >
          <span class="pt-1 text-caption text-ink-2 sm:w-32 sm:shrink-0 sm:py-1">
            {humanize(trait)}
          </span>
          <ul class="min-w-0 flex-1 divide-y divide-line">
            <.fact_row
              :for={e <- rows}
              entry={e}
              mode={@mode}
              editable={@editable}
              questions={@questions}
              editing={@editing}
              passages={@passages}
              on_passage={@on_passage}
              editor={@editor}
              corrections={@corrections}
              target={@target}
              refs={@refs}
              on_select={@on_select}
              selected={@selected}
            />
          </ul>
        </div>
      <% else %>
        <ul class="divide-y divide-line">
          <.fact_row
            :for={e <- @list}
            entry={e}
            mode={@mode}
            editable={@editable}
            questions={@questions}
            editing={@editing}
            passages={@passages}
            on_passage={@on_passage}
            editor={@editor}
            corrections={@corrections}
            target={@target}
            refs={@refs}
            on_select={@on_select}
            selected={@selected}
          />
        </ul>
      <% end %>
    </div>
    """
  end

  defp gall_name(%{name: name}) when is_binary(name), do: name
  defp gall_name(%{name_as_written: written}) when is_binary(written), do: written
  defp gall_name(%{gall_id: id}) when is_integer(id), do: "Gall #{id}"
  defp gall_name(%{ref: ref}), do: "Gall #{ref}"

  defp count(list) when is_list(list), do: length(list)
  defp count(by_trait), do: by_trait |> Map.values() |> List.flatten() |> length()

  # -- the taxonomy changes ----------------------------------------------------------------

  @doc """
  The taxonomy changes: the taxa approving creates (each under its parent,
  or unplaced) and the taxonomic acts, each a Fact row. Applied (`:applied`,
  `:public`), each act carries its `decision`
  (`Gallformers.Import.FactsView.act_entries/1`): accepted, declined (with
  the reason) or awaiting a curator, who and when.
  """
  attr :id, :string, default: "facts-taxonomy"
  attr :taxonomy, :map, required: true, doc: "`%{new_taxa, acts}`"
  attr :mode, :atom, default: :preview
  attr :editable, :boolean, default: false
  attr :filter, :atom, default: nil
  attr :questions, :map, default: %{}
  attr :editing, :string, default: nil
  attr :passages, :map, default: %{}
  attr :on_passage, :any, default: nil

  attr :corrections, :boolean,
    default: false,
    doc: "(`:applied`) a menu of corrections on each statement"

  attr :target, :any, default: nil, doc: "where the menus send their events (`@myself`)"
  slot :editor

  def facts_taxonomy(assigns) do
    assigns = assign(assigns, acts: keep(assigns.taxonomy.acts, assigns.filter))

    ~H"""
    <section
      :if={@taxonomy.new_taxa != [] or @taxonomy.acts != []}
      id={@id}
      class="gf-card overflow-hidden"
    >
      <header class="px-3 py-2 bg-surface-2 border-b border-line">
        <h3 class="gf-facts-title text-ink">Taxonomy changes</h3>
        <p class="text-caption text-muted">
          {if @mode == :preview,
            do: "The taxa approving adds to the tree, and what the Source says of names.",
            else: "What the Source says of names, and whether Gallformers follows it."}
        </p>
      </header>
      <div class="px-3 py-2 lg:columns-2 lg:gap-6">
        <div :if={@taxonomy.new_taxa != []} class="break-inside-avoid mb-2" data-category="new_taxa">
          <h4 class="gf-facts-category">
            New taxa <span class="font-normal tabular-nums">{length(@taxonomy.new_taxa)}</span>
          </h4>
          <ul class="divide-y divide-line">
            <li
              :for={t <- @taxonomy.new_taxa}
              id={"#{@id}-taxon-#{dom("#{t.batch_id}-#{t.ref}")}"}
              class="flex flex-wrap items-baseline gap-x-2 py-1 text-meta"
            >
              <span class="gf-mark gf-mark-new">new</span>
              <span class="font-medium text-ink">
                <.taxon_name name={t.name || t.name_as_written || "?"} rank={rank(t.rank)} />
              </span>
              <span :if={t.rank} class="text-caption text-muted">{t.rank}</span>
              <%= cond do %>
                <% t.parent -> %>
                  <span class="text-caption text-ink-2">
                    under <.taxon_name name={t.parent.name} rank={rank(t.parent.rank)} />
                    <span :if={t.parent[:new]}>
                      (new)
                    </span>
                  </span>
                <% t.unplaced -> %>
                  <span class="text-caption text-warn">unplaced in the tree</span>
                <% true -> %>
              <% end %>
              <span
                :if={t.name_as_written && t.name_as_written != t.name}
                class="text-caption text-muted"
              >
                “{t.name_as_written}”
              </span>
            </li>
          </ul>
        </div>
        <div :if={@acts != []} class="break-inside-avoid mb-2" data-category="acts">
          <h4 class="gf-facts-category">
            Acts <span class="font-normal tabular-nums">{length(@acts)}</span>
          </h4>
          <ul class="divide-y divide-line">
            <.fact_row
              :for={e <- @acts}
              entry={e}
              mode={@mode}
              editable={@editable}
              questions={@questions}
              editing={@editing}
              passages={@passages}
              on_passage={@on_passage}
              editor={@editor}
              corrections={@corrections}
              target={@target}
            />
          </ul>
        </div>
      </div>
    </section>
    """
  end

  # -- an edit's form -----------------------------------------------------------------------

  @doc """
  The form of an edit open on a Fact, in the `editor` slot of
  `facts_view/1` and `facts_taxonomy/1`: the review Facts page's edits
  (Drop, Change Host, Change value, Note) and the admin Source page's
  corrections (Withdraw, Change Host, value, parent, accepted taxon). Its
  title says what the edit does; then, as the edit needs, a taxon search
  (`search_label` given: a `typeahead`, its results grouped by `:group`,
  each with its `meta` muted), the Trait's values to tick (`values` given:
  `review_value_list`), the caller's own fields (the inner block), the
  note, the refusal (`error`), and Save and Cancel (`edit_cancel`).

  `pick` holds the open edit's choices (`query`, `results`, `selected`,
  `values`, `note`). Parts' ids are `<id>-note`, `<id>-values`, `<id>-error`,
  `<id>-save`, `<id>-cancel`, and the search's `search_id` (default
  `<id>-taxon`).
  """
  attr :id, :string, required: true
  attr :title, :string, required: true, doc: "what the edit does, in words"
  attr :on_submit, :string, required: true
  attr :target, :any, default: nil, doc: "where the form sends its events (`@myself`)"
  attr :pick, :map, required: true, doc: "`%{query, results, selected, values, note}`"
  attr :search_label, :string, default: nil, doc: "the taxon search's label; nil for none"
  attr :search_id, :string, default: nil
  attr :search_event, :string, default: "search_taxon"
  attr :select_event, :string, default: "select_taxon"
  attr :clear_event, :string, default: "clear_taxon"
  attr :values, :list, default: nil, doc: "the Trait's `{value, definition}` pairs; nil for none"
  attr :on_toggle, :string, default: "toggle_value"
  attr :note_label, :string, required: true
  attr :error, :string, default: nil
  attr :save_text, :string, required: true
  attr :save_variant, :string, default: "primary"
  slot :inner_block, doc: "the edit's own fields, before the note"

  def fact_editor(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={@id}
      phx-submit={@on_submit}
      phx-target={@target}
      class="grid gap-2 rounded-panel border border-line bg-surface-2 p-2"
    >
      <p class="text-caption font-semibold text-ink-2">{@title}</p>
      <.typeahead
        :if={@search_label}
        id={@search_id || "#{@id}-taxon"}
        label={@search_label}
        placeholder="Type a name…"
        search_event={@search_event}
        select_event={@select_event}
        clear_event={@clear_event}
        query={@pick.query}
        results={@pick.results}
        selected={@pick.selected}
        display_fn={& &1.name}
        group_key={:group}
        target={@target}
      >
        <:result :let={result}>
          <span class="italic">{result.name}</span>
          <span :if={result.meta != ""} class="text-caption text-muted ml-1">{result.meta}</span>
        </:result>
      </.typeahead>
      <.review_value_list
        :if={@values}
        id={"#{@id}-values"}
        type="checkbox"
        values={@values}
        selected={@pick.values}
        on_pick={@on_toggle}
        target={@target}
      />
      {render_slot(@inner_block)}
      <div class="grid gap-0.5">
        <label for={"#{@id}-note"} class="gf-label-sm">{@note_label}</label>
        <textarea id={"#{@id}-note"} name="note" rows="2" class="gf-textarea text-ui">{@pick.note}</textarea>
      </div>
      <p :if={@error} id={"#{@id}-error"} class="text-caption text-danger">{@error}</p>
      <div class="flex flex-wrap gap-2">
        <.button id={"#{@id}-save"} type="submit" size="sm" variant={@save_variant}>
          {@save_text}
        </.button>
        <.button
          id={"#{@id}-cancel"}
          type="button"
          phx-click="edit_cancel"
          phx-target={@target}
          size="sm"
          variant="ghost"
        >
          Cancel
        </.button>
      </div>
    </.form>
    """
  end

  # -- a taxon's position ----------------------------------------------------------------

  @doc """
  Where a taxon stands, compactly (matter `f923` Task 10), for a taxon's
  page: its placement and its name, each with the Source it comes from,
  and the papers that disagree (each marked declined, with the reason, or
  awaiting a curator), linking only to public pages. `position` is
  `Gallformers.Import.taxonomic_position/1`'s. Renders nothing when no
  current Fact places or names the taxon and no paper disagrees.
  """
  attr :id, :string, required: true
  attr :position, :map, required: true, doc: "`%{placement, name, disagreeing}`"

  def taxonomic_position(assigns) do
    p = assigns.position

    assigns =
      assign(assigns,
        placement: p.placement,
        name: p.name,
        disagreeing: p.disagreeing,
        any: p.placement != nil or p.name != nil or p.disagreeing != []
      )

    ~H"""
    <.fact_list :if={@any} id={@id} layout={:inline} missing_label={nil}>
      <:item :if={@placement} label="Placed">
        <span data-part="placement">
          <%= if @placement.parent do %>
            under <.taxon_name name={@placement.parent.name} rank={rank(@placement.parent.rank)} />
          <% else %>
            at the root
          <% end %>
          <.from source={@placement.source} />
        </span>
      </:item>
      <:item :if={@name} label="Name">
        <span data-part="name">
          <.taxon_name name={@name.name} rank={rank(@name.rank)} />
          <span :if={@name.authorship}>{@name.authorship}</span>
          <span :if={@name.sensu} class="text-muted">sensu {@name.sensu}</span>
          <.from source={@name.source} />
        </span>
      </:item>
      <:item :if={@disagreeing != []} label="Papers that disagree">
        <ul data-part="disagreeing" class="grid gap-0.5">
          <li
            :for={e <- @disagreeing}
            data-decision={e.decision.state}
            class="flex flex-wrap items-baseline gap-x-2"
          >
            <.link navigate={"/source/#{e.source.source_id}"} class="hover:underline">
              {e.source.name}
            </.link>
            <.decision_mark decision={e.decision} />
            <span :if={e.stance == :deny} class="text-caption font-semibold text-danger">not</span>
            <span class="inline-flex min-w-0 flex-wrap items-baseline gap-x-1 text-ink">
              <.fact_value entry={e} />
            </span>
            <span
              :if={e.decision.state == :declined and e.decision.reason}
              class="text-caption text-ink-2"
            >
              Declined: {e.decision.reason}
            </span>
          </li>
        </ul>
      </:item>
    </.fact_list>
    """
  end

  # The Source a position comes from, linked.
  attr :source, :map, required: true

  defp from(assigns) do
    ~H"""
    <span class="text-caption text-muted">
      · from
      <.link navigate={"/source/#{@source.source_id}"} class="hover:underline">{@source.name}</.link>
    </span>
    """
  end

  # -- one Fact ------------------------------------------------------------------------------

  attr :entry, :map, required: true
  attr :mode, :atom, required: true
  attr :editable, :boolean, required: true
  attr :questions, :map, required: true
  attr :editing, :string, default: nil
  attr :passages, :map, required: true
  attr :on_passage, :any, default: nil
  attr :editor, :list, default: []
  attr :corrections, :boolean, default: false
  attr :target, :any, default: nil
  attr :refs, :map, default: %{}
  attr :on_select, :string, default: nil
  attr :selected, :any, default: nil

  defp fact_row(assigns) do
    entry = assigns.entry
    key = fact_key(entry)
    editable = assigns.editable and is_binary(entry.ref) and assigns.mode == :preview
    dropped_by_edit = Enum.any?(entry.edits, &(&1.kind == :drop))

    {menu, kinds} =
      cond do
        editable ->
          {"Edit", edit_kinds(entry, dropped_by_edit)}

        assigns.corrections and assigns.mode == :applied and is_integer(entry.fact_id) ->
          {"Correct", correction_kinds(entry)}

        true ->
          {nil, []}
      end

    assigns =
      assign(assigns,
        key: key,
        row_id: "fact-#{key}",
        shown: shown_names(entry),
        written: written(entry),
        quotes: Enum.with_index(entry.words.evidence),
        sources: Map.get(entry, :sources, []),
        editable: editable,
        dropped_by_edit: dropped_by_edit,
        menu: menu,
        kinds: kinds,
        decision: assigns.mode != :preview && Map.get(entry, :decision)
      )

    ~H"""
    <li
      id={@row_id}
      class="py-1 text-meta scroll-mt-32"
      data-status={@entry.status}
      data-decision={@decision && @decision.state}
    >
      <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
        <.fact_mark :if={not undecided?(@decision)} entry={@entry} mode={@mode} />
        <.decision_mark :if={@decision} decision={@decision} />
        <span :if={@entry.stance == :deny} class="text-caption font-semibold text-danger">not</span>
        <span class={[
          "inline-flex min-w-0 flex-wrap items-baseline gap-x-1 text-ink",
          @entry.status == :dropped && "line-through text-muted"
        ]}>
          <.fact_ref
            :if={ref = @refs[@entry.fact_id]}
            fact={ref}
            selected={@selected}
            on_select={@on_select}
          />
          <.fact_value :if={!@refs[@entry.fact_id]} entry={@entry} />
        </span>
        <span :if={@written != []} class="text-caption text-muted" title="The Source's words">
          {Enum.map_join(@written, " · ", &"“#{&1}”")}
        </span>
        <span
          :if={@decision && @decision.state != :awaiting}
          class="text-caption text-muted"
          data-part="decided"
        >
          {decided_text(@decision)}
        </span>
        <span :if={@sources != []} class="text-caption text-muted" data-part="sources">
          <span :for={{source, i} <- Enum.with_index(@sources)}>
            {if i > 0, do: " · "}{if source.stance == :deny, do: "denied by "}<.link
              navigate={"/source/#{source.source_id}"}
              class="hover:underline"
            >{source.name}</.link>
          </span>
        </span>
        <span class="ml-auto flex items-center gap-2">
          <button
            :if={@quotes != []}
            type="button"
            class="text-caption text-brand hover:underline"
            phx-click={JS.toggle_class("hidden", to: "##{@row_id}-quotes")}
            aria-controls={"#{@row_id}-quotes"}
          >
            {quotes_text(length(@quotes))}
          </button>
          <.fact_menu
            :if={@kinds != []}
            row_id={@row_id}
            key={@key}
            label={@menu}
            kinds={@kinds}
            target={@target}
          />
        </span>
      </div>
      <p :if={@mode == :preview and @entry.status == :waiting} class="text-caption text-warn">
        Waits on
        <.question_link
          id={"#{@row_id}-question"}
          question={@entry.question}
          questions={@questions}
        />
      </p>
      <p
        :if={
          (@mode == :preview and @entry.status in [:conflict, :dropped] and @entry.why) &&
            not @dropped_by_edit
        }
        class={["text-caption", if(@entry.status == :conflict, do: "text-danger", else: "text-ink-2")]}
      >
        {@entry.why}
      </p>
      <p
        :if={@decision && @decision.state == :declined && @decision.reason}
        class="text-caption text-ink-2"
      >
        Declined: {@decision.reason}
      </p>
      <p :if={@entry.words.statement_text} class="text-caption text-ink-2">
        The Source: {@entry.words.statement_text}
      </p>
      <ul :if={@mode == :preview and @entry.edits != []} class="mt-0.5 grid gap-0.5">
        <li
          :for={edit <- @entry.edits}
          id={"#{@row_id}-edit-#{edit.id}"}
          class="flex flex-wrap items-baseline gap-x-2 text-caption text-ink-2"
          data-role="edit"
        >
          <.icon name="ph-pencil-simple" class="size-3 text-muted" />
          <span>
            {edit_text(edit)} by {edit.author_name}<span :if={edit.note}>: {edit.note}</span>
          </span>
          <button
            :if={@editable}
            id={"#{@row_id}-edit-#{edit.id}-undo"}
            type="button"
            phx-click="edit_undo"
            phx-value-id={edit.id}
            class="text-brand hover:underline"
          >
            Undo
          </button>
        </li>
      </ul>
      <div :if={@quotes != []} id={"#{@row_id}-quotes"} class="hidden mt-1 grid gap-1">
        <.review_quote
          :for={{e, _i} <- @quotes}
          text={e.quote}
          where={e.page && "p. #{e.page}"}
          on_passage={@on_passage && passage_key(@entry.batch_id, e.item) && @on_passage}
          passage_key={passage_key(@entry.batch_id, e.item)}
          passage_open={true}
        >
          <:passage :if={Map.has_key?(@passages, passage_key(@entry.batch_id, e.item))}>
            <.review_passage blocks={Map.fetch!(@passages, passage_key(@entry.batch_id, e.item))} />
          </:passage>
        </.review_quote>
      </div>
      <div :if={@editing == @key and @editor != []} class="mt-1">
        {render_slot(@editor, @entry)}
      </div>
    </li>
    """
  end

  defp quotes_text(1), do: "Quote"
  defp quotes_text(n), do: "#{n} quotes"

  # The edits (or corrections) a Fact takes, in a small menu.
  attr :row_id, :string, required: true
  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :kinds, :list, required: true, doc: "`{kind, label}`s"
  attr :target, :any, default: nil

  defp fact_menu(assigns) do
    push_opts = if assigns.target, do: [target: assigns.target], else: []
    assigns = assign(assigns, push_opts: push_opts)

    ~H"""
    <span class="relative" data-role="fact-menu">
      <button
        id={"#{@row_id}-menu-button"}
        type="button"
        class="inline-flex items-center gap-0.5 text-caption text-ink-2 hover:text-brand"
        aria-haspopup="true"
        aria-controls={"#{@row_id}-menu"}
        phx-click={JS.toggle_class("hidden", to: "##{@row_id}-menu")}
      >
        {@label} <.icon name="ph-caret-down" class="size-3" />
      </button>
      <span
        id={"#{@row_id}-menu"}
        role="menu"
        class="hidden absolute right-0 z-20 mt-1 grid min-w-36 rounded-ctl border border-line bg-surface py-1 shadow-float"
        phx-click-away={JS.add_class("hidden", to: "##{@row_id}-menu")}
      >
        <button
          :for={{kind, label} <- @kinds}
          id={"#{@row_id}-edit-#{kind}"}
          type="button"
          role="menuitem"
          class="px-3 py-1 text-left text-caption text-ink-2 hover:bg-surface-2"
          phx-click={
            JS.push("edit_open", [value: %{key: @key, kind: kind}] ++ @push_opts)
            |> JS.add_class("hidden", to: "##{@row_id}-menu")
          }
        >
          {label}
        </button>
      </span>
    </span>
    """
  end

  defp edit_kinds(entry, dropped) do
    [
      {"drop", "Drop", not dropped},
      {"host", "Change Host", host?(entry)},
      {"values", "Change value", entry.kind == :trait},
      {"note", "Note", true}
    ]
    |> Enum.filter(&elem(&1, 2))
    |> Enum.map(fn {kind, label, _} -> {kind, label} end)
  end

  # The fixes an applied Fact takes (a reading fix of its Source,
  # `Gallformers.Curation.fix_reading/3`): withdrawing the Source's
  # statement, for those with a stable key, and moving it where the kind
  # allows. Descriptions, qualifiers and other Relationships take none.
  defp correction_kinds(%{category: :taxonomy, kind: kind}) do
    case kind do
      :placement -> [{"withdraw", "Withdraw"}, {"parent", "Change parent"}]
      :synonymy -> [{"withdraw", "Withdraw"}, {"accepted", "Change accepted taxon"}]
      _ -> [{"withdraw", "Withdraw"}]
    end
  end

  defp correction_kinds(%{kind: :relationship, value: %{type: "host_of"}}),
    do: [{"withdraw", "Withdraw"}, {"host", "Change Host"}]

  defp correction_kinds(%{kind: :relationship, value: %{type: "inducer_of"}}),
    do: [{"withdraw", "Withdraw"}]

  defp correction_kinds(%{kind: :trait}),
    do: [{"withdraw", "Withdraw"}, {"values", "Change value"}]

  defp correction_kinds(%{kind: kind}) when kind in [:alias, :range, :occurrence],
    do: [{"withdraw", "Withdraw"}]

  defp correction_kinds(_entry), do: []

  @doc "Whether a Fact entry is a Host (`host_of`) Relationship."
  @spec host?(map()) :: boolean()
  def host?(%{kind: :relationship, value: %{type: "host_of"}}), do: true
  def host?(_entry), do: false

  defp edit_text(%{kind: :drop}), do: "Dropped"
  defp edit_text(%{kind: :host}), do: "Host changed"

  defp edit_text(%{kind: :trait_value, value: %{"values" => values}}),
    do: "Value set to #{Enum.join(values, ", ")}"

  defp edit_text(%{kind: :note}), do: "Note"
  defp edit_text(_edit), do: "Edited"

  # The link to the question a Fact or Gall waits on, on its step page.
  attr :id, :string, required: true
  attr :question, :map, default: nil
  attr :questions, :map, required: true

  defp question_link(assigns) do
    assigns =
      assign(assigns, target: assigns.question && Map.get(assigns.questions, assigns.question.id))

    ~H"""
    <%= if @target do %>
      <.link id={@id} navigate={@target.path} class="underline hover:text-brand">
        a question in {@target.title} →
      </.link>
    <% else %>
      <span id={@id}>a question{if @question, do: " (#{humanize(@question.kind)})"}</span>
    <% end %>
    """
  end

  # A Fact's mark: its status on the preview; its standing, when not
  # current, once applied.
  attr :entry, :map, required: true
  attr :mode, :atom, required: true

  defp fact_mark(%{mode: :preview, entry: %{status: status}} = assigns) when status != nil do
    assigns =
      assign(assigns,
        text: Map.fetch!(@status_text, status),
        title: Map.fetch!(@status_title, status)
      )

    ~H"""
    <span class={["gf-mark", "gf-mark-#{@entry.status}"]} title={@title}>{@text}</span>
    """
  end

  defp fact_mark(%{entry: %{standing: standing}} = assigns)
       when standing not in [nil, :current] do
    ~H"""
    <span class="gf-mark gf-mark-standing" title="This Fact's standing in Gallformers">
      {@entry.standing}
    </span>
    """
  end

  defp fact_mark(assigns), do: ~H""

  @decision_marks %{
    accepted:
      {"accepted", "gf-mark-held",
       "A curator accepted this statement: it counts, and the tree follows it while it is the newest"},
    declined:
      {"declined", "gf-mark-standing",
       "A curator declined this statement: it does not count unless reopened"},
    awaiting:
      {"awaiting a curator", "gf-mark-waiting",
       "No curator has accepted this statement yet: until one does, it does not count"}
  }

  # A taxonomic statement's mark: whether a curator follows it.
  attr :decision, :map, required: true

  defp decision_mark(assigns) do
    {text, class, title} = Map.fetch!(@decision_marks, assigns.decision.state)
    assigns = assign(assigns, text: text, class: class, title: title)

    ~H"""
    <span class={["gf-mark", @class]} title={@title}>{@text}</span>
    """
  end

  # An undecided statement's standing (unsupported) says nothing its mark doesn't.
  defp undecided?(%{state: state}), do: state in [:awaiting, :declined]
  defp undecided?(_decision), do: false

  defp decided_text(%{by: by, at: at}) do
    date = at && Calendar.strftime(at, "%b %-d, %Y")

    [by && "by #{by}", date]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  # -- a Fact's value, in Gallformers' terms ----------------------------------------------

  attr :entry, :map, required: true

  defp fact_value(%{entry: %{kind: :relationship, category: category, value: v}} = assigns)
       when category in [:inducer, :hosts] do
    assigns = assign(assigns, taxon: v.subject, broad_sense: v[:broad_sense])

    ~H"""
    <.endpoint value={@taxon} show_rank={@entry.category == :hosts} />
    <span
      :if={@broad_sense}
      class="text-ink-2"
    >
      · in its old broad sense, before {@broad_sense.source || "a Source"} split it; which taxon induces it is not known yet
    </span>
    """
  end

  defp fact_value(%{entry: %{kind: :relationship, value: v}} = assigns) do
    endpoints = (RelationshipTypes.get(v.type) || %{endpoints: :taxon_to_gall}).endpoints
    assigns = assign(assigns, endpoints: endpoints, v: v)

    ~H"""
    <%= case @endpoints do %>
      <% :gall_to_gall -> %>
        <span class="text-ink-2">{@v.label}</span> <.endpoint value={@v.object} />
      <% :taxon_to_taxon_in_gall -> %>
        <.endpoint value={@v.subject} /> <span class="text-ink-2">{@v.label}</span>
        <.endpoint value={@v.object} />
      <% _ -> %>
        <.endpoint value={@v.subject} /><span class="text-ink-2">· {@v.label}</span>
    <% end %>
    """
  end

  defp fact_value(%{entry: %{kind: :trait, value: v}} = assigns) do
    assigns = assign(assigns, value: v[:value], suggested: v[:suggested])

    ~H"""
    <%= cond do %>
      <% @value -> %>
        <span class="font-medium">{@value}</span>
      <% @suggested -> %>
        <span class="text-muted">suggested: {@suggested}</span>
      <% true -> %>
        <span class="text-muted">no value yet</span>
    <% end %>
    """
  end

  defp fact_value(%{entry: %{kind: kind, value: v}} = assigns)
       when kind in [:range, :occurrence] do
    assigns =
      assign(assigns,
        prefix: range_prefix(kind, v[:adjustment]),
        place:
          (v[:place] && (v.place.name || v.place.code)) || assigns.entry.words.value_as_written
      )

    ~H"""
    <span :if={@prefix} class="text-ink-2">{@prefix}</span>
    <span class="font-medium">{@place || "an unknown place"}</span>
    """
  end

  defp fact_value(%{entry: %{kind: :alias, value: v}} = assigns) do
    assigns = assign(assigns, v: v)

    ~H"""
    <span class="font-medium">{@v.name}</span>
    <span :if={@v[:kind]} class="text-caption text-muted">{humanize(@v.kind)}</span>
    """
  end

  defp fact_value(%{entry: %{kind: :description} = entry} = assigns) do
    assigns =
      assign(assigns,
        text:
          entry.words.evidence
          |> Enum.map(& &1.quote)
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" … ")
      )

    ~H"""
    <span class="line-clamp-2 text-ink">{if @text != "", do: @text, else: "A description"}</span>
    """
  end

  defp fact_value(%{entry: %{kind: :qualifier, value: v}} = assigns) do
    assigns = assign(assigns, v: v)

    ~H"""
    <span class="text-ink-2">{humanize(@v.qualifier)}:</span><span class="font-medium">{@v.value}</span><span
      :if={@v[:of_ref]}
      class="text-caption text-muted"
    >(of {@v.of_ref})</span>
    """
  end

  defp fact_value(%{entry: %{category: :taxonomy, kind: kind, value: v}} = assigns) do
    assigns = assign(assigns, kind: kind, v: v)

    ~H"""
    <span class="text-caption text-ink-2">{humanize(@kind)}</span>
    <.endpoint :if={@v[:taxon]} value={@v.taxon} show_rank />
    <span :if={@v[:name]} class="text-ink-2">as <em>{@v.name}</em></span>
    <span :if={@v[:parent]} class="text-ink-2">under <.endpoint value={@v.parent} /></span>
    <span
      :if={@kind == :placement and Map.has_key?(@v, :parent) and is_nil(@v.parent)}
      class="text-ink-2"
    >
      at the root
    </span>
    <span :if={@v[:accepted]} class="text-ink-2">
      synonym of <.endpoint value={@v.accepted} />
    </span>
    <span :if={@v[:into]} class="text-ink-2">
      into
      <span :for={{t, i} <- Enum.with_index(@v.into)}>
        <span :if={i > 0}>, </span> <.endpoint value={t} />
      </span>
    </span>
    <span :if={@v[:common_name]} class="text-ink-2">“{@v.common_name}”</span>
    """
  end

  defp fact_value(assigns) do
    ~H"""
    <span class="text-muted">{humanize(@entry.kind)}</span>
    """
  end

  defp range_prefix(:occurrence, _adjustment), do: "recorded in"
  defp range_prefix(_kind, :exclude), do: "not in"
  defp range_prefix(_kind, :only), do: "only in"
  defp range_prefix(_kind, _adjustment), do: "in"

  # A taxon or Gall a Fact names, with its rank (above species) and "new".
  attr :value, :map, default: nil
  attr :show_rank, :boolean, default: false

  defp endpoint(%{value: nil} = assigns) do
    ~H"""
    <span class="text-muted">?</span>
    """
  end

  defp endpoint(assigns) do
    assigns =
      assign(assigns,
        name: assigns.value[:name],
        rank: assigns.value[:rank],
        new: assigns.value[:new] == true
      )

    ~H"""
    <span class="font-medium">
      <span
        :if={@show_rank and @rank not in [nil, :species]}
        class="text-caption font-normal text-ink-2"
      >
        {@rank}
      </span>
      <%= if @name do %>
        <.taxon_name name={@name} rank={rank(@rank)} />
      <% else %>
        <span class="text-muted">not settled</span>
      <% end %>
      <span :if={@new} class="gf-mark gf-mark-new">new</span>
    </span>
    """
  end

  defp rank(nil), do: "species"
  defp rank(rank), do: to_string(rank)

  # -- the Source's words ------------------------------------------------------------------

  # The names a Fact's value shows, lower-cased, to leave out of the
  # Source's words what reads the same.
  defp shown_names(entry) do
    v = entry.value || %{}

    endpoints =
      for key <- [:subject, :object, :taxon, :parent, :accepted],
          %{} = e <- [Map.get(v, key)],
          is_binary(e[:name]),
          do: e.name

    others = for key <- [:value, :name], s = Map.get(v, key), is_binary(s), do: s
    places = for %{name: name} when is_binary(name) <- [Map.get(v, :place)], do: name

    MapSet.new(endpoints ++ others ++ places, &String.downcase/1)
  end

  # The Source's own words for a Fact, those that differ from what it shows.
  defp written(entry) do
    shown = shown_names(entry)
    words = entry.words

    names = for n <- words.names, w = n.name_as_written, is_binary(w), do: w

    (names ++ [words.term, words.value_as_written])
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.reject(&MapSet.member?(shown, String.downcase(&1)))
  end

  # -- the Fact inspector (matter 87a1) ------------------------------------------

  @trait_labels %{
    "detachable" => "Detachable",
    "color" => "Color",
    "texture" => "Texture",
    "shape" => "Shape",
    "season" => "Season",
    "alignment" => "Alignment",
    "walls" => "Walls",
    "plant_part" => "Location",
    "form" => "Form",
    "cells" => "Cells"
  }

  @species_ranks [:species, :subspecies, :variety, :form]

  @doc "A Trait's name on the Gall page (`plant_part` is Location)."
  @spec trait_label(String.t()) :: String.t()
  def trait_label(trait),
    do: Map.get(@trait_labels, trait, trait |> humanize() |> String.capitalize())

  @doc """
  A Fact-backed value on a page (`components.md`, `fact_ref`): the value
  with a dotted underline, a button that sends `on_select` with the Fact's
  key (`GallformersWeb.FactKey`) to open the `fact_inspector` on it. The
  Fact is one of `Gallformers.Import.gall_facts/1`'s. With `proposed`, a
  value an open action would add: `text`, marked proposed, not selectable.
  """
  attr :fact, :map, default: nil, doc: "a Fact from `Gallformers.Import.gall_facts/1`"
  attr :selected, :any, default: nil, doc: "the selected Fact's key, or nil"
  attr :on_select, :string, default: nil
  attr :inspector, :string, default: "fact-inspector", doc: "the inspector's id"
  attr :target, :any, default: nil
  attr :proposed, :boolean, default: false
  attr :text, :string, default: nil, doc: "a proposed value's words"
  attr :class, :any, default: nil, doc: "layout only"
  slot :inner_block, doc: "the value, when the page shows it otherwise"

  def fact_ref(%{proposed: true} = assigns) do
    ~H"""
    <span
      data-proposed
      class={[
        "inline-flex w-fit items-center gap-2 rounded-ctl bg-sky-soft px-1 text-ui text-ink",
        @class
      ]}
    >
      {@text}<.chip size="sm" variant={:info}>proposed</.chip>
    </span>
    """
  end

  def fact_ref(assigns) do
    assigns = assign(assigns, selected?: assigns.selected == assigns.fact.key)

    ~H"""
    <button
      type="button"
      phx-click={@on_select}
      phx-target={@target}
      phx-value-key={FactKey.encode(@fact.key)}
      aria-pressed={to_string(@selected?)}
      aria-controls={@inspector}
      title="Who says so?"
      class={[
        "w-fit rounded-ctl px-0.5 text-left text-ui text-ink underline decoration-line-strong decoration-dotted underline-offset-4 hover:decoration-ink",
        @selected? && "bg-sky-soft decoration-ink",
        @class
      ]}
    >
      <%= if @inner_block != [] do %>
        {render_slot(@inner_block)}
      <% else %>
        <.ref_value fact={@fact} />
      <% end %>
    </button>
    """
  end

  attr :fact, :map, required: true

  # A Fact's value as a page writes it (the Facts panel's `fact_value/1`
  # adds ranks and kinds; a page doesn't).
  defp ref_value(%{fact: %{kind: kind, value: %{subject: subject}}} = assigns)
       when kind in [:host, :inducer] do
    assigns = assign(assigns, subject: subject)

    ~H"""
    <.taxon_name
      name={@subject.name}
      rank={rank(@subject.rank)}
      genus_placeholder={@fact.kind == :host and @subject.rank == :genus}
    />
    """
  end

  defp ref_value(%{fact: %{kind: kind, value: %{place: place} = v}} = assigns)
       when kind in [:range, :occurrence] do
    assigns =
      assign(assigns, prefix: range_prefix(kind, v[:adjustment]), place: place.name || place.code)

    ~H"""
    <span class="text-muted">{@prefix}</span> {@place}
    """
  end

  defp ref_value(%{fact: %{kind: :trait}} = assigns), do: ~H|{@fact.value.value}|
  defp ref_value(%{fact: %{kind: :alias}} = assigns), do: ~H|{@fact.value.name}|

  @doc """
  Who says so about one Fact, beside the page (`components.md`,
  `fact_inspector`): its kind, its value, what it is of, its standing, and
  one block per Source, Gallformers first, then the others newest first
  (`Gallformers.Import.gall_facts/1` orders them). A labelled region
  placed by `gf-sheet`: a bottom sheet on phones, in the rail on wide
  screens; each `fact_ref` controls it by `id`.
  """
  attr :id, :string, required: true
  attr :state, :atom, default: :fact, values: [:fact, :new, :observation]

  attr :fact, :map,
    default: nil,
    doc: "a Fact from `Gallformers.Import.gall_facts/1` (the `:fact` state)"

  attr :new, :string, default: nil, doc: ~s|what a new Fact will be ("Host"), for `:new`|
  attr :of, :map, required: true, doc: "the Gall: `name`, `undescribed?`"
  attr :editing, :boolean, default: false, doc: "Edit mode: Gallformers' block and its actions"
  attr :on_close, :string, required: true
  attr :target, :any, default: nil

  attr :history, :list,
    default: [],
    doc:
      "the Fact's history, newest first: `%{at, what, who}` (`Gallformers.Import.fact_history/1`)"

  slot :actions, doc: "Edit mode: the actions in Gallformers' block"

  slot :reading,
    doc:
      "Edit mode: what each other Source's block offers for fixing how it was read, " <>
        "given its statement (`:let`)"

  slot :footer, doc: "Edit mode: below the blocks (the reading fixes' toggle)"
  slot :inner_block, doc: "a new Fact's form (`:new`), or the observation's (`:observation`)"

  def fact_inspector(%{state: state} = assigns) when state in [:new, :observation] do
    assigns =
      assign(assigns,
        title: if(state == :observation, do: "Add from observation", else: "New " <> assigns.new)
      )

    ~H"""
    <section id={@id} aria-label={@title} class="gf-sheet">
      <.inspector_head kind={@title} on_close={@on_close} target={@target} />
      <p data-part="of" class="text-meta text-muted">
        For
        <GallformersWeb.DomainComponents.gall_name
          name={@of.name}
          undescribed={Map.get(@of, :undescribed?, false)}
        />
      </p>
      <div class="mt-3">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  def fact_inspector(assigns) do
    ~H"""
    <section id={@id} aria-label={"Who says so: " <> kind_label(@fact)} class="gf-sheet">
      <.inspector_head kind={kind_label(@fact)} on_close={@on_close} target={@target} />

      <div class="flex flex-col gap-1">
        <p data-part="value" class="font-brand text-section text-ink"><.ref_value fact={@fact} /></p>
        <p data-part="of" class="text-meta text-muted">
          {of_words(@fact)}
          <GallformersWeb.DomainComponents.gall_name
            name={@of.name}
            undescribed={Map.get(@of, :undescribed?, false)}
          />
          <span :if={host_page(@fact)}>
            · <.link navigate={host_page(@fact)}>Host page</.link>
          </span>
        </p>
      </div>

      <p data-part="standing" class="mt-3 flex flex-wrap items-center gap-2 text-ui text-ink-2">
        <%= case @fact.standing do %>
          <% :unconfirmed -> %>
            <.chip variant={:warn}>Unconfirmed</.chip>
            <span>Only in Gallformers' original data; no other Source states it.</span>
          <% {:holds, n} -> %>
            <.chip variant={:ok}>Holds</.chip>
            <span>Stated by {n} {if n == 1, do: "Source", else: "Sources"}.</span>
          <% :withdrawn -> %>
            <.chip variant={:neutral}>Withdrawn</.chip>
            <span>{withdrawn_words(@fact)}</span>
          <% :superseded -> %>
            <.chip variant={:neutral}>Superseded</.chip>
            <span>A newer Source gives another value.</span>
        <% end %>
      </p>

      <div class="mt-4 flex flex-col border-t border-line">
        <div class="flex items-baseline justify-between gap-2 pt-3">
          <h3 class="text-meta font-semibold text-muted">Who says so</h3>
          <span class="text-caption text-muted">Gallformers, then newest first</span>
        </div>
        <.statement
          :if={@fact.gallformers || @editing}
          line={@fact.gallformers}
          gallformers
          actions={if @editing, do: @actions, else: []}
        />
        <.statement
          :for={line <- @fact.sources}
          line={line}
          reading={if @editing, do: @reading, else: []}
        />
      </div>
      <div :if={@editing and @footer != []} data-part="footer" class="pt-2">
        {render_slot(@footer)}
      </div>

      <details :if={@history != []} data-part="history" class="mt-4 border-t border-line pt-3">
        <summary class="cursor-pointer text-meta text-link">History ({length(@history)})</summary>
        <ol class="mt-2 flex flex-col gap-2">
          <li :for={h <- @history} class="flex gap-3 text-meta">
            <span class="shrink-0 text-muted tabular-nums">{history_date(h.at)}</span>
            <span class="text-ink-2">
              {h.what}<span :if={h.who} class="text-muted"> ({h.who})</span>
            </span>
          </li>
        </ol>
      </details>
    </section>
    """
  end

  attr :kind, :string, required: true
  attr :on_close, :string, required: true
  attr :target, :any, default: nil

  defp inspector_head(assigns) do
    ~H"""
    <div class="mb-2 flex items-center justify-between gap-2">
      <span data-part="kind" class="text-meta font-semibold text-muted">{@kind}</span>
      <.button
        size="sm"
        variant="ghost"
        icon="ph-x"
        icon_only
        label="Close"
        phx-click={@on_close}
        phx-target={@target}
      />
    </div>
    """
  end

  attr :line, :map, default: nil, doc: "nil: Gallformers hasn't stated it (Edit mode)"
  attr :gallformers, :boolean, default: false
  attr :actions, :list, default: [], doc: "the actions slot, in Edit mode"
  attr :reading, :list, default: [], doc: "the reading slot, in Edit mode"

  # Gallformers in Edit mode, with nothing stated yet: its block, its actions.
  defp statement(%{line: nil} = assigns) do
    ~H"""
    <article
      data-part="statement"
      data-source="gallformers"
      class="flex flex-col gap-1 border-b border-line py-3 last:border-b-0"
    >
      <p class="text-ui">
        <span class="font-semibold text-ink">Gallformers</span>
        <span class="text-ink-2">hasn't stated this</span>
      </p>
      <div :if={@actions != []} data-part="actions" class="flex flex-col gap-2 pt-1">
        {render_slot(@actions)}
      </div>
    </article>
    """
  end

  # One Source's statement: the same template for every Source.
  defp statement(assigns) do
    assigns =
      assign(assigns,
        shown: Enum.take(assigns.line.quotes, 2),
        more: max(length(assigns.line.quotes) - 2, 0)
      )

    ~H"""
    <article
      data-part="statement"
      data-source={if @gallformers, do: "gallformers", else: @line.source_id}
      class="flex flex-col gap-1 border-b border-line py-3 last:border-b-0"
    >
      <p class="text-ui">
        <span :if={@gallformers} class="font-semibold text-ink">Gallformers</span>
        <.link :if={!@gallformers} navigate={"/source/#{@line.source_id}"} class="font-semibold">
          {@line.name}
        </.link>
        <span class="text-ink">
          {if @line.stance == :deny, do: "says it isn't so", else: "says so"}
        </span>
        <span class="text-meta text-muted">
          · {when_words(@line, @gallformers)}{state_words(@line)}
        </span>
      </p>
      <p :if={@line.words != []} data-part="words" class="text-meta text-ink-2">
        Written as {Enum.map_join(@line.words, ", ", &"“#{&1}”")}
      </p>
      <p
        :for={o <- @line.observations}
        data-part="observation"
        class="flex items-center gap-2 text-meta text-ink-2"
      >
        <img
          :if={o[:thumbnail_url]}
          src={o.thumbnail_url}
          alt=""
          class="size-10 shrink-0 rounded-ctl object-cover"
        />
        <span>
          Based on
          <.link href={observation_href(o)} target="_blank" rel="noreferrer">
            {observation_name(o)} {o.id}
          </.link>
          <span :if={grade_words(o[:quality_grade])}>({grade_words(o[:quality_grade])})</span>
        </span>
      </p>
      <.source_quote :for={q <- @shown} page={q.page && "p. #{q.page}"} class="text-meta">
        <span class="line-clamp-4">{q.quote}</span>
      </.source_quote>
      <p :if={@more > 0} data-part="more-quotes" class="text-caption text-muted">
        {@more} more {if @more == 1, do: "quote", else: "quotes"}
      </p>
      <div :if={@actions != []} data-part="actions" class="flex flex-col gap-2 pt-1">
        {render_slot(@actions)}
      </div>
      <div :if={@reading != []} data-part="reading" class="flex flex-col gap-2 pt-1">
        {render_slot(@reading, @line)}
      </div>
    </article>
    """
  end

  defp observation_href(%{url: url}) when is_binary(url) and url != "", do: url

  defp observation_href(%{provider: provider, id: id}) when provider in [:bugguide, "bugguide"],
    do: "https://bugguide.net/node/view/#{id}"

  defp observation_href(%{id: id}), do: "https://www.inaturalist.org/observations/#{id}"

  defp observation_name(%{provider: provider}) when provider in [:bugguide, "bugguide"],
    do: "BugGuide observation"

  defp observation_name(_observation), do: "iNaturalist observation"

  @doc "An iNaturalist quality grade in words (nil for none)."
  @spec grade_words(String.t() | nil) :: String.t() | nil
  def grade_words("research"), do: "Research Grade"
  def grade_words("needs_id"), do: "Needs ID"
  def grade_words("casual"), do: "Casual"
  def grade_words(_grade), do: nil

  defp when_words(%{date: nil}, true), do: "original data, undated"
  defp when_words(%{date: nil}, false), do: "undated"
  defp when_words(%{date: date}, _gallformers), do: date

  defp state_words(%{state: :awaiting}), do: " · awaiting a curator"

  defp state_words(%{state: :declined, reason: reason}) when reason not in [nil, ""],
    do: " · declined: #{reason}"

  defp state_words(%{state: :declined}), do: " · declined"
  defp state_words(_line), do: ""

  # Who withdrew it: the newest Source that says it isn't so.
  defp withdrawn_words(fact) do
    case Enum.find([fact.gallformers | fact.sources], &match?(%{stance: :deny}, &1)) do
      %{gallformers?: true} -> "Gallformers says it isn't so."
      %{name: name} -> "#{name} says it isn't so."
      nil -> "A newer Source says it isn't so."
    end
  end

  defp history_date(nil), do: "undated"
  defp history_date(%NaiveDateTime{} = at), do: at |> NaiveDateTime.to_date() |> Date.to_iso8601()
  defp history_date(%DateTime{} = at), do: at |> DateTime.to_date() |> Date.to_iso8601()

  defp kind_label(%{kind: :host}), do: "Host"
  defp kind_label(%{kind: :inducer}), do: "Inducer"
  defp kind_label(%{kind: :trait, trait: trait}), do: trait_label(trait)
  defp kind_label(%{kind: kind}) when kind in [:range, :occurrence], do: "Range"
  defp kind_label(%{kind: :alias, value: %{kind: :former_label}}), do: "Former label"
  defp kind_label(%{kind: :alias}), do: "Common name"

  defp of_words(%{kind: :host}), do: "A Host of"
  defp of_words(%{kind: :inducer}), do: "The Inducer of"
  defp of_words(%{kind: :trait}), do: "A Trait of"
  defp of_words(%{kind: kind}) when kind in [:range, :occurrence], do: "The range of"
  defp of_words(%{kind: :alias, value: %{kind: :former_label}}), do: "A former label of"
  defp of_words(%{kind: :alias}), do: "A common name of"

  # A Host's own page: a species or below its Host page, a genus or
  # section its rank page.
  defp host_page(%{kind: :host, value: %{subject: %{taxon_id: id, rank: rank}}})
       when rank in @species_ranks,
       do: "/host/#{id}"

  defp host_page(%{kind: :host, value: %{subject: %{rank: rank, name: name}}}),
    do: TaxonomyURL.public_path(%{rank: rank, name: name})

  defp host_page(_fact), do: nil

  defp humanize(nil), do: ""
  defp humanize(text), do: text |> to_string() |> String.replace("_", " ")
end
