defmodule Gallformers.CatalogMigration.Report do
  @moduledoc """
  What a data-migration run did (`Gallformers.CatalogMigration`), for the
  person running it:

    * `reconciliation` — each class of old rows against what became of
      them: `old` = `new` plus the rows `accounted` for otherwise (e.g. genus
      placeholders, which become no taxon). An entry that does not balance
      means rows went missing.
    * `counts` — figures worth knowing (Inducers merged, Facts created, ...).
    * `duplicates` — taxa sharing an accepted name, rank and kingdom. The
      replay log finds taxa by that key (`Gallformers.Import.StableRef`), so
      replay stops on them.
    * `needs_review` — Galls read through a mapping row a curator must check
      (`priv/catalog_migration/name_suffixes.csv`).
    * `unparsed` — gall names the mapping cannot read; nothing was guessed.
    * `problems` — other rows a curator should look at, by category.
    * `pending` — rows of the curated inputs (`priv/catalog_migration/*.csv`,
      `Gallformers.CatalogMigration.Curated`) that need a decision and have
      none, or whose decision cannot be applied. A strict run stops on
      these and on `duplicates` (`blocking?/1`); a lenient run skips them.
    * `curation` — the worksheets for the curated inputs, by name
      (`"non_galls"`, `"ranges"`, `"aliases"`, `"keys"`): every row the
      input covers with its decision so far, written as CSV by
      `write_curation/2`.
  """

  alias Gallformers.CatalogMigration.Curated

  @type entry :: %{
          label: String.t(),
          old: non_neg_integer(),
          new: non_neg_integer(),
          accounted: [{String.t(), non_neg_integer()}]
        }

  @type gall_note :: %{gall_id: integer(), name: String.t(), reason: String.t()}

  @type duplicate :: %{
          name: String.t(),
          rank: atom(),
          kingdom: String.t() | nil,
          taxon_ids: [integer()]
        }

  @type problem :: %{category: String.t(), detail: String.t()}

  @typedoc "A curated row awaiting a decision: its input file, its key in that file, a line."
  @type pending :: %{input: String.t(), key: term(), detail: String.t()}

  @type worksheet :: %{columns: [String.t()], rows: [map()]}

  @type t :: %__MODULE__{
          reconciliation: [entry()],
          counts: [{String.t(), non_neg_integer()}],
          duplicates: [duplicate()],
          needs_review: [gall_note()],
          unparsed: [gall_note()],
          problems: [problem()],
          pending: [pending()],
          curation: %{String.t() => worksheet()}
        }

  defstruct reconciliation: [],
            counts: [],
            duplicates: [],
            needs_review: [],
            unparsed: [],
            problems: [],
            pending: [],
            curation: %{}

  # Pending rows printed per input; the worksheets hold them all.
  @pending_shown 100

  @doc "Adds a reconciliation entry: `old` rows became `new` plus `accounted`."
  @spec reconcile(t(), String.t(), non_neg_integer(), non_neg_integer(), [
          {String.t(), non_neg_integer()}
        ]) :: t()
  def reconcile(%__MODULE__{} = report, label, old, new, accounted \\ []) do
    entry = %{
      label: label,
      old: old,
      new: new,
      accounted: Enum.reject(accounted, &(elem(&1, 1) == 0))
    }

    %{report | reconciliation: report.reconciliation ++ [entry]}
  end

  @doc "Adds a count."
  @spec count(t(), String.t(), non_neg_integer()) :: t()
  def count(%__MODULE__{} = report, label, n),
    do: %{report | counts: report.counts ++ [{label, n}]}

  @doc "Adds problems of one `category`, each a detail line."
  @spec problems(t(), String.t(), [String.t()]) :: t()
  def problems(%__MODULE__{} = report, category, details) do
    %{
      report
      | problems: report.problems ++ Enum.map(details, &%{category: category, detail: &1})
    }
  end

  @doc "Adds Galls to `:needs_review` or `:unparsed`."
  @spec galls(t(), :needs_review | :unparsed, [gall_note()]) :: t()
  def galls(%__MODULE__{} = report, list, notes) when list in [:needs_review, :unparsed],
    do: Map.update!(report, list, &(&1 ++ notes))

  @doc "Adds curated rows of `input` (a file name) awaiting a decision: `{key, detail}` pairs."
  @spec pending(t(), String.t(), [{term(), String.t()}]) :: t()
  def pending(%__MODULE__{} = report, input, rows) do
    added = for {key, detail} <- rows, do: %{input: input, key: key, detail: detail}
    %{report | pending: report.pending ++ added}
  end

  @doc "Sets the worksheet `name`: its `columns` in order and its `rows` (maps by column)."
  @spec curation(t(), String.t(), [String.t()], [map()]) :: t()
  def curation(%__MODULE__{} = report, name, columns, rows),
    do: put_in(report.curation[name], %{columns: columns, rows: rows})

  @doc """
  Whether a strict run must stop: curated rows await decisions, or taxa
  share a replay key (`duplicates`).
  """
  @spec blocking?(t()) :: boolean()
  def blocking?(%__MODULE__{pending: pending, duplicates: duplicates}),
    do: pending != [] or duplicates != []

  @doc "Writes each worksheet to `dir` as `<name>_report.csv`; returns the paths."
  @spec write_curation(t(), String.t()) :: [String.t()]
  def write_curation(%__MODULE__{curation: curation}, dir) do
    File.mkdir_p!(dir)

    for {name, %{columns: columns, rows: rows}} <- Enum.sort(curation) do
      path = Path.join(dir, "#{name}_report.csv")
      :ok = Curated.write(path, columns, rows)
      path
    end
  end

  @doc "Whether an entry's old rows are all accounted for."
  @spec balanced?(entry()) :: boolean()
  def balanced?(%{old: old, new: new, accounted: accounted}),
    do: old == new + Enum.sum(Enum.map(accounted, &elem(&1, 1)))

  @doc "The report as text."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = report) do
    [
      "Catalog migration report",
      "",
      "Reconciliation (old = new + accounted):",
      Enum.map(report.reconciliation, &entry_line/1),
      "",
      "Counts:",
      Enum.map(report.counts, fn {label, n} -> "  #{label}: #{n}" end),
      "",
      section(
        "Duplicates of accepted name + rank + kingdom (replay stops on these)",
        report.duplicates,
        fn d ->
          "#{d.name} (#{d.rank}, #{d.kingdom || "no kingdom"}): taxa #{Enum.join(d.taxon_ids, ", ")}"
        end
      ),
      section(
        "Needs review (name-suffix rows a curator must check)",
        report.needs_review,
        &gall_line/1
      ),
      section("Unparsed gall names (no Inducer guessed)", report.unparsed, &gall_line/1),
      section("Other problems", report.problems, &"[#{&1.category}] #{&1.detail}"),
      worksheets(report.curation),
      pending_section(report.pending)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp worksheets(curation) do
    [
      "Curation worksheets (written with --reports):",
      for({name, %{rows: rows}} <- Enum.sort(curation), do: "  #{name}: #{length(rows)} rows"),
      ""
    ]
  end

  defp pending_section(pending) do
    by_input = Enum.group_by(pending, & &1.input)

    [
      "Pending curated decisions (a strict run stops on these): #{length(pending)}",
      for {input, rows} <- Enum.sort(by_input) do
        shown = Enum.take(rows, @pending_shown)
        more = length(rows) - length(shown)

        [
          "  #{input}: #{length(rows)}",
          Enum.map(shown, &"    #{&1.detail}"),
          if(more > 0, do: ["    ... and #{more} more (see the worksheet)"], else: [])
        ]
      end,
      ""
    ]
  end

  defp entry_line(entry) do
    accounted = Enum.map(entry.accounted, fn {label, n} -> " + #{n} #{label}" end)
    flag = if balanced?(entry), do: "ok", else: "MISMATCH"
    "  [#{flag}] #{entry.label}: #{entry.old} = #{entry.new}#{accounted}"
  end

  defp gall_line(note), do: "#{note.gall_id} #{note.name}: #{note.reason}"

  defp section(title, items, line) do
    ["#{title}: #{length(items)}", Enum.map(items, &("  " <> line.(&1))), ""]
  end
end
