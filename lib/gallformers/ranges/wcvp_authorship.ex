defmodule Gallformers.Ranges.WcvpAuthorship do
  @moduledoc """
  Plants' authorship from WCVP (matter `f14c`, "Other decisions": plants
  get their authorship from WCVP, whose data Gallformers holds). A plant's
  names are editorial (`8567`, "Plants are the exception"), so WCVP's
  authors are written straight to `taxon_names.authorship`, audited, with
  no Fact.

  A plant (Plantae at species rank or below) name's WCVP record is:

    * for the accepted name, the record the plant is linked to
      (`taxon_wcvp.wcvp_id`) when that record is of the same name (a link
      found through a synonym is a record of another name, and gives none);
    * otherwise the records of the same name, ignoring case, at the same
      rank (WCVP's `taxon_rank`; a synonym's rank, and a record's without
      one, read from the name's infraspecific marker): one, or several
      giving the same authors; when they differ, those in the synonymy of
      the plant's linked record (the record itself, or sharing its accepted
      name).

  A name with several records giving different authors and nothing to
  choose between them is **ambiguous**: left blank and counted.

  `backfill/2` fills every plant name that has no authorship (a one-off,
  idempotent; the catalog migration runs it, and
  `mix gallformers.wcvp.authorship` / `Gallformers.Release.backfill_wcvp_authorship/0`
  on a database already migrated). `follow_link/3` keeps a plant current
  when its WCVP link changes (`Gallformers.Ranges.Wcvp.put_link/3`, which
  every link write goes through: adding a plant from WCVP, a match, a sync,
  the replay log). An authorship a curator gave is never overwritten.

  The WCVP data comes from the configured lookup (`:wcvp_lookup`, default
  `Gallformers.Wcvp.Lookup`; a stub in tests).
  """
  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Ranges.TaxonWcvp
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName

  @typedoc """
  What a backfill found, by plant name: `names` checked; `matched`, those
  WCVP holds unambiguously, of which `filled` took WCVP's authors now,
  `unchanged` already had them, `kept` hold another authorship (left
  alone) and `no_authorship` WCVP gives none for (an autonym, say);
  `ambiguous` (each `%{taxon_id, name}`, left blank); `not_in_wcvp`.
  """
  @type summary :: %{
          names: non_neg_integer(),
          matched: non_neg_integer(),
          filled: non_neg_integer(),
          unchanged: non_neg_integer(),
          kept: non_neg_integer(),
          no_authorship: non_neg_integer(),
          ambiguous: [%{taxon_id: integer(), name: String.t()}],
          not_in_wcvp: non_neg_integer()
        }

  defp lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)

  @doc """
  Gives every plant name that has no authorship WCVP's authors, where WCVP
  holds the name unambiguously, audited as `actor`. Options: `:taxon_ids`
  (only these taxa; default every plant), `:lookup` (default the
  configured one). Running it again fills nothing more.
  `{:error, :wcvp_unavailable}` when the WCVP database cannot be read
  (nothing is written).
  """
  @spec backfill(Actor.t(), keyword()) :: {:ok, summary()} | {:error, :wcvp_unavailable}
  def backfill(%Actor{} = actor, opts \\ []) do
    lookup = Keyword.get_lazy(opts, :lookup, &lookup/0)

    if lookup.available?() do
      resolved = opts |> Keyword.get(:taxon_ids) |> plant_names() |> resolve(lookup)

      Audit.transaction(actor, "ranges.wcvp_authorship.backfill", fn -> fill(actor, resolved) end)
    else
      {:error, :wcvp_unavailable}
    end
  end

  defp fill(actor, resolved) do
    resolved
    |> Enum.reduce(empty_summary(), fn {row, outcome}, summary ->
      tally(actor, row, outcome, summary)
    end)
    |> Map.update!(:ambiguous, &Enum.reverse/1)
  end

  defp empty_summary,
    do: %{
      names: 0,
      matched: 0,
      filled: 0,
      unchanged: 0,
      kept: 0,
      no_authorship: 0,
      ambiguous: [],
      not_in_wcvp: 0
    }

  defp tally(actor, %{name: name}, outcome, summary) do
    summary = %{summary | names: summary.names + 1}

    case {outcome, name.authorship} do
      {:not_in_wcvp, _} ->
        %{summary | not_in_wcvp: summary.not_in_wcvp + 1}

      {:ambiguous, _} ->
        entry = %{taxon_id: name.taxon_id, name: name.name}
        %{summary | ambiguous: [entry | summary.ambiguous]}

      {{:matched, nil}, _} ->
        bump(summary, :no_authorship)

      {{:matched, authors}, nil} ->
        {:ok, _} = Taxa.set_name_authorship(actor, name, authors)
        bump(summary, :filled)

      {{:matched, authors}, authors} ->
        bump(summary, :unchanged)

      {{:matched, _authors}, _other} ->
        bump(summary, :kept)
    end
  end

  defp bump(summary, field),
    do: summary |> Map.update!(:matched, &(&1 + 1)) |> Map.update!(field, &(&1 + 1))

  @doc """
  Keeps plant `taxon_id`'s authorship current after its WCVP link changed
  from `previous_wcvp_id` (nil when it had none): its names with no
  authorship take WCVP's, and its accepted name's authorship, when it is
  the previous record's (WCVP's, not a curator's), becomes the new one's.
  Nothing happens for a taxon that is no plant, or when WCVP cannot be
  read.
  """
  @spec follow_link(Actor.t(), integer(), String.t() | nil) :: :ok
  def follow_link(%Actor{} = actor, taxon_id, previous_wcvp_id) when is_integer(taxon_id) do
    lookup = lookup()

    with true <- lookup.available?(),
         [_ | _] = rows <- plant_names([taxon_id]) do
      previous = previous_authors(lookup, previous_wcvp_id)

      {:ok, :ok} =
        Audit.transaction(actor, "ranges.wcvp_authorship.follow_link", fn ->
          for {%{name: name}, {:matched, authors}} <- resolve(rows, lookup),
              authors != nil,
              follows?(name, authors, previous),
              do: {:ok, _} = Taxa.set_name_authorship(actor, name, authors)

          :ok
        end)
    end

    :ok
  end

  defp previous_authors(_lookup, id) when id in [nil, ""], do: nil

  defp previous_authors(lookup, id) do
    case lookup.get_names([id]) do
      [record | _] -> authors(record)
      [] -> nil
    end
  end

  defp follows?(%TaxonName{authorship: nil}, _authors, _previous), do: true
  defp follows?(%TaxonName{authorship: authors}, authors, _previous), do: false

  defp follows?(%TaxonName{status: :accepted, authorship: current}, _authors, previous),
    do: previous != nil and current == previous

  defp follows?(_name, _authors, _previous), do: false

  # -- finding the records -------------------------------------------------------

  # Each plant name (accepted first) with its taxon's rank and WCVP link.
  defp plant_names(taxon_ids) do
    query =
      from(n in TaxonName,
        join: t in Taxon,
        on: t.id == n.taxon_id,
        left_join: w in TaxonWcvp,
        on: w.taxon_id == t.id,
        where: t.kingdom == "Plantae" and t.rank in ^Rank.species_and_below(),
        order_by: [n.taxon_id, n.status, n.id],
        select: %{name: n, rank: t.rank, wcvp_id: w.wcvp_id}
      )

    query = if taxon_ids, do: where(query, [n], n.taxon_id in ^taxon_ids), else: query
    Repo.all(query)
  end

  # Each row with its outcome: `{:matched, authors | nil}`, `:ambiguous` or
  # `:not_in_wcvp`.
  defp resolve(rows, lookup) do
    linked =
      rows
      |> Enum.map(& &1.wcvp_id)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> then(&lookup.get_names/1)
      |> Map.new(&{&1.plant_name_id, &1})

    by_name =
      rows
      |> Enum.map(& &1.name.name)
      |> then(&lookup.find_names/1)
      |> Enum.group_by(&key(&1.taxon_name))

    for row <- rows, do: {row, outcome(row, row.wcvp_id && linked[row.wcvp_id], by_name)}
  end

  defp outcome(%{name: %TaxonName{status: :accepted} = name} = row, link, by_name) do
    if link && key(link.taxon_name) == key(name.name),
      do: {:matched, authors(link)},
      else: by_name(name.name, row.rank, link, by_name)
  end

  defp outcome(%{name: name}, link, by_name),
    do: by_name(name.name, name_rank(name.name), link, by_name)

  defp by_name(name, rank, link, by_name) do
    candidates = by_name |> Map.get(key(name), []) |> Enum.filter(&(record_rank(&1) == rank))

    case candidates do
      [] -> :not_in_wcvp
      _ -> choose(candidates, link)
    end
  end

  defp choose(candidates, link) do
    case distinct_authors(candidates) do
      [authors] ->
        {:matched, authors}

      _ when link != nil ->
        case candidates |> Enum.filter(&in_synonymy?(&1, link)) |> distinct_authors() do
          [authors] -> {:matched, authors}
          _ -> :ambiguous
        end

      _ ->
        :ambiguous
    end
  end

  defp distinct_authors(records), do: records |> Enum.map(&authors/1) |> Enum.uniq()

  defp in_synonymy?(record, link),
    do: record.plant_name_id == link.plant_name_id or accepted_id(record) == accepted_id(link)

  defp accepted_id(%{accepted_plant_name_id: id, plant_name_id: own}),
    do: if(id in [nil, ""], do: own, else: id)

  defp authors(%{taxon_authors: authors}) when is_binary(authors) do
    case String.trim(authors) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp authors(_record), do: nil

  defp key(name), do: name |> String.downcase() |> String.split() |> Enum.join(" ")

  # A WCVP rank Gallformers has none for matches no plant's.
  defp record_rank(record), do: Wcvp.rank(record) || :other

  # A name's rank read from its infraspecific marker.
  defp name_rank(name), do: Wcvp.rank(%{taxon_name: name})

  # -- the summary ---------------------------------------------------------------

  @doc "A backfill's summary as text, each ambiguous name on a line."
  @spec format(summary()) :: String.t()
  def format(summary) do
    lines = [
      "Plant names: #{summary.names}",
      "  WCVP holds unambiguously: #{summary.matched} — given WCVP's authorship now: " <>
        "#{summary.filled}; already WCVP's: #{summary.unchanged}; keeping their own: " <>
        "#{summary.kept}; WCVP gives none: #{summary.no_authorship}",
      "  ambiguous in WCVP: #{length(summary.ambiguous)} (left blank)"
    ]

    ambiguous = for a <- summary.ambiguous, do: "    #{a.name} (taxon #{a.taxon_id})"

    Enum.join(lines ++ ambiguous ++ ["  not in WCVP: #{summary.not_in_wcvp}"], "\n")
  end
end
