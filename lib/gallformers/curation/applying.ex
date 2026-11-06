defmodule Gallformers.Curation.Applying do
  @moduledoc """
  Applying tray items (matter `ec2c`, `apply/2`): each item on its own,
  never all-or-nothing.

    * **Editorial items** apply at once through the functions the admin
      screens use: a Gall's fields through `Gallformers.Catalog.update_gall_editorial/3`
      and `Gallformers.Catalog.update_name_parts/3`; a plant's name,
      synonyms and range through the taxonomy admin's replay-logged edits
      (`Gallformers.Import.record_taxonomy_edit/2`,
      `Gallformers.Import.record_synonym_added/4`,
      `Gallformers.Import.record_host_range_saved/4`), with its "based on"
      note (`Gallformers.Import.record_taxon_note/5`), in one transaction.
    * **Notes** apply at once (`Gallformers.Import.record_fact_note/5`).
    * **Fact items** become one gall batch of Gallformers' statements
      (`Gallformers.Curation.Statements`,
      `Gallformers.Import.GallformersFragment`), its Galls and taxa given
      by ID, submitted as a package of its own
      (`Gallformers.Import.submit_gallformers_fragment/2`) for the import
      job to apply. The items wait in the tray for its outcome
      (`settle/1`). A Fact item Gallformers itself states already, with
      the same Observations, is a no-op: it leaves the tray with nothing
      submitted. A newer Gallformers statement keeps the Observations its
      earlier one cited.

  `dry_run/2` applies an editorial item or note in a transaction that is
  always rolled back, so Review sees every check the apply makes.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Curation.Item
  alias Gallformers.Curation.Review
  alias Gallformers.Curation.Spec
  alias Gallformers.Curation.Statements
  alias Gallformers.Import
  alias Gallformers.Import.GallformersFragment
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @doc "An item's evidence: its own, else the set's (both decoded)."
  @spec evidence(Item.t(), map() | nil) :: map() | nil
  def evidence(%Item{evidence: nil}, set_evidence), do: set_evidence
  def evidence(%Item{evidence: own}, _set_evidence), do: own

  # -- editorial items and notes -------------------------------------------------

  @doc "Applies an editorial item or a note: `:ok` or `{:error, reason}` (words)."
  @spec run(Actor.t(), Item.t()) :: :ok | {:error, String.t()}
  def run(actor, %Item{kind: :note, spec: spec}) do
    actor
    |> Import.record_fact_note(spec.gall_id, spec.key, spec.text)
    |> result()
  end

  def run(actor, %Item{kind: :editorial, spec: %{subject: {:gall, id}} = spec}) do
    case Catalog.get_gall(id) do
      nil -> {:error, "the Gall is gone"}
      gall -> gall_edit(actor, gall, spec.field, spec.value) |> result()
    end
  end

  def run(actor, %Item{kind: :editorial, spec: %{subject: {:plant, id}} = spec}) do
    Audit.transaction(actor, "curation.apply_plant_edit", fn ->
      actor |> plant_edit(id, spec.field, spec.value) |> unwrap_or_rollback()

      if spec.based_on,
        do:
          actor
          |> Import.record_taxon_note(id, Atom.to_string(spec.field), spec.based_on)
          |> unwrap_or_rollback()

      :ok
    end)
    |> result()
  end

  @doc "Applies `item` in a transaction that is rolled back: `:ok` or `{:error, reason}`."
  @spec dry_run(Actor.t(), Item.t()) :: :ok | {:error, String.t()}
  def dry_run(actor, item) do
    {:error, outcome} = Repo.transaction(fn -> Repo.rollback({:dry_run, run(actor, item)}) end)
    {:dry_run, result} = outcome
    result
  end

  defp gall_edit(actor, gall, :completeness, value),
    do: Catalog.update_gall_editorial(actor, gall, %{datacomplete: value})

  defp gall_edit(actor, gall, :abundance, value),
    do: Catalog.update_gall_editorial(actor, gall, %{abundance_id: value})

  defp gall_edit(actor, gall, :code, value),
    do: Catalog.update_gall_editorial(actor, gall, %{gallformers_code: value || ""})

  defp gall_edit(actor, gall, :default_source_id, value),
    do: Catalog.update_gall_editorial(actor, gall, %{default_source_id: value})

  defp gall_edit(actor, gall, :name_parts, parts),
    do: Catalog.update_name_parts(actor, gall, parts)

  defp plant_edit(actor, id, :name, name),
    do: Import.record_taxonomy_edit(actor, {:rename, id, name})

  defp plant_edit(actor, id, :range, entries),
    do: Import.record_host_range_saved(actor, id, entries, %{})

  defp plant_edit(actor, id, :synonyms, wanted) do
    current = Taxa.list_synonyms(id)
    same = fn s, w -> s.name == w.name and s.sensu == w.sensu end

    with :ok <-
           each(current, &(not Enum.any?(wanted, fn w -> same.(&1, w) end)), fn s ->
             Import.record_taxonomy_edit(actor, {:remove_synonym, s.id})
           end) do
      each(wanted, &(not Enum.any?(current, fn s -> same.(s, &1) end)), fn w ->
        opts = if w.sensu, do: [sensu: w.sensu], else: []
        Import.record_synonym_added(actor, id, w.name, opts)
      end)
    end
    |> case do
      :ok -> {:ok, :ok}
      error -> error
    end
  end

  defp each(list, keep?, fun) do
    Enum.reduce_while(Enum.filter(list, keep?), :ok, fn x, :ok ->
      case fun.(x) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp result({:ok, _}), do: :ok
  defp result({:error, reason}), do: {:error, reason_text(reason)}

  @doc "Why something was refused, in words."
  @spec reason_text(term()) :: String.t()
  def reason_text(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> flatten_errors()
    |> Enum.join("; ")
  end

  def reason_text(:no_fact), do: "Gallformers holds no such Fact"
  def reason_text(:not_found), do: "it is gone"
  def reason_text(reason) when is_binary(reason), do: reason

  def reason_text(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  def reason_text(reason), do: inspect(reason)

  defp flatten_errors(errors, prefix \\ nil) do
    Enum.flat_map(errors, fn
      {field, messages} when is_list(messages) ->
        Enum.flat_map(messages, fn
          message when is_binary(message) -> ["#{join(prefix, field)} #{message}"]
          nested when is_map(nested) -> flatten_errors(nested, join(prefix, field))
        end)

      {field, nested} when is_map(nested) ->
        flatten_errors(nested, join(prefix, field))
    end)
  end

  defp join(nil, field), do: String.replace(to_string(field), "_", " ")
  defp join(prefix, field), do: "#{prefix} #{String.replace(to_string(field), "_", " ")}"

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)

  # -- Fact items ----------------------------------------------------------------

  @doc """
  Submits Fact `items` (decorated, each with its evidence) as one package:
  `{:ok, package, refs}` (the Fact refs each item became, by item ID),
  `{:error, reason}` for all of them, and the items held back because a
  statement cannot name their Gall (`[{item, reason}]`).
  """
  @spec submit(Actor.t(), [{Item.t(), map() | nil}]) ::
          {{:ok, Import.Package.t(), %{integer() => [String.t()]}} | {:error, String.t()} | nil,
           [{Item.t(), String.t()}]}
  def submit(actor, items) do
    today = Date.utc_today()

    {named, unnamed} =
      items
      |> Enum.group_by(fn {item, _evidence} -> item.spec.gall_id end)
      |> Enum.map(fn {gall_id, entries} ->
        statements =
          for {item, evidence} <- entries,
              do: {item, Statements.for_item(item.spec, keep_observations(item, evidence), today)}

        {gall_id, statements}
      end)
      |> Enum.split_with(fn {gall_id, statements} ->
        match?(
          {:ok, _},
          GallformersFragment.gall_batch(
            Catalog.gall_summary(gall_id),
            Enum.flat_map(statements, &elem(&1, 1))
          )
        )
      end)

    held =
      for {_gall_id, statements} <- unnamed,
          {item, _facts} <- statements,
          do: {item, "the Gall has neither an Inducer nor a Host, so a statement cannot name it"}

    {submitted(actor, named), held}
  end

  # Gallformers' newer statement replaces its earlier one on the same Fact,
  # so it carries the Observations the earlier one cited as well.
  defp keep_observations(item, evidence) do
    case Review.kept_observations(item.spec) do
      [] ->
        evidence

      kept ->
        evidence = evidence || %{}
        new = evidence[:observations] || []
        seen = MapSet.new(new, &{to_string(&1.provider), to_string(&1.id)})

        Map.put(
          evidence,
          :observations,
          new ++ Enum.reject(kept, &MapSet.member?(seen, {&1.provider, &1.id}))
        )
    end
  end

  defp submitted(_actor, []), do: nil

  defp submitted(actor, galls) do
    {entries, refs, _n} =
      Enum.reduce(galls, {[], %{}, 0}, fn {gall_id, statements}, {entries, refs, n} ->
        {facts, refs, n} =
          Enum.reduce(statements, {[], refs, n}, fn {item, facts}, {acc, refs, n} ->
            ids = for i <- 1..length(facts), do: "f#{n + i}"
            {acc ++ facts, Map.put(refs, item.id, ids), n + length(facts)}
          end)

        {entries ++ [{Catalog.gall_summary(gall_id), facts}], refs, n}
      end)

    with {:ok, batch} <- GallformersFragment.galls_batch(entries, taxon_ids: true),
         {:ok, package} <- Import.submit_gallformers_fragment(actor, %{"gall.json" => batch}) do
      {:ok, package, refs}
    else
      {:error, reason} -> {:error, "the statement could not be submitted: #{reason_text(reason)}"}
    end
  end

  # -- outcomes ------------------------------------------------------------------

  @typedoc "What became of a submitted item."
  @type outcome :: :applied | {:waiting_review, integer()} | {:held, String.t()} | :waiting

  @doc """
  The outcome of each of `items` (submitted in package `package_id`) as the
  package stands: `:applied` once its batch is applied and the item's
  statements were written; `{:waiting_review, package_id}` while it waits
  for an admin; `{:held, reason}` when the import refused it, turned it
  down, or wrote the batch without the item's statements; `:waiting` while
  the job has yet to take it on.
  """
  @spec outcomes(integer(), [Item.t()]) :: [{Item.t(), outcome()}]
  def outcomes(package_id, items) do
    package = Import.get_package!(package_id)

    case package.status do
      :invalid ->
        reason = "the import refused the statement: " <> problems(package)
        Enum.map(items, &{&1, {:held, reason}})

      :denied ->
        reason = "turned down: #{package.denied_reason}"
        Enum.map(items, &{&1, {:held, reason}})

      :awaiting_review ->
        Enum.map(items, &{&1, {:waiting_review, package.id}})

      :approved ->
        written(package, items)

      _ ->
        Enum.map(items, &{&1, :waiting})
    end
  end

  defp problems(package) do
    case for(%{"level" => "error"} = p <- package.problems, do: p["message"]) do
      [] -> "no reason given"
      messages -> Enum.join(messages, "; ")
    end
  end

  defp written(package, items) do
    case Import.list_batches(package) do
      [_ | _] = batches ->
        if Enum.all?(batches, &(&1.status == :applied)) do
          statements =
            batches
            |> Enum.flat_map(&Import.list_statements/1)
            |> Enum.filter(&(&1.kind == :fact))
            |> Enum.group_by(&base_ref(&1.ref))

          Enum.map(items, &{&1, item_written(&1, statements)})
        else
          Enum.map(items, &{&1, :waiting})
        end

      [] ->
        Enum.map(items, &{&1, :waiting})
    end
  end

  defp item_written(item, statements) do
    unwritten =
      for ref <- item.package_refs,
          rows = Map.get(statements, ref, []),
          not Enum.any?(rows, &is_integer(&1.fact_id)),
          do: Enum.find_value(rows, "not written", & &1.detail["skipped"])

    case unwritten do
      [] -> :applied
      [reason | _] -> {:held, "the import did not write it: #{reason}"}
    end
  end

  defp base_ref(ref), do: ref |> String.split("+") |> hd()

  @doc "The items waiting on package `package_id`."
  @spec waiting_on(integer()) :: [Item.t()]
  def waiting_on(package_id) do
    Repo.all(
      from(i in Item,
        where: i.package_id == ^package_id and i.status in [:submitted, :in_review],
        order_by: i.id
      )
    )
  end

  @doc false
  @spec decode_spec(Item.t()) :: map()
  def decode_spec(%Item{} = item),
    do: Spec.decode(item.kind, {item.subject_type, item.subject_id}, item.key, item.stored_spec)
end
