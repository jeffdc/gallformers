defmodule Gallformers.Import.ReviewContext do
  @moduledoc """
  What the review pages' questions need from the database (`d213` Task 13,
  "Research burden" and "Ten-question test"): the facts a curator would
  otherwise look up in another tab, read for the presenter
  (`GallformersWeb.Admin.Review.Questions`) to put on the questions.

    * `taxon/1` — a taxon candidate's identity line: its accepted name,
      rank, authorship (when the tree records it, which it mostly doesn't),
      family, synonyms, and its Galls and their Hosts in Gallformers;
      `holds_name/2` says whether it already holds the Source's name.
    * `host/2` — for a Host name as written: what WCVP holds for it, or its
      nearest spelling in the genus, the record's status and accepted name,
      and whether Gallformers holds that plant. Nil fields when WCVP has
      nothing (the page then links to POWO and IPNI searches).
    * `gall/2` — a candidate Gall's photos and Sources, its description,
      and whether one of its descriptions quotes this Source. The field-by-field comparison is
      `Gallformers.Import.GallComparison`'s.
    * `document/1` — the package's `document.json`, decoded, for
      `Gallformers.Import.Passages`.

  Nothing here writes.
  """

  alias Gallformers.Catalog
  alias Gallformers.Import.HostSuggestions
  alias Gallformers.Import.Package
  alias Gallformers.Storage.Private
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @plantae "Plantae"
  # How much of a Source's text a Gall's description must contain to quote it.
  @quote_length 30
  # How many of an epithet's letters a synonym must share to be a close spelling.
  @epithet_prefix 6
  # The Host suggestions' matches that are another spelling of the name.
  @near_matches ["spelling_variant", "edit_distance"]

  @type taxon_ref :: %{taxon_id: integer(), name: String.t()}

  @type taxon :: %{
          taxon_id: integer(),
          name: String.t(),
          rank: Gallformers.Taxa.Rank.t(),
          authorship: String.t() | nil,
          family: String.t() | nil,
          synonyms: [String.t()],
          galls: [%{id: integer(), name: String.t()}],
          hosts: [taxon_ref()]
        }

  @type wcvp_record :: %{
          id: String.t(),
          name: String.t(),
          authors: String.t() | nil,
          status: String.t() | nil
        }

  @type host :: %{
          written: String.t(),
          match: :exact | :near | nil,
          wcvp: wcvp_record() | nil,
          accepted: %{id: String.t(), name: String.t(), authors: String.t() | nil} | nil,
          held: taxon_ref() | nil
        }

  @type gall :: %{
          gall_id: integer(),
          photos: non_neg_integer(),
          sources: non_neg_integer(),
          quoted_in: String.t() | nil,
          description: String.t() | nil
        }

  @type holding ::
          :exact | {:close_spelling, String.t()} | {:same_epithet_other_genus, String.t()} | :no

  # -- taxa --------------------------------------------------------------------

  @doc """
  Taxon `id`'s identity line, or nil when there is no such taxon. `galls`
  are the Galls it induces (by name), `hosts` the distinct Hosts of those
  Galls (by name); their counts are the lists' lengths.
  """
  @spec taxon(integer()) :: taxon() | nil
  def taxon(id) when is_integer(id) do
    case Taxa.get_taxon(id) do
      nil -> nil
      taxon -> identity(taxon)
    end
  end

  defp identity(taxon) do
    accepted = Enum.find(taxon.names, &(&1.status == :accepted))
    summaries = Catalog.list_gall_summaries_by_inducer([taxon.id])

    %{
      taxon_id: taxon.id,
      name: accepted.name,
      rank: taxon.rank,
      authorship: accepted.authorship,
      family: Enum.find_value(Taxa.lineage(taxon.id), &(&1.rank == :family && &1.name)),
      synonyms: for(n <- taxon.names, n.status == :synonym, do: n.name),
      galls:
        summaries
        |> Enum.map(&%{id: &1.gall_id, name: &1.name})
        |> Enum.sort_by(&{&1.name, &1.id}),
      hosts:
        summaries
        |> Enum.flat_map(& &1.hosts)
        |> Enum.uniq_by(& &1.taxon_id)
        |> Enum.map(&%{taxon_id: &1.taxon_id, name: &1.name})
        |> Enum.sort_by(&{&1.name, &1.taxon_id})
    }
  end

  @doc """
  Whether a taxon (`%{name, synonyms}`, as `taxon/1` gives it) already holds
  the Source's name `written`, compared normalized
  (`Gallformers.Taxa.NameNormalizer`):

    * `:exact` — its accepted name or one of its synonyms;
    * `{:close_spelling, synonym}` — a synonym in the same genus whose last
      epithet shares its first six letters with the written one;
    * `{:same_epithet_other_genus, synonym}` — such a synonym in another
      genus;
    * `:no` — none: the candidate matched on the species name only.
  """
  @spec holds_name(%{name: String.t(), synonyms: [String.t()]}, String.t()) :: holding()
  def holds_name(%{name: name, synonyms: synonyms}, written) when is_binary(written) do
    wanted = NameNormalizer.normalize(written)
    words = String.split(wanted)

    cond do
      Enum.any?([name | synonyms], &(NameNormalizer.normalize(&1) == wanted)) ->
        :exact

      near = Enum.find(synonyms, &same_epithet?(&1, words)) ->
        if genus(near) == List.first(words),
          do: {:close_spelling, near},
          else: {:same_epithet_other_genus, near}

      true ->
        :no
    end
  end

  defp same_epithet?(synonym, words) do
    epithet_start(synonym |> NameNormalizer.normalize() |> String.split()) ==
      epithet_start(words)
  end

  defp epithet_start([]), do: nil
  defp epithet_start(words), do: words |> List.last() |> String.slice(0, @epithet_prefix)

  defp genus(name), do: name |> NameNormalizer.normalize() |> String.split() |> List.first()

  # -- Hosts -------------------------------------------------------------------

  @doc """
  What WCVP and Gallformers hold for Host name `written`, through the Host
  suggestions (`Gallformers.Import.HostSuggestions`):

    * `match` — `:exact` when WCVP holds the name itself (as written, as a
      hybrid), `:near` when only another spelling of it in the genus (an
      ending, or a near spelling; also the spelling the tree holds it
      under), nil when WCVP has nothing;
    * `wcvp` — that record: `%{id, name, authors, status}`;
    * `accepted` — the record WCVP names as accepted for it, when that is
      another record (nil when the record is itself accepted, or WCVP names
      none, as for an unplaced name);
    * `held` — Gallformers' plant for it: WCVP's plant, linked or by name;
      else the name as written, or the tree's spelling of it.

  `opts`: `:wcvp` (the WCVP lookup; default the configured `:wcvp_lookup`),
  `:genera` (to expand a genus abbreviation, as the resolver's context).
  """
  @spec host(String.t(), keyword()) :: host()
  def host(written, opts \\ []) when is_binary(written) do
    context = %{
      genera: Keyword.get(opts, :genera, []),
      wcvp:
        Keyword.get_lazy(opts, :wcvp, fn ->
          Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)
        end)
    }

    suggestions = suggestions(written, context)
    {match, record} = wcvp_record(suggestions, context)

    %{
      written: written,
      match: match,
      wcvp: record && wcvp_fields(record),
      accepted: record && accepted_fields(record["accepted"]),
      held: held(record, written, suggestions)
    }
  end

  defp suggestions(name, context) do
    case HostSuggestions.suggest(%{"name_as_written" => name}, context, kingdom: @plantae) do
      %{suggestions: suggestions} -> suggestions
      nil -> []
    end
  end

  # The WCVP record for the name, else its nearest spelling. When the tree
  # holds the name in another spelling the suggestions stop there, so that
  # spelling is looked up in WCVP.
  defp wcvp_record(suggestions, context) do
    cond do
      record = Enum.find(suggestions, &wcvp_exact?/1) ->
        {:exact, record}

      record = Enum.find(suggestions, &(wcvp?(&1) and &1["match"] in @near_matches)) ->
        {:near, record}

      tree =
          Enum.find(suggestions, &(&1["source"] == "tree" and &1["match"] == "spelling_variant")) ->
        case tree["name"] |> suggestions(context) |> Enum.find(&wcvp_exact?/1) do
          nil -> {nil, nil}
          record -> {:near, record}
        end

      true ->
        {nil, nil}
    end
  end

  defp wcvp?(suggestion), do: suggestion["source"] == "wcvp"
  defp wcvp_exact?(s), do: wcvp?(s) and s["match"] in ["exact", "synonym"]

  defp wcvp_fields(record) do
    %{
      id: record["wcvp_id"],
      name: record["name"],
      authors: record["authors"],
      status: record["wcvp_status"]
    }
  end

  defp accepted_fields(nil), do: nil
  defp accepted_fields(a), do: %{id: a["wcvp_id"], name: a["name"], authors: a["authors"]}

  defp held(%{"taxon_id" => id}, _written, _suggestions) when is_integer(id), do: taxon_ref(id)

  defp held(_record, written, suggestions) do
    case Taxa.resolve_name(written, kingdom: @plantae) do
      {:ok, taxon} ->
        taxon_ref(taxon.id)

      _ ->
        Enum.find_value(suggestions, fn s ->
          s["source"] == "tree" and s["match"] == "spelling_variant" and taxon_ref(s["taxon_id"])
        end)
    end
  end

  defp taxon_ref(id), do: %{taxon_id: id, name: Taxa.accepted_name(id)}

  # -- Galls -------------------------------------------------------------------

  @doc """
  Gall `id`'s photos and Sources, counted as its page lists them
  (`Gallformers.Catalog.gall_page/1`), and `quoted_in`: the title of its
  Source whose description quotes `text` (a Source's text about the Gall),
  else nil. A description quotes a text when it contains the text's first
  30 characters, compared without case and with spacing collapsed (a text
  shorter than that quotes nothing). `description` is the Gall's
  description as its page leads with it: its default Source's, else the
  first non-empty one (nil when it has none). Nil when there is no such
  Gall.
  """
  @spec gall(integer(), String.t() | nil) :: gall() | nil
  def gall(id, text) when is_integer(id) do
    case Catalog.gall_page(id) do
      {:ok, page} ->
        %{
          gall_id: page.id,
          photos: length(page.images),
          sources: length(page.sources),
          quoted_in: quoted_in(page.sources, text),
          description: description(page.sources)
        }

      :not_found ->
        nil
    end
  end

  defp description(sources) do
    described = Enum.filter(sources, &(is_binary(&1.description) and &1.description != ""))
    source = Enum.find(described, & &1.useasdefault) || List.first(described)
    source && source.description
  end

  defp quoted_in(_sources, text) when not is_binary(text), do: nil

  defp quoted_in(sources, text) do
    start = text |> squish() |> String.slice(0, @quote_length)

    if String.length(start) == @quote_length do
      Enum.find_value(sources, &(quotes?(&1, start) && &1.title))
    end
  end

  defp quotes?(source, start), do: String.contains?(squish(source.description || ""), start)

  defp squish(text), do: text |> String.downcase() |> String.split() |> Enum.join(" ")

  # -- the document ------------------------------------------------------------

  @doc """
  The package's `document.json` from the private bucket, decoded:
  `{:error, :not_found}` when it wasn't delivered, `{:error, :invalid_json}`
  when it isn't a JSON object.
  """
  @spec document(Package.t()) :: {:ok, map()} | {:error, :not_found | :invalid_json | term()}
  def document(%Package{s3_prefix: prefix}) when is_binary(prefix) do
    with {:ok, bytes} <- Private.get(prefix <> "document.json") do
      case Jason.decode(bytes) do
        {:ok, %{} = doc} -> {:ok, doc}
        _ -> {:error, :invalid_json}
      end
    end
  end
end
