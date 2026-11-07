defmodule GallformersWeb.Palette do
  @moduledoc """
  What the command palette offers (design system, matters bc0d and ec2c):
  groups of rows, each row a place to go.

  With nothing typed: for a curator whose tray holds changes, Your changes
  first (Review and apply, then the changes, `Gallformers.Curation.summary/1`'s
  lines); then the fixed Go to list, and for a curator their commands (Edit
  this page, Add from observation…, Sources to review, Changes).

  For a query: the commands whose words the typed words start (Go to's,
  a curator's, and Review and apply while their tray holds changes), then
  Go to shortcuts into the ID tool ("Galls on *Quercus alba*", "… in
  Virginia", "Galls in Virginia"), for a curator "Review: <Source>" for
  each Source found that has an import under review, then the matches by
  kind (`Gallformers.Search.global_search/2`, and published articles by
  title), and last, every result on the search page. Commands come first
  when the typed words start words of a command's name; when they match
  only its other words (its description and synonyms), or the query is a
  single character, the commands come after the results, just before every
  result.

  A row is a place to go (`href`), or with `action: :review` opens the
  tray's Review and apply (`GallformersWeb.TrayLive`).

  Rows are numbered (`index`) across the groups, for the keyboard.
  """
  alias Gallformers.{Articles, Import, Search}
  alias GallformersWeb.TaxonomyURL

  @type row :: %{
          icon: String.t(),
          label: String.t(),
          href: String.t(),
          detail: String.t() | nil,
          name: boolean(),
          prefix: String.t() | nil,
          suffix: String.t() | nil,
          action: :review | nil,
          index: non_neg_integer()
        }

  @type group :: %{title: String.t() | nil, rows: [row()]}

  @typedoc "A curator's tray (`Gallformers.Curation.summary/1`)."
  @type changes :: %{count: non_neg_integer(), lines: [String.t()]} | nil

  # How many of the tray's changes the palette lists.
  @changes_shown 5
  # How many commands a query shows.
  @commands_shown 5

  @doc """
  The palette's groups for `query`. Options: `admin?` (a curator's
  commands) and `changes` (a curator's tray, `Gallformers.Curation.summary/1`).
  """
  @spec groups(String.t(), keyword()) :: [group()]
  def groups(query, opts \\ []) do
    admin? = Keyword.get(opts, :admin?, false)
    changes = if admin?, do: Keyword.get(opts, :changes)

    case String.trim(query) do
      "" -> start(admin?, changes)
      q -> results(q, admin?, changes)
    end
    |> Enum.reject(&(&1.rows == []))
    |> number()
  end

  defp start(admin?, changes) do
    [
      %{title: "Your changes", rows: your_changes(changes)},
      %{title: "Go to", rows: Enum.map(go_to(), &elem(&1, 0))},
      %{title: "Curators", rows: Enum.map(curators(admin?, nil), &elem(&1, 0))}
    ]
  end

  # Each command with the other words it is found by (besides its name and
  # description).
  defp go_to do
    [
      {row(
         "ph-magnifying-glass-plus",
         "Identify a gall",
         "/id",
         "Start from the plant it's on"
       ), ~w(id tool)},
      {row("gf-gall", "Browse galls", "/galls", "By what causes them"), []},
      {row("gf-host", "Browse host plants", "/hosts"), ~w(hosts)},
      {row("gf-place", "Browse places", "/places"), []},
      {row("ph-article", "Articles", "/articles"), []},
      {row("ph-tree-structure", "Identification keys", "/keys"), []},
      {row("ph-book-open", "Glossary", "/glossary"), ~w(terms)}
    ]
  end

  defp curators(false, _changes), do: []

  defp curators(true, changes) do
    review_and_apply(changes) ++
      [
        {row("ph-pencil-simple", "Edit this page", "?edit", "Turn on Edit here"), []},
        {row(
           "ph-eye",
           "Add from observation…",
           "/admin/observation",
           "An iNaturalist observation into your tray"
         ), ~w(inat intake)},
        {row("ph-check-circle", "Sources to review", "/admin/review"), ~w(imports)},
        {row("ph-list", "Changes", "/admin/changes", "What curators changed"), ~w(history recent)}
      ]
  end

  # Review and apply, while the tray holds changes (a command when typed).
  defp review_and_apply(%{count: count} = changes) when count > 0,
    do: [{review_row(changes), ~w(tray changes)}]

  defp review_and_apply(_changes), do: []

  defp your_changes(%{count: count, lines: lines} = changes) when count > 0 do
    [
      review_row(changes)
      | for(line <- Enum.take(lines, @changes_shown), do: review(row("ph-pencil", line, "#")))
    ]
  end

  defp your_changes(_changes), do: []

  defp review_row(%{count: count}),
    do:
      review(
        row(
          "ph-check",
          "Review and apply",
          "#",
          "#{count} #{if count == 1, do: "change", else: "changes"} in your tray"
        )
      )

  defp review(row), do: %{row | action: :review}

  # The commands the typed words find: {by name, by other words}. Each word
  # typed must start a word of the command (its name; else its name,
  # description and synonyms).
  defp commands(q, admin?, changes), do: commands_for(words(q), admin?, changes)

  # Punctuation alone has no words to match.
  defp commands_for([], _admin?, _changes), do: {[], []}

  defp commands_for(typed, admin?, changes) do
    {by_name, by_other} =
      (go_to() ++ curators(admin?, changes))
      |> Enum.map(fn {row, also} -> {row, match(typed, row, also)} end)
      |> Enum.reject(&(elem(&1, 1) == nil))
      |> Enum.split_with(&(elem(&1, 1) == :name))

    {Enum.map(by_name, &elem(&1, 0)), Enum.map(by_other, &elem(&1, 0))}
  end

  defp match(typed, row, also) do
    name = words(row.label)

    cond do
      starts_all?(typed, name) -> :name
      starts_all?(typed, name ++ words(row.detail || "") ++ also) -> :other
      true -> nil
    end
  end

  defp starts_all?(typed, words),
    do: Enum.all?(typed, fn t -> Enum.any?(words, &String.starts_with?(&1, t)) end)

  defp words(text), do: text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)

  # A package still being reviewed (`GallformersWeb.Admin.ReviewLive.Loader`'s).
  @reviewable [:validated, :resolving, :awaiting_review]

  defp results(q, admin?, changes) do
    {by_name, by_other} = commands(q, admin?, changes)

    {first, last} =
      if String.length(q) > 1 and by_name != [],
        do: {by_name ++ by_other, []},
        else: {[], by_name ++ by_other}

    q
    |> search_groups(admin?)
    |> List.insert_at(0, %{title: "Commands", rows: Enum.take(first, @commands_shown)})
    |> List.insert_at(-2, %{title: "Commands", rows: Enum.take(last, @commands_shown)})
  end

  defp search_groups(q, admin?) do
    found = Search.global_search(q)

    groups =
      for {title, key, limit, to_row} <- [
            {"Galls", :galls, 4, &gall_row/1},
            {"Host plants", :hosts, 4, &host_row/1},
            {"Groups", :taxonomy, 4, &group_row/1},
            {"Places", :places, 3, &place_row/1},
            {"Sources", :sources, 3, &source_row/1},
            {"Glossary", :glossary, 2, &glossary_row/1}
          ] do
        %{title: title, rows: found |> Map.fetch!(key) |> Enum.take(limit) |> Enum.map(to_row)}
      end

    [%{title: "Go to", rows: shortcuts(List.first(found.hosts), List.first(found.places))}] ++
      [%{title: "Review", rows: if(admin?, do: review_rows(found.sources), else: [])}] ++
      groups ++
      [
        %{title: "Articles", rows: Enum.map(Articles.search_published(q, 2), &article_row/1)},
        %{title: nil, rows: [every_result(q)]}
      ]
  end

  defp gall_row(g), do: named("gf-gall", g.name, "/gall/#{g.id}", also(g))
  defp host_row(h), do: named("gf-host", h.name, "/host/#{h.id}", also(h))

  defp group_row(t),
    do: row("gf-taxon", t.name, TaxonomyURL.public_path(t) || "/", t.rank || t.type)

  defp place_row(p), do: row("gf-place", p.name, "/place/#{p.code}", p[:kind])
  defp source_row(s), do: row("gf-source", s.name, "/source/#{s.id}")

  defp glossary_row(e),
    do: row("gf-entry", e.name, "/glossary##{String.downcase(e.name)}", e[:definition])

  defp article_row(a), do: row("ph-article", a.title, "/articles/#{a.slug}", a.author)

  # "Review: <Source>" for the Sources found with an import under review.
  defp review_rows([]), do: []

  defp review_rows(sources) do
    reviewing =
      Import.list_packages(status: @reviewable).entries |> MapSet.new(& &1.source_id)

    for s <- sources, MapSet.member?(reviewing, s.id) do
      row(
        "ph-check-circle",
        "Review: #{s.name}",
        "/admin/review/sources/#{s.id}",
        "Sources to review"
      )
    end
  end

  defp every_result(q),
    do:
      row(
        "ph-magnifying-glass",
        "See every result for “#{q}”",
        "/globalsearch?" <> URI.encode_query(%{q: q})
      )

  defp shortcuts(host, place) do
    [
      host &&
        %{
          named("ph-magnifying-glass-plus", host.name, id_tool(h: host.name), "In the ID tool")
          | prefix: "Galls on "
        },
      host && place &&
        %{
          named(
            "ph-magnifying-glass-plus",
            host.name,
            id_tool(h: host.name, pl: place.code),
            "In the ID tool"
          )
          | prefix: "Galls on ",
            suffix: " in #{place.name}"
        },
      place &&
        row(
          "ph-magnifying-glass-plus",
          "Galls in #{place.name}",
          "/place/#{place.code}",
          "Every gall known there"
        )
    ]
    |> Enum.filter(& &1)
  end

  defp id_tool(params), do: "/id?" <> URI.encode_query(params)

  defp also(%{aliases: [first | _]}) when is_binary(first), do: "also #{first}"
  defp also(_), do: nil

  defp row(icon, label, href, detail \\ nil),
    do: %{
      icon: icon,
      label: label,
      href: href,
      detail: detail,
      name: false,
      prefix: nil,
      suffix: nil,
      action: nil
    }

  # A row whose label is a scientific name.
  defp named(icon, name, href, detail), do: %{row(icon, name, href, detail) | name: true}

  defp number(groups) do
    {numbered, _} =
      Enum.map_reduce(groups, 0, fn group, next ->
        rows =
          group.rows
          |> Enum.with_index(next)
          |> Enum.map(fn {row, i} -> Map.put(row, :index, i) end)

        {%{group | rows: rows}, next + length(rows)}
      end)

    numbered
  end
end
