defmodule GallformersWeb.Palette do
  @moduledoc """
  What the command palette offers (design system, matters bc0d and ec2c):
  groups of rows, each row a place to go.

  With nothing typed: the fixed Go to list, and for a curator their
  commands (Edit this page, Add from observation…, Sources to review,
  Changes). For a query: Go to shortcuts into the ID tool ("Galls on
  *Quercus alba*", "… in Virginia", "Galls in Virginia"), for a curator
  "Review: <Source>" for each Source found that has an import under review,
  then the matches by kind (`Gallformers.Search.global_search/2`, and
  published articles by title), and last, every result on the search page.

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
          index: non_neg_integer()
        }

  @type group :: %{title: String.t() | nil, rows: [row()]}

  @doc """
  The palette's groups for `query`. Options: `admin?` (a curator's
  commands).
  """
  @spec groups(String.t(), keyword()) :: [group()]
  def groups(query, opts \\ []) do
    admin? = Keyword.get(opts, :admin?, false)

    case String.trim(query) do
      "" -> start(admin?)
      q -> results(q, admin?)
    end
    |> Enum.reject(&(&1.rows == []))
    |> number()
  end

  defp start(admin?) do
    [
      %{
        title: "Go to",
        rows: [
          row(
            "ph-magnifying-glass-plus",
            "Identify a gall",
            "/id",
            "Start from the plant it's on"
          ),
          row("gf-gall", "Browse galls", "/galls", "By what causes them"),
          row("gf-host", "Browse host plants", "/hosts"),
          row("gf-place", "Browse places", "/places"),
          row("ph-article", "Articles", "/articles"),
          row("ph-tree-structure", "Identification keys", "/keys"),
          row("ph-book-open", "Glossary", "/glossary")
        ]
      },
      %{
        title: "Curators",
        rows:
          if(admin?,
            do: [
              row("ph-pencil-simple", "Edit this page", "?edit", "Turn on Edit here"),
              row(
                "ph-eye",
                "Add from observation…",
                "/admin/observation",
                "An iNaturalist observation into your tray"
              ),
              row("ph-check-circle", "Sources to review", "/admin/review"),
              row("ph-list", "Changes", "/admin/changes", "What curators changed")
            ],
            else: []
          )
      }
    ]
  end

  # A package still being reviewed (`GallformersWeb.Admin.ReviewLive.Loader`'s).
  @reviewable [:validated, :resolving, :awaiting_review]

  defp results(q, admin?) do
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
      suffix: nil
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
