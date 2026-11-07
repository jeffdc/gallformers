defmodule GallformersWeb.Admin.ReviewLive.Loader do
  @moduledoc """
  What the review pages (`6611` Task 6) read, through `Gallformers.Import`
  and the catalog's own functions, and shape for the curator.

    * `sources/0` — every Source with a package under review, its packages
      grouped under it (the Gallformers notes' many packages under the one
      Gallformers Source; a package not matched to a Source yet stands on
      its own, under its Source block's title and citation), with how much
      is left to decide, how much has a proposed answer and what holds
      approval.
    * `source_page/1` and `package_page/1` — one Source's (or one
      package's) packages with their batches, items and statements, and
      the Source's summary.
    * `notes_page/1` — the Gallformers Source's notes (`6611` Task 7), one
      line each, with where each stands, its group and what it adds.
    * `renames/1` and `renames_row/0` — the Gall rename proposals, which
      belong to no package (`6611` Task 8), and their row on the Sources
      list.
    * `merge_conflicts/1` and `merge_conflicts_row/0` — the questions merges
      leave (same-date ties, of no package; matter `ec2c`), and their row.
    * `taxonomy/1` and `taxonomy_row/0` — the taxonomy questions (matter
      `f923` Task 6: Sources' taxonomic statements to accept or decline,
      across Sources), by Source, and their row. They are not among a
      Source's own questions (its steps, its overview, its row): they come
      after approval and hold none.
    * `entries/3` — each item of a page as the curator reads it
      (`GallformersWeb.Admin.Review.Questions.present/2`), with the quotes
      it rests on. On a step's page (`step:`), the step's open questions
      get what their answers show besides: on Names each candidate taxon's
      identity line (`Gallformers.Import.ReviewContext.taxon/1`), on Galls
      what the Source says of each Gall and what each candidate Gall is,
      to compare side by side (`gall_view`). A Host's WCVP panel is read
      when its row opens (`GallformersWeb.Admin.ReviewLive.ItemRow`), with
      the genera the batch names (`genera`) to expand an abbreviation; an
      open Host's `new_plant` is the plant its "Create a new plant" link
      starts the New Taxon page with.
      Disputes about the same statement are one entry, every one of them
      its `members` (matter `d213`, Disputes step).

  Nothing here writes.
  """

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.ReviewContext
  alias Gallformers.Places
  alias Gallformers.Sources
  alias Gallformers.Sources.Source
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.Review.Questions
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.ReviewLive.Notes

  @reviewable [:validated, :resolving, :awaiting_review]
  @set_aside_kinds [:set_aside_term, :set_aside_statement, :trait_term]

  @kind_labels %{
    "publication" => "Publication",
    "website" => "Website",
    "database" => "Database",
    "unpublished" => "Unpublished",
    "research_data" => "Research data",
    "gallformers" => "Gallformers notes"
  }

  @typedoc """
  An item of a page, as the curator reads it. A group of identical
  disputes also has `members`, its disputes' entries.
  """
  @type entry :: %{
          item: QueueItem.t(),
          question: GallformersWeb.Admin.Review.Question.t(),
          quotes: [%{text: String.t(), where: String.t() | nil, item: String.t() | nil}],
          holds: boolean(),
          proposable: boolean(),
          rejected: boolean(),
          accept: {:firm | :suggestion, map()} | nil,
          decided: String.t() | nil,
          comparison: [Import.candidate()],
          genera: [String.t()],
          new_plant: %{name: String.t() | nil, rank: Rank.t(), parent_id: integer() | nil} | nil
        }

  # -- the Sources list ----------------------------------------------------------

  @doc """
  Every Source with a package under review, as rows for the Sources list:
  `%{id, source_id, path, title, citation, kind, year, notes, packages,
  to_decide, proposed, holding, ready, status}` (`source_id` nil for a
  package not matched to a Source yet). `to_decide` counts the open
  questions, all but the terms and statements set aside (which never hold
  approval), identical disputes once. `holding` is `[{count, section
  title}]`; `ready` is true when nothing holds approval. `path` opens the
  Source at its first step with work left
  (`GallformersWeb.Admin.Review.Steps`), else at its overview; the
  Gallformers notes at their own page.
  """
  @spec sources() :: [map()]
  def sources do
    packages = Import.list_packages(status: @reviewable).entries

    open =
      Import.list_open_queue_items().entries
      |> Enum.filter(&(&1.package_id && not taxonomy_question?(&1)))
      |> Enum.group_by(& &1.package_id)

    sources = packages |> Enum.map(& &1.source_id) |> source_map()

    # The statements behind the open items, so each is placed in the section
    # the Source's page places it in (`Questions` reads its method and detail).
    statements =
      open
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(& &1.batch_id)
      |> Enum.map(&{&1.batch_id, &1.statement_ref})
      |> Import.statements_for()

    packages
    |> Enum.group_by(&group_key(&1, sources))
    |> Enum.map(fn {key, packages} -> source_row(key, packages, sources, open, statements) end)
  end

  defp group_key(%Package{source_id: id}, sources) when is_integer(id) do
    case sources[id] do
      %Source{kind: :gallformers} -> :notes
      _ -> {:source, id}
    end
  end

  defp group_key(%Package{id: id}, _sources), do: {:package, id}

  defp source_row(key, packages, sources, open, statements) do
    all =
      packages
      |> Enum.flat_map(&Map.get(open, &1.id, []))
      |> Enum.map(&light_entry(&1, statements))
      |> group_disputes(nil)

    # Terms and statements set aside never hold approval: they're counted apart.
    {set_aside, entries} = Enum.split_with(all, &(&1.item.kind in @set_aside_kinds))
    holding = holding(entries)
    first = all |> Steps.summarize() |> Steps.first_open()

    summary =
      case key do
        {:package, _id} -> packages |> hd() |> Import.list_batches() |> block_summary()
        _ -> sources |> Map.fetch!(hd(packages).source_id) |> source_summary()
      end

    %{
      id: row_id(key, packages),
      source_id: if(match?({:package, _}, key), do: nil, else: hd(packages).source_id),
      path: row_path(key, packages, first),
      title: summary.title,
      citation: summary.citation,
      kind: summary.kind,
      year: summary.year,
      notes: key == :notes,
      packages: length(packages),
      to_decide: length(entries),
      set_aside: length(set_aside),
      proposed: Enum.count(entries, & &1.proposable),
      holding: holding,
      ready: holding == [] and Enum.all?(packages, &(&1.status == :awaiting_review)),
      status: status(packages, holding)
    }
  end

  @doc """
  The rows of `sources/0` of the Sources Gallformers holds, by Source ID:
  what the admin Sources list and a Source's page show of its review.
  """
  @spec reviews_by_source() :: %{integer() => map()}
  def reviews_by_source do
    for %{source_id: id} = row <- sources(), is_integer(id), into: %{}, do: {id, row}
  end

  defp row_id(:notes, [p | _]), do: "source-#{p.source_id}"
  defp row_id({:source, id}, _packages), do: "source-#{id}"
  defp row_id({:package, id}, _packages), do: "package-#{id}"

  # A Source opens at its first step with work left; the Gallformers notes
  # at their own page.
  defp row_path(:notes, [p | _], _first), do: "/admin/review/sources/#{p.source_id}"
  defp row_path(key, packages, nil), do: base_path(key, packages)
  defp row_path(key, packages, step), do: "#{base_path(key, packages)}/#{step.slug}"

  defp base_path({:package, id}, _packages), do: "/admin/review/packages/#{id}"
  defp base_path(_key, [p | _]), do: "/admin/review/sources/#{p.source_id}"

  # An open item with what the list needs: its section, and whether it
  # holds approval or has a proposal to accept. The batch is preloaded.
  defp light_entry(%QueueItem{} = item, statements) do
    batch = loaded(item.batch)
    statement = statements[{item.batch_id, item.statement_ref}]

    context = %{
      batch_type: batch && batch.batch_type,
      fact: batch && fact(batch, item),
      statement: statement && Map.take(statement, [:method, :flags, :detail])
    }

    entry(item, Questions.present(item, context), batch, [])
  end

  defp loaded(%Batch{} = batch), do: batch
  defp loaded(_batch), do: nil

  @doc "What holds approval among `entries`' open items: `[{count, section title}]`."
  @spec holding([entry()]) :: [{pos_integer(), String.t()}]
  def holding(entries) do
    entries
    |> Enum.filter(&(&1.item.status == :open and &1.holds))
    |> Enum.group_by(& &1.question.section.id)
    |> Enum.sort_by(fn {id, _} -> Enum.find_index(section_order(), &(&1 == id)) end)
    |> Enum.map(fn {_id, [e | _] = held} -> {length(held), e.question.section.title} end)
  end

  defp section_order, do: Enum.map(Questions.sections(), & &1.id)

  defp status(packages, holding) do
    cond do
      Enum.any?(packages, &(&1.status in [:validated, :resolving])) -> "Resolving"
      holding == [] -> "Ready to approve"
      true -> "Awaiting review"
    end
  end

  # -- the Gall rename proposals ----------------------------------------------------

  @doc """
  The Gall rename proposals (`Gallformers.Import.list_gall_renames/1`,
  from no package) as `t:entry/0`s, oldest first: the open ones, or with
  `status: :all` the decided ones too.
  """
  @spec renames(keyword()) :: [entry()]
  def renames(opts \\ []) do
    items = Import.list_gall_renames(status: Keyword.get(opts, :status, :open))
    entries([%{items: items, batches: [], statements: %{}}], nil)
  end

  @doc """
  The Sources list's row for the open Gall rename proposals (shaped as
  `sources/0`'s rows), or nil when none is open.
  """
  @spec renames_row() :: map() | nil
  def renames_row do
    case renames() do
      [] ->
        nil

      entries ->
        %{
          id: "gall-renames",
          source_id: nil,
          path: "/admin/review/renames",
          title: "Gall rename proposals",
          citation: "A change in the tree would rename these Galls. They come from no Source.",
          kind: nil,
          year: nil,
          notes: false,
          packages: 0,
          to_decide: length(entries),
          set_aside: 0,
          proposed: Enum.count(entries, & &1.proposable),
          holding: [],
          ready: false,
          status: "Awaiting a decision"
        }
    end
  end

  @doc """
  The questions merges leave (`Gallformers.Import.list_merge_conflicts/1`,
  from no package) as `t:entry/0`s, oldest first: the open ones, or with
  `status: :all` the decided ones too.
  """
  @spec merge_conflicts(keyword()) :: [entry()]
  def merge_conflicts(opts \\ []) do
    items = Import.list_merge_conflicts(status: Keyword.get(opts, :status, :open))
    entries([%{items: items, batches: [], statements: %{}}], nil)
  end

  @doc """
  The Sources list's row for the open questions merges left (shaped as
  `sources/0`'s rows), or nil when none is open.
  """
  @spec merge_conflicts_row() :: map() | nil
  def merge_conflicts_row do
    case Import.list_merge_conflicts() do
      [] ->
        nil

      items ->
        %{
          id: "merge-conflicts",
          source_id: nil,
          path: "/admin/review/merges",
          title: "Questions from merges",
          citation:
            "Merging two records brought Sources of the same date into disagreement. They come from no Source.",
          kind: nil,
          year: nil,
          notes: false,
          packages: 0,
          to_decide: length(items),
          set_aside: 0,
          proposed: 0,
          holding: [],
          ready: false,
          status: "Awaiting a decision"
        }
    end
  end

  # -- the taxonomy questions (matter `f923` Task 6) ---------------------------------

  @doc """
  The taxonomy questions (`Gallformers.Import.list_taxonomy_questions/1`)
  by Source, the newest Source first: `%{source_id, source, summary, name,
  entries, open}`, `name` the Source's short name (else its title) and
  `entries` its questions as `t:entry/0`s, oldest first, each open one
  reading what the tree holds now (`subject["now"]`). Options: `:status`
  (default `:open`; `:all`), `:source_id`.
  """
  @spec taxonomy(keyword()) :: [map()]
  def taxonomy(opts \\ []) do
    items = Import.list_taxonomy_questions(opts)
    sources = items |> Enum.map(& &1.subject["source_id"]) |> source_map()

    batches =
      items
      |> Enum.map(& &1.batch_id)
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()
      |> Enum.map(&Import.get_batch!/1)

    items
    |> Enum.group_by(& &1.subject["source_id"])
    |> Enum.map(fn {source_id, items} ->
      source = sources[source_id]
      summary = source && source_summary(source)
      name = summary && (summary.who || summary.title)
      items = Enum.map(items, &with_tree_now/1)
      entries = entries([%{items: items, batches: batches, statements: %{}}], name)

      %{
        source_id: source_id,
        source: source,
        summary: summary,
        name: name || "A Source",
        entries: entries,
        open: Enum.count(entries, &(&1.item.status == :open))
      }
    end)
    |> Enum.sort_by(&{-((&1.summary && &1.summary.year) || 0), &1.name})
  end

  # An open question reads what the tree holds now, not when it was asked.
  defp with_tree_now(%QueueItem{status: :open} = item) do
    now = Import.taxonomy_tree_now(item) || "the tree follows it already"
    %{item | subject: Map.put(item.subject, "now", now)}
  end

  defp with_tree_now(item), do: item

  @doc """
  The Sources list's row for the open taxonomy questions (shaped as
  `sources/0`'s rows), or nil when none is open.
  """
  @spec taxonomy_row() :: map() | nil
  def taxonomy_row do
    case Import.count_taxonomy_questions() do
      0 ->
        nil

      n ->
        %{
          id: "taxonomy-questions",
          source_id: nil,
          path: "/admin/review/taxonomy",
          title: "Taxonomy questions",
          citation:
            "Newer papers' placements, names and synonymies, to accept or decline. " <>
              "They come after a Source's approval and hold none.",
          kind: nil,
          year: nil,
          notes: false,
          packages: 0,
          to_decide: n,
          set_aside: 0,
          proposed: 0,
          holding: [],
          ready: false,
          status: "Awaiting a decision"
        }
    end
  end

  defp taxonomy_question?(%QueueItem{kind: :taxonomy_acceptance}), do: true
  defp taxonomy_question?(_item), do: false

  # -- one Source's page ----------------------------------------------------------

  @doc """
  The packages under review of the Source `source_id`, with the Source:
  `%{source, summary, packages}` (see `package_data/1`), or nil when there
  is no such Source. `keep` lists package IDs to keep whatever their status
  (the page's packages, once approved or denied).
  """
  @spec source_page(integer(), [integer()]) :: map() | nil
  def source_page(source_id, keep \\ []) do
    case Sources.get_source(source_id) do
      nil ->
        nil

      source ->
        packages =
          Import.list_packages().entries
          |> Enum.filter(
            &(&1.source_id == source_id and (&1.status in @reviewable or &1.id in keep))
          )
          |> Enum.sort_by(& &1.id)

        %{
          source: source,
          summary: source_summary(source),
          packages: Enum.map(packages, &package_data/1)
        }
    end
  end

  @doc "One package's page: as `source_page/2`, with only that package."
  @spec package_page(integer()) :: map() | nil
  def package_page(package_id) do
    case get_package(package_id) do
      nil ->
        nil

      package ->
        data = package_data(package)
        source = package.source_id && Sources.get_source(package.source_id)

        summary =
          if source, do: source_summary(source), else: block_summary(data.batches)

        %{source: source, summary: summary, packages: [data]}
    end
  end

  defp get_package(id) do
    Import.get_package!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  # -- the Gallformers notes ------------------------------------------------------------

  @typedoc """
  A Gallformers note on its Source's page (`6611` Task 7): its package,
  where it stands (`:ready`, nothing holds it; `:needs`, something holds it
  or it is still resolving; `:approved`), its group
  (`GallformersWeb.Admin.ReviewLive.Notes.group/1`), its Gall's name and
  ID, what it adds and set aside (chips), how many open items hold it, and
  for a note that needs the curator, those items as `t:entry/0`s.
  """
  @type note :: %{
          id: integer(),
          package: Package.t(),
          state: :ready | :needs | :approved,
          group: Notes.group(),
          name: String.t(),
          gall_id: integer() | nil,
          adds: [String.t()],
          aside: [String.t()],
          holding: non_neg_integer(),
          entries: [entry()]
        }

  @doc """
  The Gallformers Source's notes, or nil when Source `source_id` is not the
  Gallformers Source: `%{source, summary, notes, stats}`. Each package of
  the Source under review or approved is one `t:note/0`, oldest first;
  `stats` counts the notes Gallformers holds (`notes`), those read into a
  package (`read`), and the `ready`, `needs` and `approved` ones.
  """
  @spec notes_page(integer()) :: map() | nil
  def notes_page(source_id) do
    case Sources.get_source(source_id) do
      %Source{kind: :gallformers} = source -> notes_data(source)
      _ -> nil
    end
  end

  defp notes_data(source) do
    loaded =
      Import.list_packages(status: [:approved | @reviewable]).entries
      |> Enum.filter(&(&1.source_id == source.id))
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn p ->
        batches = Import.list_batches(p)
        content = Enum.find_value(batches, &(&1.batch_type == :gall && &1.content))
        %{package: p, batches: batches, content: content, gall_id: note_gall_id(content)}
      end)

    gall_ids = loaded |> Enum.map(& &1.gall_id) |> Enum.filter(&is_integer/1) |> Enum.uniq()
    galls = gall_ids |> Catalog.list_galls_by_id() |> Map.new(&{&1.id, gall_name(&1)})

    undescribed =
      galls
      |> Map.keys()
      |> Enum.map(&%{id: &1})
      |> Catalog.add_undescribed()
      |> Map.new(&{&1.id, &1.undescribed})

    texts = Sources.newest_note_texts(source.id)
    places = Places.list_all_places() |> Map.new(&{&1.code, &1.name})

    ctx = %{galls: galls, undescribed: undescribed, texts: texts, places: places}
    notes = Enum.map(loaded, &note_row(&1, ctx))

    %{
      source: source,
      summary: source_summary(source),
      notes: notes,
      stats: %{
        notes: map_size(texts),
        read: length(notes),
        ready: Enum.count(notes, &(&1.state == :ready)),
        needs: Enum.count(notes, &(&1.state == :needs)),
        approved: Enum.count(notes, &(&1.state == :approved))
      }
    }
  end

  defp note_row(%{package: package, batches: batches, content: content, gall_id: gall_id}, ctx) do
    items = Import.list_queue_items(package, status: :all)
    types = Map.new(batches, &{&1.id, &1.batch_type})

    holding =
      Enum.filter(items, &(&1.status == :open and Import.blocking?(&1, types[&1.batch_id])))

    state =
      cond do
        package.status == :approved -> :approved
        package.status == :awaiting_review and holding == [] -> :ready
        true -> :needs
      end

    group =
      Notes.group(%{
        undescribed: Map.get(ctx.undescribed, gall_id, false),
        text: Map.get(ctx.texts, gall_id),
        observations: Notes.observations?(content)
      })

    %{
      id: package.id,
      package: package,
      state: state,
      group: group,
      name: Map.get(ctx.galls, gall_id) || first_gall_name(content) || "A note",
      gall_id: gall_id,
      adds: Notes.adds(content, ctx.places),
      aside: Notes.set_aside(items),
      holding: length(holding),
      entries: if(state == :needs, do: holding_entries(package), else: [])
    }
  end

  # The note's Gall: the note's own ID, else its batch's first Gall's.
  defp note_gall_id(content) when is_map(content) do
    [
      get_in(content, ["source", "note", "gallformers_gall_id"]),
      content
      |> Map.get("galls")
      |> List.wrap()
      |> List.first()
      |> gall_field("gallformers_gall_id")
    ]
    |> Enum.find(&is_integer/1)
  end

  defp note_gall_id(_content), do: nil

  defp first_gall_name(content) when is_map(content),
    do:
      content |> Map.get("galls") |> List.wrap() |> List.first() |> gall_field("name_as_written")

  defp first_gall_name(_content), do: nil

  defp gall_field(%{} = gall, key), do: gall[key]
  defp gall_field(_gall, _key), do: nil

  # The open items that hold a note, as the curator reads them.
  defp holding_entries(package) do
    [package_data(package)]
    |> entries("the note")
    |> Enum.filter(& &1.holds)
  end

  @doc """
  A package with its batches, every queue item (decided ones too) and its
  statements by batch and ref: `%{package, batches, items, statements}`.
  """
  @spec package_data(Package.t()) :: map()
  def package_data(%Package{} = package) do
    batches = Import.list_batches(package)

    %{
      package: package,
      batches: batches,
      items:
        package
        |> Import.list_queue_items(status: :all)
        |> Enum.reject(&taxonomy_question?/1),
      statements:
        Map.new(batches, fn b -> {b.id, Map.new(Import.list_statements(b), &{&1.ref, &1})} end)
    }
  end

  @doc "What a page's batches state: Galls, statements about them, acts and what was set aside."
  @spec stats([map()]) :: %{
          galls: integer(),
          facts: integer(),
          acts: integer(),
          set_aside: integer()
        }
  def stats(packages) do
    contents = for p <- packages, b <- p.batches, b.status != :denied, do: b.content || %{}

    %{
      galls: count(contents, "galls"),
      facts: count(contents, "facts"),
      acts: count(contents, "acts"),
      set_aside: count(contents, "unmapped")
    }
  end

  defp count(contents, key), do: contents |> Enum.map(&length(List.wrap(&1[key]))) |> Enum.sum()

  # -- the items, as the curator reads them ------------------------------------------

  @doc """
  Every item of `packages` (from `package_data/1`) as an `t:entry/0`, with
  `who` (the Source's short name) in the copy.
  """
  @spec entries([map()], String.t() | nil, keyword()) :: [entry()]
  def entries(packages, who, opts \\ []) do
    items = Enum.flat_map(packages, & &1.items)
    step = Keyword.get(opts, :step)

    statements =
      packages |> Enum.flat_map(&Map.values(&1.statements)) |> Enum.flat_map(&Map.values/1)

    names = names(items, statements)
    definitions = definitions()
    batches = packages |> Enum.flat_map(& &1.batches) |> Map.new(&{&1.id, &1})
    by_batch = Map.new(packages |> Enum.flat_map(& &1.statements))

    shared =
      Map.merge(
        %{source: who, names: names, definitions: definitions, step: step},
        step_context(step, items, batches, who)
      )

    items
    |> Enum.map(fn item ->
      batch = batches[item.batch_id]
      statements = (item.batch_id && by_batch[item.batch_id]) || %{}
      written = if batch, do: written(batch), else: %{}
      content = (batch && batch.content) || %{}
      context = item_context(item, batch, statements, written, content, shared)
      question = Questions.present(item, context)

      item
      |> entry(question, batch, quotes(item, batch, written))
      |> Map.put(:decided, decided_text(item, question, names))
      |> Map.put(:comparison, comparison(item, question))
      |> host_context(question, content)
    end)
    |> group_disputes(who, names)
  end

  # -- disputes about the same statement (matter d213, Disputes step) --------------

  # Disputes about the same statement (`subject["group"]`, in one package)
  # are one entry: the first's, with every one of them as `members`, its
  # question covering them all (`Questions.group/2`, of the open ones while
  # any is open). It is open while any is.
  defp group_disputes(entries, who, names \\ %{}) do
    groups =
      entries
      |> Enum.filter(&group_key/1)
      |> Enum.group_by(&group_key/1)
      |> Map.filter(fn {_key, members} -> length(members) > 1 end)

    {grouped, _done} =
      Enum.flat_map_reduce(entries, MapSet.new(), fn entry, done ->
        key = group_key(entry)

        cond do
          not Map.has_key?(groups, key) -> {[entry], done}
          MapSet.member?(done, key) -> {[], done}
          true -> {[grouped(groups[key], who, names)], MapSet.put(done, key)}
        end
      end)

    grouped
  end

  defp group_key(%{item: %QueueItem{kind: :dispute, package_id: id, subject: %{"group" => g}}})
       when is_binary(g),
       do: {id, g}

  defp group_key(_entry), do: nil

  defp grouped(members, who, names) do
    open = Enum.filter(members, &(&1.item.status == :open))
    shown = if open == [], do: members, else: open
    [base | _] = shown

    %{
      base
      | question: Questions.group(Enum.map(shown, & &1.question), who),
        quotes: shown |> Enum.flat_map(& &1.quotes) |> Enum.uniq_by(& &1.text),
        decided: if(open == [], do: group_decided(members, names))
    }
    |> Map.put(:members, shown)
  end

  # How a group of disputes was decided: kept or dropped for every Gall, or
  # for how many each; kept on a plant chosen for them, which.
  defp group_decided(members, names) do
    n = length(members)
    kept = Enum.filter(members, &(&1.item.decision["keep"] == true))

    text =
      case {length(kept), n - length(kept)} do
        {_, 0} -> "Kept for #{every_gall(n)}"
        {0, _} -> "Dropped for #{every_gall(n)}"
        {k, d} -> "Kept for #{k} #{galls_noun(k)}; dropped for #{d}"
      end

    case kept |> Enum.map(& &1.item.decision["host_taxon_id"]) |> Enum.uniq() do
      [id] when is_integer(id) -> "#{text}, on #{taxon_label(id, names)}"
      _ -> text
    end
  end

  # A taxon by name, a section's as "sect. Lobatae".
  defp taxon_label(id, names) do
    case {Map.get(names, :taxa, %{})[id], Map.get(names, :ranks, %{})[id]} do
      {nil, _rank} -> "the plant chosen"
      {name, :section} -> "sect. #{name}"
      {name, _rank} -> name
    end
  end

  defp every_gall(2), do: "both Galls"
  defp every_gall(n), do: "all #{n} Galls"

  defp galls_noun(1), do: "Gall"
  defp galls_noun(_n), do: "Galls"

  # What a step's answers show besides (matter d213, Names and Galls steps):
  # the candidate taxa's identity lines and the genera the tree holds, the
  # candidate Galls' sides.
  defp step_context(:names, items, _batches, _who),
    do: %{taxa_info: taxa_info(items), held_genera: held_genera(items), galls: %{}}

  defp step_context(:galls, items, batches, who),
    do: %{taxa_info: %{}, held_genera: %{}, galls: gall_sides(items, batches, who)}

  defp step_context(_step, _items, _batches, _who),
    do: %{taxa_info: %{}, held_genera: %{}, galls: %{}}

  # What `Questions.present/2` reads of the item, its batch and the page.
  defp item_context(item, batch, statements, written, content, shared) do
    statement = statements[item.statement_ref]
    fact = batch && fact(batch, item)
    host = host_taxon(fact, statements)

    gall_view =
      if shared.step == :galls and gall_item?(item),
        do: gall_view(item, content, statements, shared.names, shared.galls)

    %{
      source: shared.source,
      names: shared.names,
      statement: statement && Map.take(statement, [:method, :flags, :detail]),
      fact: fact,
      written: written,
      definitions: shared.definitions,
      batch_type: batch && batch.batch_type,
      content: content,
      taxa_info: shared.taxa_info,
      held_genera: shared.held_genera,
      host_sections: host_sections(host || gall_host(gall_view)),
      host_rank: host_rank(host, fact, content),
      gall_view: gall_view
    }
  end

  # A Gall question's one Source Host, as its statement resolved.
  defp gall_host(%{source: %{hosts: [%{taxon_id: id}]}}) when is_integer(id),
    do: Taxa.get_taxon(id)

  defp gall_host(_gall_view), do: nil

  # A Host dispute's Host, as its statement resolved; nil for anything else.
  defp host_taxon(%{"type" => "host_of", "subject" => ref}, statements) do
    case statements[ref] do
      %{taxon_id: id} when is_integer(id) -> Taxa.get_taxon(id)
      _ -> nil
    end
  end

  defp host_taxon(_fact, _statements), do: nil

  # A Host dispute's Host, or a Gall question's, when it is a genus: its
  # sections, for the search for the plant meant (an unnamed oak is usually
  # a section's, d213).
  defp host_sections(%{rank: :genus, id: id}) do
    for child <- Taxa.children_with_ranks(id), child.rank == :section do
      %{id: child.taxon_id, name: child.name, common_name: List.first(child.common_names)}
    end
  end

  defp host_sections(_host), do: []

  # A Host dispute's Host's rank: the taxon it resolved to, else the rank
  # the batch declares it at (`Gallformers.Import.Disputes`: above species
  # rank, it is kept on a plant picked for its statements only).
  defp host_rank(%{rank: rank}, _fact, _content), do: rank

  defp host_rank(nil, %{"type" => "host_of", "subject" => ref}, content),
    do: declared_rank(ref, content)

  defp host_rank(_host, _fact, _content), do: nil

  # The rank the batch declares taxon `ref` at.
  defp declared_rank(ref, content) do
    declared = Enum.find(List.wrap(content["taxa"]), &(is_map(&1) and &1["ref"] == ref)) || %{}
    Enum.find(Rank.all(), &(to_string(&1) == declared["rank"]))
  end

  # -- what the answers show besides (matter d213, Names and Galls steps) -----------

  # The open name questions' candidate taxa (at most three each, as shown),
  # with their identity lines.
  defp taxa_info(items) do
    items
    |> Enum.filter(&(&1.status == :open and name_item?(&1)))
    |> Enum.flat_map(&shown_ids/1)
    |> Enum.uniq()
    |> Map.new(&{&1, ReviewContext.taxon(&1)})
    |> Map.reject(fn {_id, info} -> is_nil(info) end)
  end

  # The genera the tree holds named by the first word of an open name
  # question's name (one taxon of rank genus each), for a new species'
  # parent, by the word in lower case: `%{"andricus" => %{id, name}}`.
  defp held_genera(items) do
    items
    |> Enum.filter(&(&1.status == :open and name_item?(&1)))
    |> Enum.flat_map(fn %{subject: subject} ->
      subject = subject || %{}

      case String.split(subject["name_reading"] || subject["name_as_written"] || "") do
        [genus, _ | _] -> [String.downcase(genus)]
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn genus ->
      case Taxa.resolve_name(genus, rank: :genus) do
        {:ok, taxon} -> [{genus, %{id: taxon.id, name: Taxa.accepted_name(taxon)}}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp name_item?(%QueueItem{kind: kind, statement_ref: "t" <> _, subject: subject})
       when kind in [:ambiguous_match, :unresolved_name, :taxonomy_disagreement],
       do: (subject || %{})["host"] != true

  defp name_item?(_item), do: false

  defp gall_item?(%QueueItem{kind: kind, statement_ref: "g" <> _})
       when kind in [:ambiguous_match, :undescribed_gall, :unresolved_name],
       do: true

  defp gall_item?(_item), do: false

  # The candidates a question offers as answers: the proposed (or best)
  # first, at most three (`GallformersWeb.Admin.Review.Questions`).
  defp shown_ids(%QueueItem{proposal: proposal}) do
    proposal = proposal || %{}
    ids = proposal |> Map.get("candidate_ids") |> List.wrap() |> Enum.filter(&is_integer/1)

    ids =
      case proposal["proposed"] || proposal["best"] do
        id when is_integer(id) -> [id | List.delete(ids, id)]
        _ -> ids
      end

    Enum.take(ids, 3)
  end

  # What each candidate Gall of the open Gall questions is, by ID: its
  # name, Hosts, Traits and generation, photos and Sources, and its
  # description (which may quote this Source).
  defp gall_sides(items, batches, who) do
    open = Enum.filter(items, &(&1.status == :open and gall_item?(&1)))
    ids = open |> Enum.flat_map(&shown_ids/1) |> Enum.uniq()

    texts =
      for item <- open, id <- shown_ids(item), reduce: %{} do
        acc ->
          content = (batches[item.batch_id] && batches[item.batch_id].content) || %{}
          Map.put_new(acc, id, {description_text(content, item.statement_ref), content})
      end

    Map.new(ids, fn id ->
      {text, content} = Map.get(texts, id, {nil, %{}})
      {id, gall_side(id, text, title_of(content), who)}
    end)
  end

  defp gall_side(id, text, title, who) do
    summary = Catalog.gall_summary(id)

    context =
      ReviewContext.gall(id, text) ||
        %{photos: nil, sources: nil, quoted_in: nil, description: nil}

    %{
      id: id,
      hosts: Enum.map(summary.hosts, & &1.name),
      where: Map.get(summary.traits, "plant_part", []),
      detachable: Map.get(summary.traits, "detachable", []),
      generation: summary.generation,
      season: Map.get(summary.traits, "season", []),
      form: Map.get(summary.traits, "form", []),
      photos: context.photos,
      sources: context.sources,
      quoted_in: if(context.quoted_in == title and title, do: who, else: context.quoted_in),
      description: context.description
    }
  rescue
    Ecto.NoResultsError -> %{id: id}
  end

  defp title_of(content), do: get_in(content, ["source", "title"])

  # A Gall question's view: what the Source says of the Gall, what each
  # candidate is, and the generations of the candidates' group.
  defp gall_view(item, content, statements, names, galls) do
    ids = shown_ids(item)

    %{
      source: source_side(content, item.statement_ref, statements, names),
      galls: Map.take(galls, ids),
      generations: generations(Enum.map(ids, &get_in(galls, [&1, :generation])))
    }
  end

  # What the Source says of Gall `ref`: its Hosts (as resolved, with how it
  # wrote them), where on the plant, detachable, generation and season, form
  # and description, each with the Facts it rests on (those a curator may
  # leave out).
  defp source_side(content, ref, statements, names) do
    gall = content |> Map.get("galls") |> List.wrap() |> Enum.find(%{}, &(&1["ref"] == ref))
    ident = gall["identified_by"] || %{}
    written = written_in(content)

    facts =
      for f <- List.wrap(content["facts"]),
          is_map(f),
          Map.get(f, "stance", "confirm") == "confirm",
          do: f

    host_facts = Enum.filter(facts, &(&1["type"] == "host_of" and &1["object"] == ref))

    sides = %{statements: statements, names: names, written: written, content: content}

    hosts =
      host_facts
      |> Enum.group_by(& &1["subject"])
      |> Enum.map(fn {subject, fs} -> host_entry(subject, Enum.map(fs, & &1["id"]), sides) end)

    hosts =
      case ident["host"] do
        host when is_binary(host) ->
          if Enum.any?(host_facts, &(&1["subject"] == host)),
            do: hosts,
            else: hosts ++ [host_entry(host, [], sides)]

        _ ->
          hosts
      end

    traits = for f <- facts, f["kind"] == "trait", f["gall"] == ref, do: f

    %{
      hosts: hosts,
      where: ident_part(ident["plant_part"]) ++ trait_entries(traits, "plant_part"),
      detachable: trait_entries(traits, "detachable"),
      generation: get_in(ident, ["generation", "value"]),
      season: trait_entries(traits, "season"),
      form: trait_entries(traits, "form"),
      text: description_text(content, ref)
    }
  end

  # A Source Host: its name as resolved and as written, the Facts it rests
  # on, and its taxon and rank (the taxon's, else the one the batch
  # declares: above species rank, it goes on another plant for this Gall
  # only, `Gallformers.Import.GallDecisions`).
  defp host_entry(subject, refs, %{statements: statements, names: names, written: written} = s) do
    as_written = written[subject]

    taxon =
      case statements[subject] do
        %{taxon_id: id} when is_integer(id) -> Taxa.get_taxon(id)
        _ -> nil
      end

    name = taxon && (names.taxa[taxon.id] || Taxa.accepted_name(taxon))

    %{
      name: name || as_written || "a plant",
      written: as_written,
      refs: refs,
      taxon_id: taxon && taxon.id,
      rank: if(taxon, do: taxon.rank, else: declared_rank(subject, s.content))
    }
  end

  defp ident_part(%{"value" => value} = part) when is_binary(value),
    do: [%{value: value, term: part["as_written"], refs: []}]

  defp ident_part(_part), do: []

  # A trait's statements: format 4's category (one value or several) and
  # term, format 3's value and its words.
  defp trait_entries(traits, trait) do
    for %{"trait" => ^trait} = f <- traits,
        values = List.wrap(get_in(f, ["category", "value"]) || get_in(f, ["value", "value"])),
        values != [],
        do: %{
          value: Enum.join(values, ", "),
          term: f["term"] || get_in(f, ["value", "as_written"]),
          refs: [f["id"]]
        }
  end

  # The Source's description of Gall `ref`: its description Facts' quotes.
  defp description_text(content, ref) do
    quotes =
      for %{"kind" => "description", "gall" => ^ref} = f <- List.wrap(content["facts"]),
          e <- List.wrap(f["evidence"]),
          is_binary(e["quote"]),
          do: e["quote"]

    if quotes != [], do: Enum.join(quotes, " … ")
  end

  # The values of the generation group the candidates' generations are in.
  defp generations(held) do
    case Enum.find(held, &is_binary/1) do
      nil ->
        []

      value ->
        Catalog.list_generation_groups()
        |> Enum.find(fn g -> Enum.any?(g.values, &(&1.value == value)) end)
        |> case do
          nil -> []
          group -> Enum.map(group.values, & &1.value)
        end
    end
  end

  # A Host question's genera (to expand an abbreviation) and the plant its
  # "Create a new plant" link starts with.
  defp host_context(entry, %{section: %{id: :hosts}}, content) do
    genera = genera(content)
    Map.merge(entry, %{genera: genera, new_plant: new_plant(entry.item, genera)})
  end

  defp host_context(entry, _question, _content), do: entry

  # The plant a Host the tree doesn't hold starts as on the New Taxon page
  # (matter f14c): the Source's name for it (`name_reading`, else
  # `name_as_written`), an abbreviated genus written out with the one genus
  # of that initial the batch writes in full (as
  # `Gallformers.Import.HostDecisions` writes it out with the plant's); its
  # rank by its name; under its genus when the tree holds it. A Host named
  # only by a common name starts with no name.
  defp new_plant(%QueueItem{status: :open, subject: subject}, genera) do
    subject = subject || %{}

    name =
      if subject["common_name"] != true,
        do:
          (subject["name_reading"] || subject["name_as_written"] || "")
          |> String.split()
          |> Enum.join(" ")
          |> expand_genus(genera)

    case name do
      blank when blank in [nil, ""] ->
        %{name: nil, rank: :species, parent_id: nil}

      name ->
        %{
          name: name,
          rank: Import.wcvp_rank(%{taxon_name: name}),
          parent_id: plant_genus(name)
        }
    end
  end

  defp new_plant(_item, _genera), do: nil

  defp expand_genus(name, genera) do
    with [_, initial, rest] <- Regex.run(~r/\A([A-Z])\.\s*(.+)\z/, name),
         [genus] <- Enum.filter(genera, &String.starts_with?(&1, initial)) do
      "#{genus} #{rest}"
    else
      _ -> name
    end
  end

  defp plant_genus(name) do
    with [genus, _ | _] <- String.split(name),
         {:ok, taxon} <- Taxa.resolve_name(genus, rank: :genus, kingdom: "Plantae") do
      taxon.id
    else
      _ -> nil
    end
  end

  # The genera the batch writes in full, to expand "Q. lobata".
  defp genera(content) do
    for t <- List.wrap(content["taxa"]),
        is_map(t),
        name = t["name_reading"] || t["name_as_written"],
        is_binary(name),
        [genus | _] = String.split(name),
        not String.ends_with?(genus, "."),
        String.length(genus) > 1,
        uniq: true,
        do: genus |> String.downcase() |> String.capitalize()
  end

  defp entry(item, question, batch, quotes) do
    accept = accept(item, question)

    %{
      item: item,
      question: question,
      quotes: quotes,
      decided: nil,
      comparison: [],
      genera: [],
      new_plant: nil,
      holds: item.status == :open and Import.blocking?(item, batch && batch.batch_type),
      rejected: rejected?(item),
      accept: accept,
      proposable: match?({:firm, _}, accept)
    }
  end

  # What Accept decides: the proposal (`Gallformers.Import.proposed_decision/1`),
  # which bulk accept takes too, or a suggestion to check, only one by one.
  defp accept(%QueueItem{status: :open} = item, question) do
    case Import.proposed_decision(item) do
      {:ok, decision} ->
        {:firm, decision}

      {:none, :weak} ->
        case question.proposal do
          %{pending: false, decision: decision} when is_map(decision) -> {:suggestion, decision}
          _ -> nil
        end

      {:none, _reason} ->
        nil
    end
  end

  defp accept(_item, _question), do: nil

  # The candidates of a name several species hold, to compare.
  defp comparison(%QueueItem{status: :open} = item, %{topic: :several_species}),
    do: Import.candidate_comparison(item)

  defp comparison(_item, _question), do: []

  # What a decided item was decided as, in the words of the choice it took.
  # An old decision's note shows with the item's notes, not here.
  defp decided_text(%QueueItem{status: :decided, decision: decision}, question, names) do
    choice_text(Map.delete(decision || %{}, "note"), question, names)
  end

  defp decided_text(_item, _question, _names), do: nil

  defp choice_text(choice, question, names) do
    case Enum.find(question.choices, &(&1.decision == choice)) do
      %{label: label} -> String.trim_trailing(label, "…")
      nil -> picked_text(choice, names)
    end
  end

  defp picked_text(%{"keep" => true, "host_reading" => %{"taxon_id" => id} = r}, names),
    do: "Kept, its Host read as #{names.taxa[id] || r["name"] || "another plant"}"

  defp picked_text(%{"keep" => true, "host_taxon_id" => id}, names),
    do: "Kept, its Host set to #{taxon_label(id, names)}"

  defp picked_text(%{"taxon_id" => id}, names), do: names.taxa[id] || "a taxon"

  defp picked_text(%{"new" => true, "parent_id" => id}, names),
    do: "Created under #{names.taxa[id] || "the taxon picked"}"

  defp picked_text(%{"new" => true, "generation" => v}, _names),
    do: "Created as the #{v} generation's Gall"

  defp picked_text(%{"new" => true}, _names), do: "Created new"
  defp picked_text(%{"gall_id" => id}, names), do: names.galls[id] || "a Gall"
  defp picked_text(%{"source_id" => id}, names), do: names.sources[id] || "a Source"
  defp picked_text(%{"wcvp_id" => _}, _names), do: "A plant added from WCVP"
  defp picked_text(%{"trait_value" => v}, _names), do: "Mapped to #{v}"

  defp picked_text(%{"place" => [_ | _] = values}, _names),
    do: "Placed under #{and_list(values)} for every Source"

  defp picked_text(%{"place" => c}, _names), do: "Placed under #{c} for every Source"
  defp picked_text(%{"category" => c}, _names), do: "#{c}, for these Galls only"
  defp picked_text(%{"categories" => _}, _names), do: "Decided Gall by Gall"
  defp picked_text(%{"value" => v}, _names), do: "Changed to #{v}"
  defp picked_text(%{"state" => _}, _names), do: "Stated"
  defp picked_text(%{"skip" => true}, _names), do: "Left out of the import"
  defp picked_text(%{"decline" => true, "reason" => r}, _names), do: "Declined: #{r}"

  defp picked_text(%{"history" => true}, _names),
    do: "Closed as history: a newer statement was accepted"

  defp picked_text(choice, _names) when map_size(choice) == 0, do: "Acknowledged"
  defp picked_text(_choice, _names), do: "Decided"

  defp and_list([one]), do: one
  defp and_list(list), do: Enum.join(Enum.drop(list, -1), ", ") <> " and " <> List.last(list)

  @doc "Whether a curator rejected `item`'s proposal (`Gallformers.Import.reject_proposal/2`)."
  @spec rejected?(QueueItem.t()) :: boolean()
  def rejected?(item), do: match?(%DateTime{}, Map.get(item, :proposal_rejected_at))

  @doc "The Trait values' definitions, `%{trait => %{value => definition}}`."
  @spec definitions() :: %{String.t() => %{String.t() => String.t() | nil}}
  def definitions do
    Catalog.list_trait_values()
    |> Enum.group_by(& &1.trait)
    |> Map.new(fn {trait, values} -> {trait, Map.new(values, &{&1.value, &1.definition})} end)
  end

  # The batch's names as written, by ref.
  defp written(%Batch{content: content}), do: written_in(content)

  defp written_in(content) do
    for key <- ["taxa", "galls"],
        entry <- List.wrap((content || %{})[key]),
        is_map(entry) and is_binary(entry["ref"]) and is_binary(entry["name_as_written"]),
        into: %{},
        do: {entry["ref"], entry["name_as_written"]}
  end

  # The batch statement (a Fact, act, taxon or Gall) a dispute is about, decoded.
  defp fact(%Batch{content: content}, %QueueItem{kind: :dispute, statement_ref: ref}) do
    content = content || %{}

    Enum.find_value(["facts", "acts", "taxa", "galls"], fn key ->
      content
      |> Map.get(key)
      |> List.wrap()
      |> Enum.find(&(is_map(&1) and (&1["id"] == ref or &1["ref"] == ref)))
    end)
  end

  defp fact(_batch, _item), do: nil

  # -- quotes ----------------------------------------------------------------------

  @max_quotes 3

  # The Source's words an item rests on: for a Trait term, none here (each
  # covered Gall shows its own); for something set aside, each covered
  # Gall's; for a statement, its own evidence; for a name or a Gall, the
  # evidence of the Facts that name it.
  defp quotes(%QueueItem{kind: :trait_term}, _batch, _written), do: []

  defp quotes(%QueueItem{kind: kind} = item, _batch, _written) when kind in @set_aside_kinds do
    item.subject
    |> Map.get("covers")
    |> List.wrap()
    |> Enum.flat_map(fn cover -> evidence(cover["evidence"], cover["name_as_written"]) end)
    |> finish()
  end

  defp quotes(_item, nil, _written), do: []

  defp quotes(%QueueItem{statement_ref: ref}, %Batch{content: content}, written)
       when is_binary(ref) do
    content = content || %{}
    statements = List.wrap(content["facts"]) ++ List.wrap(content["acts"])

    own = Enum.filter(statements, &(is_map(&1) and &1["id"] == ref))

    naming =
      Enum.filter(statements, fn s ->
        is_map(s) and s["id"] != ref and ref in refs_of(s)
      end)

    (own ++ naming)
    |> Enum.flat_map(&evidence(&1["evidence"], where(&1, written)))
    |> finish()
  end

  defp quotes(_item, _batch, _written), do: []

  defp refs_of(statement) do
    ~w(subject object gall taxon parent name accepted)
    |> Enum.map(&statement[&1])
    |> Enum.filter(&is_binary/1)
  end

  # Where in the Source a statement's quote is: the Gall it is about.
  defp where(statement, written) do
    ref = statement["gall"] || (statement["kind"] == "relationship" && statement["object"])
    if is_binary(ref), do: written[ref]
  end

  defp evidence(evidence, where) do
    for e <- List.wrap(evidence),
        is_map(e),
        is_binary(e["quote"]) and e["quote"] != "",
        do: %{text: e["quote"], where: where, item: e["item"]}
  end

  defp finish(quotes), do: quotes |> Enum.uniq_by(& &1.text) |> Enum.take(@max_quotes)

  # -- names -----------------------------------------------------------------------

  @doc """
  The names of the taxa, Galls and Sources that `items` and `statements`
  speak of, by ID (`%{taxa: %{id => name}, galls: ..., sources: ...}`),
  and the taxa's ranks (`ranks: %{id => rank}`).
  """
  @spec names([QueueItem.t()], [map()]) :: map()
  def names(items, statements \\ []) do
    ids = Enum.reduce(items, %{taxa: [], galls: [], sources: []}, &item_ids/2)
    ids = Enum.reduce(statements, ids, &statement_ids/2)

    lineages = ids.taxa |> Enum.uniq() |> Taxa.lineages()

    %{
      taxa: Map.new(lineages, fn {id, lineage} -> {id, List.last(lineage).name} end),
      ranks: Map.new(lineages, fn {id, lineage} -> {id, List.last(lineage).rank} end),
      galls:
        ids.galls |> Enum.uniq() |> Catalog.list_galls_by_id() |> Map.new(&{&1.id, gall_name(&1)}),
      sources:
        ids.sources |> Enum.uniq() |> Sources.list_sources_by_id() |> Map.new(&{&1.id, &1.title})
    }
  end

  defp gall_name(%{name_override: override}) when is_binary(override), do: override
  defp gall_name(%{name: name}), do: name

  defp item_ids(%QueueItem{} = item, acc) do
    proposal = item.proposal || %{}
    subject = item.subject || %{}
    decision = item.decision || %{}
    candidates = ints([proposal["proposed"] | List.wrap(proposal["candidate_ids"])])

    suggested =
      proposal
      |> Map.get("suggestions")
      |> List.wrap()
      |> Enum.map(&(is_map(&1) && &1["taxon_id"]))

    acc =
      case item.statement_ref do
        ref when ref in ["source", "retracts"] -> add(acc, :sources, candidates)
        "g" <> _ -> add(acc, :galls, candidates)
        _ -> add(acc, :taxa, candidates)
      end

    acc
    |> add(:taxa, ints(suggested))
    |> add(:galls, ints([subject["gall_id"], decision["gall_id"]]))
    |> add(
      :taxa,
      ints([
        subject["inducer_id"],
        decision["taxon_id"],
        decision["parent_id"],
        decision["host_taxon_id"]
      ])
    )
    |> add(:sources, ints([decision["source_id"]]))
  end

  defp statement_ids(%{kind: :taxon} = s, acc),
    do: add(acc, :taxa, ints([s.taxon_id | s.candidate_ids]))

  defp statement_ids(%{kind: :gall} = s, acc),
    do: add(acc, :galls, ints([s.gall_id | s.candidate_ids]))

  defp statement_ids(_statement, acc), do: acc

  defp add(acc, key, ids), do: Map.update!(acc, key, &(ids ++ &1))
  defp ints(values), do: Enum.filter(values, &is_integer/1)

  # -- the Source's summary ----------------------------------------------------------

  defp source_map(ids) do
    ids
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Sources.list_sources_by_id()
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  What the pages show of a Source: `%{title, citation, kind, year, who}`;
  `who` is what the pages call it, its short name ("Ashmead 1897",
  `Gallformers.Sources.short_name/1`), nil when it names no author.
  """
  @spec source_summary(Source.t()) :: map()
  def source_summary(%Source{kind: :gallformers} = source) do
    %{
      title: "Gallformers ID Notes",
      citation: source.citation || source.title,
      kind: "Gallformers notes",
      year: year(source),
      who: "the note"
    }
  end

  def source_summary(%Source{} = source) do
    %{
      title: source.title,
      citation: source.citation,
      kind: @kind_labels[source.kind && Atom.to_string(source.kind)],
      year: year(source),
      who: Sources.short_name(source)
    }
  end

  # A package not matched to a Source yet: its batches' Source block.
  defp block_summary(batches) do
    block =
      Enum.find_value(batches, %{}, fn b -> is_map(b.content) && b.content["source"] end) || %{}

    year = block |> get_in(["authored", "date"]) |> parse_year()

    %{
      title: block["title"] || block["citation"] || "A Source not matched yet",
      citation: block["citation"],
      kind:
        if(block["gallformers"] == true,
          do: "Gallformers notes",
          else: @kind_labels[block["kind"]]
        ),
      year: year,
      who: Sources.short_name(List.wrap(block["authors"]), year)
    }
  end

  defp year(%Source{authored_date: %Date{year: year}}), do: year
  defp year(%Source{pubyear: pubyear}), do: parse_year(pubyear)

  defp parse_year(text) when is_binary(text) do
    case Regex.run(~r/\d{4}/, text) do
      [y] -> String.to_integer(y)
      _ -> nil
    end
  end

  defp parse_year(_text), do: nil
end
