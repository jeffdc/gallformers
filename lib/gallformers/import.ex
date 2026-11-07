defmodule Gallformers.Import do
  @moduledoc """
  Import: taking a package (the contract in `priv/import/`) into Gallformers
  (`9449` §5; decisions in `e381`, `d585`).

  A package is one Source's `document.json`, `taxonomy.json`, `gall.json`
  and `review.json`, delivered to the private bucket under
  `import/<key>/`. The steps:

    1. **Register** (`register_package/3`): records the package as
       `:received`. `submit_package/3` delivers a producer's files to the
       bucket, registers them and takes the package through steps 2 and 3
       (`mix gallformers.import.submit` from a package directory).
    2. **Validate** (`validate_package/3`): the contract's phase 4 checks
       and the readiness gate (`Gallformers.Import.Validator`, the same
       checks as `priv/import/validate.py`). A package with errors is
       `:invalid` and keeps its problems; a valid one is `:validated`, with
       one `Gallformers.Import.Batch` per batch file (the producer's
       `batch_id` is unique: a batch is delivered once) and the batches'
       `unmapped` entries.
    3. **Resolve** (`resolve_package/2`, through
       `Gallformers.Import.Resolver` and `Gallformers.Import.GallMatcher`):
       every taxon and Gall of a batch resolves, is new, or goes to the
       admin queue (`Gallformers.Import.Queue`; decided items are kept and
       honoured). A name both batches declare is queued and decided once.
       Unresolved Host names hold the gall batch (`d585`). The
       package's Source is matched (`Gallformers.Import.SourceStep`) and
       phase 6 disputes from `review.json` are queued
       (`Gallformers.Import.Disputes`). What the producer
       set aside as hedged or not a Fact (`unmapped`) is queued one item per
       term, never holding approval (`Gallformers.Import.SetAside`). The
       Source's Trait terms are placed (`Gallformers.Import.TraitTerms`):
       a term the import can't place on its own is a question, one per term,
       never holding approval.
    4. **Decide** (`decide_queue_item/3`): an admin answers each open item,
       recorded with who and when; or accepts the proposals of many at once
       (`accept_proposals/2`, `Gallformers.Import.Proposals`), having
       rejected those they disagree with (`reject_proposal/2`). Host
       decisions may add a synonym or a plant from WCVP
       (`Gallformers.Import.HostDecisions`); `candidate_comparison/1` sets a
       name's candidates side by side. The same queue holds rename
       proposals, which come from taxonomy changes rather than packages
       (`Gallformers.Import.GallRenames`, `list_gall_renames/1`). A Trait
       term's question is settled by placing it for every Source, a
       category for its Galls only, fitting no category, or keeping it as
       text (`Gallformers.Import.TraitTerms`).
    5. **Approve** (`approve_package/2`): with nothing open that a batch
       needs, the package is approved and the import worker
       (`Gallformers.Import.Worker`) applies it.
    6. **Apply** (`apply_package/2`): the taxonomy batch first
       (`Gallformers.Import.ApplyTaxonomy`, the phase 1 rule), then the
       package is resolved again and the gall batch applied
       (`Gallformers.Import.ApplyGall`), each in one transaction, diffing
       the Source's attributions (`Gallformers.Import.Diff`). Re-applying an
       applied batch is a no-op. A batch that a fresh resolution holds
       (new open items) sends the package back to `:awaiting_review`.

  Until a package is approved nothing here changes Facts, taxa or Galls.
  The Facts preview (`preview_package/2`, `Gallformers.Import.Preview`)
  shows what approving would write, given the answers so far, by running
  the apply in a transaction that is rolled back; before approval a
  curator may edit a Fact (drop it, change its Host or its Trait values,
  note it: `edit_fact/5`, `Gallformers.Import.FactEdits`), which applying
  honours. `facts_for_source/1` shows a Source's applied Facts the same way.
  Instead of approving, an admin can deny a package or one of its batches
  (`deny_package/3`, `deny_batch/3`) until it is applied.

  The review screens list packages and the open queue items of every
  package (`list_packages/1`, `list_open_queue_items/1`). Gallformers' own
  statements written in a form — a curator's range exclusion, say — arrive
  as a package of their own (`submit_gallformers_fragment/2`) and go
  through the same steps, approved at once when nothing needs a decision.

  ## The replay log

  Every data-changing step appends to `replay_log` by stable keys
  (`Gallformers.Import.StableRef`): batches applied, queue decisions,
  denials, edits on Facts before approval, and the Host-name step's and
  taxonomy admin's edits
  (`record_synonym_added/4`, `record_plant_added/2`,
  `record_taxonomy_edit/2`, `record_wcvp_edit/2`), curators' notes on
  Facts and plant edits (`record_fact_note/5`, `record_taxon_note/5`),
  corrections to a Source's applied Facts (`correct_source_fact/6`), and
  deletes and merges of Galls, taxa and plants (`record_deletion/2`,
  `record_merge/2`).
  `Gallformers.Import.Replay` replays it after the cutover data migration:
  `export_replay_log/0` writes preview's log to the private bucket and
  `replay_exported/2` replays that file on production
  (`Gallformers.Import.ReplayExport`; `Gallformers.Release` runs both).

  ## The contract's vocabularies

  `Gallformers.Import.Vocab` writes the contract's `priv/import/vocab/`
  files from the database and code (`mix gallformers.import.vocab`).

  ## Writes

  Every write is audited (`Gallformers.Audit`) as the given actor.
  `batch_statements` and `batch_unmapped` are derived from a batch and not
  audited themselves, but are written inside audited transactions.
  """
  use Boundary,
    deps: [
      # Curators' names on their decisions (`Gallformers.Import.FactsView`).
      Gallformers.Accounts,
      Gallformers.Audit,
      Gallformers.Catalog,
      Gallformers.Facts,
      # Deletes and merges delete and move images (`Gallformers.Import.Deletion`).
      Gallformers.Images,
      Gallformers.Licenses,
      Gallformers.Places,
      Gallformers.Ranges,
      Gallformers.Repo,
      Gallformers.Sources,
      Gallformers.Storage,
      Gallformers.Taxa,
      # Host-name suggestions call the configured WCVP lookup at runtime.
      Gallformers.Wcvp
    ],
    exports: [
      Batch,
      BatchStatement,
      BatchUnmapped,
      Events,
      GallComparison,
      GallformersFragment,
      Package,
      Passages,
      QueueItem,
      QueueItemNote,
      ReviewContext,
      Replay,
      ReplayEntry,
      SourceCorrection,
      StatementEdit,
      TermCandidate,
      UnusedNames,
      Validator,
      Validator.Problem,
      Vocab,
      Worker
    ]

  import Ecto.Query

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Import.ApplyGall
  alias Gallformers.Import.ApplyTaxonomy
  alias Gallformers.Import.Batch
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.BatchUnmapped
  alias Gallformers.Import.CurationNotes
  alias Gallformers.Import.Deletion
  alias Gallformers.Import.Disputes
  alias Gallformers.Import.FactEdits
  alias Gallformers.Import.FactsView
  alias Gallformers.Import.GallDecisions
  alias Gallformers.Import.GallMatcher
  alias Gallformers.Import.GallRenames
  alias Gallformers.Import.HostDecisions
  alias Gallformers.Import.Merge
  alias Gallformers.Import.Package
  alias Gallformers.Import.Preview
  alias Gallformers.Import.Proposals
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.QueueItemNote
  alias Gallformers.Import.Replay
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Import.ReplayExport
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.Resolver
  alias Gallformers.Import.SetAside
  alias Gallformers.Import.SourceCorrection
  alias Gallformers.Import.SourceCorrections
  alias Gallformers.Import.SourceEdits
  alias Gallformers.Import.SourceStep
  alias Gallformers.Import.SplitQuestions
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.StatementEdit
  alias Gallformers.Import.SynonymDecisions
  alias Gallformers.Import.TaxonomicDecisions
  alias Gallformers.Import.TaxonomyAdmin
  alias Gallformers.Import.TaxonomyCarryOver
  alias Gallformers.Import.TaxonomyEdits
  alias Gallformers.Import.TaxonomyQueue
  alias Gallformers.Import.TaxonomyStatements
  alias Gallformers.Import.TermCandidate
  alias Gallformers.Import.TermCandidates
  alias Gallformers.Import.TraitTerms
  alias Gallformers.Import.Undo
  alias Gallformers.Import.Validator
  alias Gallformers.Import.Validator.Problem
  alias Gallformers.Import.VocabEdits
  alias Gallformers.Import.Worker
  alias Gallformers.Repo
  alias Gallformers.Sources.Docling
  alias Gallformers.Storage.Private
  alias Gallformers.Taxa

  @package_files ["document.json", "taxonomy.json", "gall.json", "review.json"]
  @validatable [:received, :invalid, :validated]
  @resolvable [:validated, :resolving, :awaiting_review]
  @deniable [:received, :invalid, :validated, :resolving, :awaiting_review]
  @statement_fields [
    :kind,
    :ref,
    :resolution,
    :method,
    :taxon_id,
    :gall_id,
    :candidate_ids,
    :flags,
    :detail
  ]

  # -- packages ----------------------------------------------------------------

  @doc """
  Registers the package delivered under `import/<key>/` as `:received`.
  `attrs` may give `:submitter_user_id`; the submitter's name is the
  actor's. A key is registered once.
  """
  @spec register_package(Actor.t(), String.t(), map()) ::
          {:ok, Package.t()} | {:error, Changeset.t()}
  def register_package(%Actor{} = actor, key, attrs \\ %{}) when is_binary(key) do
    Audit.transaction(actor, "import.register_package", fn ->
      %Package{}
      |> Package.register_changeset(
        attrs
        |> Map.take([:submitter_user_id])
        |> Map.merge(%{key: key, submitter_name: actor.name})
      )
      |> Repo.insert()
      |> unwrap_or_rollback()
    end)
  end

  @doc """
  Delivers a producer's package (`e381` *Delivery*): writes `files` (file
  name to bytes: `document.json`, `taxonomy.json`, `gall.json`,
  `review.json`) to the private bucket under `import/<key>/`, registers the
  package as `actor` and takes it on (`advance_package/2`): validated and,
  if valid, resolved, so it waits for review (`:awaiting_review`) or is
  `:invalid` with its problems.

  `{:error, {:unknown_files, names}}` for files that are not a package's,
  and `{:error, :key_taken}` for a key already delivered; neither writes
  anything.
  """
  @spec submit_package(Actor.t(), String.t(), Validator.package()) ::
          {:ok, Package.t()} | {:error, term()}
  def submit_package(%Actor{} = actor, key, files) when is_binary(key) and is_map(files) do
    attrs = if actor.type == :user, do: %{submitter_user_id: actor.id}, else: %{}

    with :ok <- package_files_only(files),
         :ok <- key_free(key),
         :ok <- put_files(key, files),
         {:ok, package} <- register_package(actor, key, attrs) do
      advance_package(actor, package.id)
    end
  end

  defp package_files_only(files) do
    case Map.keys(files) -- @package_files do
      [] -> :ok
      unknown -> {:error, {:unknown_files, Enum.sort(unknown)}}
    end
  end

  defp key_free(key), do: if(get_package_by_key(key), do: {:error, :key_taken}, else: :ok)

  defp put_files(key, files) do
    Enum.reduce_while(files, :ok, fn {name, bytes}, :ok ->
      case Private.put(Package.prefix(key) <> name, bytes, content_type: "application/json") do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {name, reason}}}
      end
    end)
  end

  @doc "Gets a package by ID, raising if there is none."
  @spec get_package!(integer()) :: Package.t()
  def get_package!(id), do: Repo.get!(Package, id)

  @doc "Gets a package by key, or nil."
  @spec get_package_by_key(String.t()) :: Package.t() | nil
  def get_package_by_key(key), do: Repo.get_by(Package, key: key)

  @typedoc "A page of results: the entries asked for and how many there are in all."
  @type page(entry) :: %{entries: [entry], total: non_neg_integer()}

  @doc """
  Packages, newest first, as a page. Options: `:status` (a status or a
  list of them; every package when absent), `:limit` (nil for all),
  `:offset`.
  """
  @spec list_packages(keyword()) :: page(Package.t())
  def list_packages(opts \\ []) do
    query =
      case opts[:status] do
        nil -> Package
        statuses when is_list(statuses) -> from(p in Package, where: p.status in ^statuses)
        status -> from(p in Package, where: p.status == ^status)
      end

    page(query, [desc: :id], [], opts)
  end

  defp page(query, order, preloads, opts) do
    entries =
      query
      |> order_by(^order)
      |> offset(^(opts[:offset] || 0))
      |> then(&if(opts[:limit], do: limit(&1, ^opts[:limit]), else: &1))
      |> preload(^preloads)
      |> Repo.all()

    %{entries: entries, total: Repo.aggregate(query, :count)}
  end

  @doc """
  The package's files from the private bucket, as a map of file name to
  bytes (`document.json`, `taxonomy.json`, `gall.json`, `review.json`);
  files not delivered are absent.
  """
  @spec read_package_files(Package.t()) :: {:ok, Validator.package()} | {:error, term()}
  def read_package_files(%Package{s3_prefix: prefix}) do
    Enum.reduce_while(@package_files, {:ok, %{}}, fn name, {:ok, files} ->
      case Private.get(prefix <> name) do
        {:ok, bytes} -> {:cont, {:ok, Map.put(files, name, bytes)}}
        {:error, :not_found} -> {:cont, {:ok, files}}
        {:error, reason} -> {:halt, {:error, {name, reason}}}
      end
    end)
  end

  @doc """
  Validates a registered package (`Gallformers.Import.Validator`): phase 4
  and, unless `review: false`, the readiness gate (Gallformers' own
  statement batches carry no review).

  A producer `batch_id` already delivered in another package is an error
  too. With no errors the package becomes `:validated` and its batches
  (and their `unmapped` entries) are recorded, replacing any recorded by an
  earlier validation; otherwise it becomes `:invalid` with no batches. The
  problems, warnings included, are kept on the package either way.

  Only a `:received`, `:invalid` or `:validated` package can be validated
  (`{:error, :not_validatable}` otherwise). `{:error, {file, reason}}` when
  the bucket cannot be read.
  """
  @spec validate_package(Actor.t(), Package.t(), keyword()) ::
          {:ok, Package.t()} | {:error, :not_validatable | {String.t(), term()} | Changeset.t()}
  def validate_package(%Actor{} = actor, %Package{} = package, opts \\ []) do
    with :ok <- validatable(package),
         {:ok, files} <- read_package_files(package) do
      problems = Validator.validate(files, review: Keyword.get(opts, :review, true))
      batches = decoded_batches(files)
      problems = problems ++ redelivered(batches, package)

      Audit.transaction(actor, "import.validate_package", fn ->
        package = lock_package(package.id)
        if package.status not in @validatable, do: Repo.rollback(:not_validatable)

        delete_batches(package)
        valid? = not Validator.errors?(problems)
        if valid?, do: Enum.each(batches, &insert_batch(package, &1))

        package
        |> Package.validated_changeset(%{
          status: if(valid?, do: :validated, else: :invalid),
          problems: Enum.map(problems, &problem_map/1),
          format_version: version(batches, "format_version"),
          vocabulary_version: version(batches, "vocabulary_version"),
          validated_at: DateTime.utc_now(:second)
        })
        |> Repo.update()
        |> unwrap_or_rollback()
      end)
    end
  end

  defp validatable(%Package{status: status}) when status in @validatable, do: :ok
  defp validatable(_package), do: {:error, :not_validatable}

  defp lock_package(id),
    do: Repo.one!(from(p in Package, where: p.id == ^id, lock: "FOR UPDATE"))

  defp decoded_batches(files) do
    for name <- Validator.batch_files(),
        bytes = files[name],
        is_binary(bytes),
        {:ok, %{} = content} <- [Jason.decode(bytes)],
        do: %{file: name, bytes: bytes, content: content}
  end

  # A batch_id another package already delivered: each batch is imported once.
  defp redelivered(batches, %Package{id: package_id}) do
    for %{file: file, content: %{"batch_id" => batch_id}} <- batches,
        is_binary(batch_id),
        key =
          Repo.one(
            from(b in Batch,
              join: p in assoc(b, :package),
              where: b.producer_batch_id == ^batch_id and b.package_id != ^package_id,
              select: p.key
            )
          ),
        do: %Problem{
          level: :error,
          file: file,
          message: "batch_id #{batch_id} was already delivered in package #{key}"
        }
  end

  defp delete_batches(%Package{id: package_id}) do
    Repo.delete_all(from(b in Batch, where: b.package_id == ^package_id))
  end

  defp insert_batch(package, %{file: file, bytes: bytes, content: content}) do
    batch =
      %Batch{}
      |> Batch.create_changeset(%{
        package_id: package.id,
        file: file,
        batch_type: content["batch_type"],
        mode: content["mode"],
        producer_batch_id: content["batch_id"],
        sha256: Validator.sha256(bytes),
        content: content
      })
      |> Repo.insert()
      |> unwrap_or_rollback()

    Repo.insert_all(BatchUnmapped, BatchUnmapped.rows(batch.id, content))
    batch
  end

  defp version(batches, field), do: Enum.find_value(batches, & &1.content[field])

  defp problem_map(%Problem{} = p),
    do: %{"level" => Atom.to_string(p.level), "file" => p.file, "message" => p.message}

  # -- batches -----------------------------------------------------------------

  @doc "A package's batches, the taxonomy batch first."
  @spec list_batches(Package.t()) :: [Batch.t()]
  def list_batches(%Package{id: package_id}) do
    from(b in Batch,
      where: b.package_id == ^package_id,
      order_by: fragment("CASE ? WHEN 'taxonomy' THEN 0 ELSE 1 END", b.batch_type)
    )
    |> Repo.all()
  end

  @doc "Gets a batch by ID, raising if there is none."
  @spec get_batch!(integer()) :: Batch.t()
  def get_batch!(id), do: Repo.get!(Batch, id)

  # -- resolution --------------------------------------------------------------

  @doc """
  Resolves a validated package's batches that are not applied or denied,
  taxonomy batch first (`Gallformers.Import.Resolver`,
  `Gallformers.Import.GallMatcher`): each batch's taxon and Gall statements
  are stored (`Gallformers.Import.BatchStatement`, replacing the last
  resolution's), and what needs an admin is queued
  (`Gallformers.Import.QueueItem`; open items of an earlier resolution are
  replaced, decided ones kept).

  A gall batch with a Host name that is not resolved is `:blocked` until an
  admin resolves the name (adds a synonym or the plant) and the package is
  resolved again (`d585`); otherwise a batch is `:ready`. The package
  becomes `:awaiting_review`.

  Resolving changes no Facts, taxa or Galls. Only a `:validated`,
  `:resolving` or `:awaiting_review` package can be resolved
  (`{:error, :not_resolvable}` otherwise).
  """
  @spec resolve_package(Actor.t(), Package.t()) ::
          {:ok, Package.t()} | {:error, :not_resolvable | {String.t(), term()} | Changeset.t()}
  def resolve_package(%Actor{} = actor, %Package{} = package) do
    with :ok <- resolvable(package),
         {:ok, files} <- read_package_files(package) do
      Audit.transaction(actor, "import.resolve_package", fn ->
        package = lock_package(package.id)
        if package.status not in @resolvable, do: Repo.rollback(:not_resolvable)

        package
        |> resolve(files)
        |> Package.status_changeset(:awaiting_review)
        |> Repo.update()
        |> unwrap_or_rollback()
      end)
    end
  end

  defp resolvable(%Package{status: status}) when status in @resolvable, do: :ok
  defp resolvable(_package), do: {:error, :not_resolvable}

  # Resolves the package's batches that are not applied or denied, and its
  # Source, inside the caller's transaction. Returns the package.
  defp resolve(package, files) do
    all = list_batches(package)
    batches = Enum.reject(all, &(&1.status in [:applied, :denied]))
    # A denied taxonomy batch names no taxa for the gall batch.
    taxonomy =
      Enum.find_value(all, &(&1.batch_type == :taxonomy && &1.status != :denied && &1.content))

    texts = document_texts(files["document.json"])
    review = decode(files["review.json"])

    %{source_id: source_id, queue: source_items} =
      all |> Enum.map(& &1.content) |> SourceStep.source_block() |> SourceStep.resolve()

    store_package_items(package, source_items)

    # A denied batch decides nothing for the others.
    decided =
      for batch <- all,
          batch.status != :denied,
          into: %{},
          do: {batch.id, Queue.decided(batch.id)}

    names =
      name_decisions(
        all,
        Map.new(decided, fn {id, items} -> {id, Queue.statement_decisions(items)} end)
      )

    # A Host read in the Source's sense holds for every batch of the package.
    readings = decided |> Map.values() |> List.flatten() |> GallDecisions.readings()

    common = %{
      taxonomy: taxonomy,
      texts: texts,
      review: review,
      names: names,
      readings: readings
    }

    resolutions =
      for batch <- batches, do: resolve_batch(batch, Map.put(common, :decided, decided[batch.id]))

    queues =
      resolutions
      |> Enum.map(fn %{batch: batch} = r ->
        %{file: batch.file, batch_type: batch.batch_type, name_keys: r.name_keys, queue: r.queue}
      end)
      |> Queue.share_names()

    for {resolution, queue} <- Enum.zip(resolutions, queues) do
      store_resolution(package, %{resolution | queue: queue})
    end

    if source_id && package.source_id == nil do
      package |> Changeset.change(source_id: source_id) |> Repo.update() |> unwrap_or_rollback()
    else
      package
    end
  end

  defp decode(nil), do: nil

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{} = map} -> map
      _ -> nil
    end
  end

  # The package-level items (its Source, the Source a notice retracts):
  # open ones replaced, decided ones kept.
  defp store_package_items(package, items) do
    decided =
      from(q in QueueItem,
        where: q.package_id == ^package.id and is_nil(q.batch_id) and q.status == :decided,
        select: q.statement_ref
      )
      |> Repo.all()

    replace_open_items(package, nil, Enum.reject(items, &(&1.statement_ref in decided)))
  end

  # The decisions on names, by name key (`Queue.name_keys/1`): what was
  # decided for a name in one batch holds for it in every batch of the
  # package; the first batch's (the taxonomy batch's) wins.
  defp name_decisions(batches, decisions) do
    for batch <- batches,
        by_ref = Map.get(decisions, batch.id, %{}),
        {ref, key} <- Queue.name_keys(batch.content),
        Map.has_key?(by_ref, ref),
        reduce: %{},
        do: (acc -> Map.put_new(acc, key, by_ref[ref]))
  end

  defp document_texts(nil), do: []

  defp document_texts(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{} = doc} -> doc |> Docling.items() |> Enum.map(&Docling.item_text/1)
      _ -> []
    end
  end

  # Resolves one batch, honouring the decided queue items: its own, and the
  # package's decisions on the names it declares (`ctx.names`). The taxa
  # are decided before the Galls are matched, so a Gall waiting on its
  # Inducer is matched against the decided Inducer. Returns the
  # statements, the queue items they call for (less those decided, and
  # less unresolved names no act or Fact needs), and its status.
  defp resolve_batch(%Batch{content: content} = batch, ctx) do
    name_keys = Queue.name_keys(content)

    decisions =
      for(
        {ref, key} <- name_keys,
        Map.has_key?(ctx.names, key),
        into: %{},
        do: {ref, ctx.names[key]}
      )
      |> Map.merge(Queue.statement_decisions(ctx.decided))

    context = Resolver.context(content, taxonomy: ctx.taxonomy, document_texts: ctx.texts)

    taxa =
      content
      |> Resolver.resolve_taxa(context)
      |> GallDecisions.read(ctx.readings)
      |> Queue.overlay(decisions)

    {statements, queue, status} =
      case batch.batch_type do
        :taxonomy ->
          {taxa, Resolver.queue_items(taxa), :ready}

        :gall ->
          galls =
            content
            |> GallMatcher.match_galls(taxa)
            |> Queue.overlay(decisions)
            |> GallMatcher.settle_pairs()

          {taxa ++ galls, Resolver.queue_items(taxa) ++ GallMatcher.queue_items(galls),
           if(Queue.holds_gall_batch?(taxa), do: :blocked, else: :ready)}
      end

    needed = needed_taxon_refs(batch.batch_type, content, taxa)

    queue =
      Enum.filter(queue, fn item ->
        not Map.has_key?(decisions, item.statement_ref) and
          (not String.starts_with?(item.statement_ref, "t") or item.statement_ref in needed)
      end) ++ statement_items(batch, ctx)

    %{batch: batch, statements: statements, queue: queue, status: status, name_keys: name_keys}
  end

  # The items about the batch's statements rather than its names and Galls,
  # less those decided: disputes, what was set aside, Trait terms.
  defp statement_items(%Batch{content: content, file: file}, ctx) do
    decided_disputes = for(%{kind: :dispute} = q <- ctx.decided, ref <- Disputes.refs(q), do: ref)
    decided_set_aside = for(q <- ctx.decided, SetAside.set_aside?(q), do: q.statement_ref)
    decided_terms = for(%{kind: :trait_term} = q <- ctx.decided, do: q.statement_ref)

    dropped = Map.keys(Queue.drops(ctx.decided))
    terms = TraitTerms.queue_items(content, ctx.review, file: file, drop: dropped)

    # A statement a Gall decision left out is disputed no longer.
    Enum.reject(
      Disputes.items(ctx.review, file, content),
      &(&1.statement_ref in decided_disputes or &1.statement_ref in dropped)
    ) ++
      Enum.reject(SetAside.queue_items(content), &(&1.statement_ref in decided_set_aside)) ++
      Enum.reject(terms, &(&1.statement_ref in decided_terms))
  end

  # The taxon refs a batch's acts or Galls and Facts need resolved. A
  # synonymy act's `name` is a name, not a taxon: it need not resolve. Nor
  # does the parent of an original combination's placement, which is
  # recorded as history (`Gallformers.Import.ApplyTaxonomy`).
  defp needed_taxon_refs(:taxonomy, content, taxa) do
    original = for %{flags: flags} = s <- taxa, "original_combination" in flags, do: s.ref

    for act <- List.wrap(content["acts"]),
        role <- ["taxon", "parent", "accepted", "into"],
        not (role == "parent" and act["kind"] == "placement" and act["taxon"] in original),
        ref <- List.wrap(act[role]),
        uniq: true,
        do: ref
  end

  defp needed_taxon_refs(:gall, content, _taxa) do
    from_galls =
      for g <- List.wrap(content["galls"]),
          role <- ["inducer", "host"],
          ref = get_in(g, ["identified_by", role]),
          is_binary(ref),
          do: ref

    from_facts =
      for f <- List.wrap(content["facts"]),
          role <- ["subject", "object"],
          ref = f[role],
          is_binary(ref) and String.starts_with?(ref, "t"),
          do: ref

    Enum.uniq(from_galls ++ from_facts)
  end

  defp store_resolution(package, %{batch: batch} = resolution) do
    Repo.delete_all(from(s in BatchStatement, where: s.batch_id == ^batch.id))

    rows =
      for s <- resolution.statements do
        s |> Map.take(@statement_fields) |> Map.put(:batch_id, batch.id)
      end

    Repo.insert_all(BatchStatement, rows)
    replace_open_items(package, batch.id, resolution.queue)

    batch
    |> Batch.status_changeset(resolution.status)
    |> Repo.update()
    |> unwrap_or_rollback()
  end

  # Replaces the open items of `batch_id` (nil: the package's own) with
  # `items`. An open item still called for (the same kind and statement)
  # keeps its row and ID, its subject, proposal and reason brought up to
  # date, so a resolution after a decision leaves the others in place. A
  # rejection lasts while the proposal it rejected does. An item no longer
  # called for is deleted; its notes pass to the item now queued about the
  # same statement, if any, else go with it.
  defp replace_open_items(package, batch_id, items) do
    open =
      from(q in QueueItem, where: q.package_id == ^package.id and q.status == :open)
      |> then(fn query ->
        if batch_id,
          do: where(query, [q], q.batch_id == ^batch_id),
          else: where(query, [q], is_nil(q.batch_id))
      end)
      |> Repo.all()
      |> Map.new(&{{&1.kind, &1.statement_ref}, &1})

    items = Enum.uniq_by(items, &{&1.kind, &1.statement_ref})
    wanted = MapSet.new(items, &{&1.kind, &1.statement_ref})
    stale = for {key, q} <- open, not MapSet.member?(wanted, key), do: q

    {kept, new} = Enum.split_with(items, &Map.has_key?(open, {&1.kind, &1.statement_ref}))

    for item <- kept,
        q = open[{item.kind, item.statement_ref}],
        {q.subject, q.proposal, q.reason} != {item.subject, item.proposal, item.reason} do
      rejection =
        if q.proposal != item.proposal,
          do: [proposal_rejected_at: nil, proposal_rejected_by_name: nil],
          else: []

      from(i in QueueItem, where: i.id == ^q.id)
      |> Repo.update_all(
        set:
          [
            subject: item.subject,
            proposal: item.proposal,
            reason: item.reason,
            updated_at: DateTime.utc_now(:second)
          ] ++ rejection
      )
    end

    insert_queue_items(new, package, batch_id)
    # A stale item's notes pass to its replacement before it is deleted.
    pass_on_notes(package, batch_id, stale)
    Repo.delete_all(from(q in QueueItem, where: q.id in ^Enum.map(stale, & &1.id)))
  end

  defp insert_queue_items(items, package, batch_id) do
    now = DateTime.utc_now(:second)

    rows =
      for item <- items do
        Map.merge(item, %{
          package_id: package.id,
          batch_id: batch_id,
          status: :open,
          inserted_at: now,
          updated_at: now
        })
      end

    Repo.insert_all(QueueItem, rows, on_conflict: :nothing)
  end

  @doc """
  Resolves plant names that come from outside a package (an iNaturalist
  observation's Host) as a gall batch's Hosts are resolved
  (`Gallformers.Import.Resolver`): accepted names and synonyms of plants,
  abbreviations expanded with the genera the names and `:document_texts`
  write in full, and for a name that matches nothing, Host suggestions from
  the tree and WCVP. One statement per name, in order (`ref` `"h1"`,
  `"h2"`, …). Options: `:document_texts`, `:wcvp` (the WCVP lookup).
  """
  @spec resolve_host_names([String.t()], keyword()) :: [Resolver.statement()]
  def resolve_host_names(names, opts \\ []) when is_list(names) do
    taxa =
      for {name, i} <- Enum.with_index(names, 1),
          do: %{"ref" => "h#{i}", "name_as_written" => name}

    batch = %{
      "batch_type" => "gall",
      "taxa" => taxa,
      "facts" =>
        for(
          t <- taxa,
          do: %{"kind" => "relationship", "type" => "host_of", "subject" => t["ref"]}
        )
    }

    Resolver.resolve_taxa(
      batch,
      Resolver.context(batch, Keyword.take(opts, [:document_texts, :wcvp]))
    )
  end

  @doc "A batch's statements with their resolutions: taxa, then Galls, each in batch order."
  @spec list_statements(Batch.t()) :: [BatchStatement.t()]
  def list_statements(%Batch{id: batch_id}) do
    Repo.all(from(s in BatchStatement, where: s.batch_id == ^batch_id, order_by: s.id))
  end

  @doc """
  The taxon and Gall statements of `batch_ids` with these refs, in one
  query, by `{batch_id, ref}`: what the queue items of several packages
  speak of (`pairs` is `[{batch_id, ref}]`).
  """
  @spec statements_for([{integer(), String.t()}]) :: %{
          {integer(), String.t()} => BatchStatement.t()
        }
  def statements_for([]), do: %{}

  def statements_for(pairs) do
    batch_ids = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    wanted = MapSet.new(pairs)

    from(s in BatchStatement, where: s.batch_id in ^batch_ids and s.kind in [:taxon, :gall])
    |> Repo.all()
    |> Enum.filter(&MapSet.member?(wanted, {&1.batch_id, &1.ref}))
    |> Map.new(&{{&1.batch_id, &1.ref}, &1})
  end

  @doc """
  A package's queue items, oldest first. Options: `:kind` and `:status`
  (default `:open`; `:all` for every item).
  """
  @spec list_queue_items(Package.t(), keyword()) :: [QueueItem.t()]
  def list_queue_items(%Package{id: package_id}, opts \\ []) do
    query = from(q in QueueItem, where: q.package_id == ^package_id, order_by: q.id)

    query =
      case Keyword.get(opts, :status, :open) do
        :all -> query
        status -> where(query, [q], q.status == ^status)
      end

    query =
      case opts[:kind] do
        nil -> query
        kind -> where(query, [q], q.kind == ^kind)
      end

    Repo.all(query)
  end

  @doc """
  The open queue items of every package, and the rename proposals (which
  come from no package), oldest first, as a page; each with its `package`
  and `batch` (nil for a rename proposal and for an item about the
  package's Source). Options: `:kind`, `:limit` (nil for all), `:offset`.
  """
  @spec list_open_queue_items(keyword()) :: page(QueueItem.t())
  def list_open_queue_items(opts \\ []) do
    query = from(q in QueueItem, where: q.status == :open)

    query =
      case opts[:kind] do
        nil -> query
        kind -> where(query, [q], q.kind == ^kind)
      end

    page(query, [asc: :id], [:package, :batch], opts)
  end

  @doc "How many queue items are open, by kind (kinds with none are absent)."
  @spec count_open_queue_items() :: %{QueueItem.kind() => pos_integer()}
  def count_open_queue_items do
    from(q in QueueItem, where: q.status == :open, group_by: q.kind, select: {q.kind, count()})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Whether a batch can be applied now: resolved with nothing holding it (a
  gall batch waits for its Host names, `d585`). Applying also waits for the
  package's taxonomy batch (Task 13).
  """
  @spec applicable?(Batch.t()) :: boolean()
  def applicable?(%Batch{status: status}), do: status == :ready

  @typedoc "A Trait Fact written on a placed term the producer suggested another category for."
  @type term_spot_check :: %{
          trait: String.t(),
          term: String.t(),
          category: String.t(),
          suggested: [String.t()],
          fact_id: integer(),
          batch_id: integer(),
          ref: String.t()
        }

  @doc """
  The Trait Facts written on a placed term whose producer suggested
  another category (flagged `"suggested_other_category"` when applied,
  `Gallformers.Import.TraitTerms`), newest first: for spot checks of the
  term's placement.
  """
  @spec list_term_spot_checks() :: [term_spot_check()]
  def list_term_spot_checks do
    from(s in BatchStatement,
      where: s.kind == :fact and "suggested_other_category" in s.flags,
      order_by: [desc: s.id]
    )
    |> Repo.all()
    |> Enum.map(fn s ->
      spot = s.detail["spot_check"] || %{}

      %{
        trait: spot["trait"],
        term: spot["term"],
        category: spot["category"],
        suggested: List.wrap(spot["suggested"]),
        fact_id: s.fact_id,
        batch_id: s.batch_id,
        ref: s.ref
      }
    end)
  end

  @doc "A batch's `unmapped` entries, in the batch's order."
  @spec list_unmapped(Batch.t()) :: [BatchUnmapped.t()]
  def list_unmapped(%Batch{id: batch_id}) do
    Repo.all(from(u in BatchUnmapped, where: u.batch_id == ^batch_id, order_by: u.position))
  end

  @doc "Gets a queue item by ID, raising if there is none."
  @spec get_queue_item!(integer()) :: QueueItem.t()
  def get_queue_item!(id), do: Repo.get!(QueueItem, id)

  @doc """
  The rename proposals (`:gall_rename` queue items, from no package;
  `Gallformers.Import.GallRenames`), oldest first. Options: `:status`
  (default `:open`; `:all` for every one).
  """
  @spec list_gall_renames(keyword()) :: [QueueItem.t()]
  def list_gall_renames(opts \\ []), do: GallRenames.list(opts)

  @doc """
  The questions merges leave (`:same_date_conflict` queue items of no
  package: a merge brought two same-date Sources into disagreement on one
  Fact; `record_merge/2`), oldest first. Options: `:status` (default
  `:open`; `:all` for every one).
  """
  @spec list_merge_conflicts(keyword()) :: [QueueItem.t()]
  def list_merge_conflicts(opts \\ []) do
    query =
      from(q in QueueItem,
        where: q.kind == :same_date_conflict and is_nil(q.package_id),
        order_by: q.id
      )

    case Keyword.get(opts, :status, :open) do
      :all -> Repo.all(query)
      status -> Repo.all(from(q in query, where: q.status == ^status))
    end
  end

  @typedoc "A candidate of a name several taxa hold, for comparison (`candidate_comparison/1`)."
  @type candidate :: %{
          taxon_id: integer(),
          name: String.t(),
          rank: Taxa.Rank.t(),
          authorship: String.t() | nil,
          names: [
            %{
              name: String.t(),
              status: :accepted | :synonym,
              authorship: String.t() | nil,
              sensu: String.t() | nil
            }
          ],
          galls: [
            %{
              gall_id: integer(),
              name: String.t(),
              generation: String.t() | nil,
              hosts: [%{taxon_id: integer(), name: String.t(), rank: Taxa.Rank.t()}]
            }
          ]
        }

  @doc """
  The candidates of a taxon item (`t1`; a name several species hold, as a
  misapplied or invalid name is), in the proposal's order, to compare with
  what the Source says: each one's accepted name and rank, the names it
  holds (accepted first, then its synonyms, with authorship and sensu), and
  the Galls it induces with their current Hosts. Empty for any other item.
  """
  @spec candidate_comparison(QueueItem.t()) :: [candidate()]
  def candidate_comparison(%QueueItem{statement_ref: "t" <> _, proposal: proposal}) do
    for id <- List.wrap(proposal["candidate_ids"]),
        taxon = Taxa.get_taxon(id) do
      accepted = Enum.find(taxon.names, &(&1.status == :accepted))

      %{
        taxon_id: id,
        name: accepted.name,
        rank: taxon.rank,
        authorship: accepted.authorship,
        names: Enum.map(taxon.names, &Map.take(&1, [:name, :status, :authorship, :sensu])),
        galls:
          for s <- Catalog.list_gall_summaries_by_inducer([id]) do
            %{gall_id: s.gall_id, name: s.name, generation: s.generation, hosts: s.hosts}
          end
      }
    end
  end

  def candidate_comparison(_item), do: []

  # -- decisions ---------------------------------------------------------------

  @doc """
  Records an admin's `decision` on an open queue item, with who (`actor`)
  and when (`Gallformers.Import.Queue` lists what each kind takes). The
  decision is honoured at once — a decided taxon or Gall statement follows
  it, and a gall batch held only by a decided Host name is freed — and
  every later resolution keeps it. A decision on a batch's item resolves
  the package again (when it can be resolved): a name's decision then
  holds in every batch that declares it, and the Galls are matched again,
  so a Gall that waited on its Inducer is queued now if it still needs
  someone. Open items still called for keep their IDs. The replay log
  records it.

  A Host decision that adds a synonym or a plant adds it first
  (`Gallformers.Import.HostDecisions`). A Gall decision may leave out
  statements the Source gets wrong and read a Host name in the Source's
  sense, recording that sense on the plant first
  (`Gallformers.Import.GallDecisions`). A synonym question may be decided by
  changing the tree: the name split off as a species of its own, or moved
  to another species (`Gallformers.Import.SynonymDecisions`), the edits
  made first. A dispute dropping a Trait Fact
  keeps its words as text on the Gall (`Gallformers.Import.Disputes`); one
  about a Trait term kept after its batch was applied writes its Facts. A
  decision on what was set aside, made after its gall batch was applied,
  writes its Facts at once (`apply_set_aside_decision/2`). A decision on a
  Trait term (`Gallformers.Import.TraitTerms`) changes the term first;
  then its waiting uses are settled and get their Facts at once where
  their batch is applied (else when it is): this question's, or, placing
  the term for every Source or marking it as fitting none, every
  Source's, the other packages' questions about the term being decided
  with it.

  `{:error, :already_decided}` for a decided item; `{:error, :gone}` for
  one a later resolution removed (its statement no longer needs anyone);
  `{:error, changeset}` (errors on `:decision`) for a decision that does
  not fit the item.
  """
  @spec decide_queue_item(Actor.t(), QueueItem.t(), map()) ::
          {:ok, QueueItem.t()} | {:error, :already_decided | :gone | Changeset.t() | term()}
  def decide_queue_item(
        %Actor{} = actor,
        %QueueItem{kind: :taxonomy_acceptance} = item,
        decision
      ),
      do: decide_taxonomy_question(actor, item, decision)

  def decide_queue_item(%Actor{} = actor, %QueueItem{} = item, decision) do
    files = decision_files(item.package_id, [item])

    Audit.transaction(actor, "import.decide_queue_item", fn ->
      # The package first, as resolving locks it before its items.
      package = item.package_id && lock_package(item.package_id)
      item = Repo.one(from(q in QueueItem, where: q.id == ^item.id, lock: "FOR UPDATE"))
      if item == nil, do: Repo.rollback(:gone)
      if item.status == :decided, do: Repo.rollback(:already_decided)

      item = actor |> decide(item, package, decision, files) |> unwrap_or_rollback()
      settle(package, [item], files)
      item
    end)
  end

  @doc """
  Accepts the proposals of `items` (`Gallformers.Import.Proposals`: what
  accepting decides, per kind), in one transaction: each is decided as
  `decide_queue_item/3` decides it, and logged for replay the same way;
  each package is then resolved again once.

  Skipped, and left open: an item whose proposal was rejected
  (`:rejected`), one with only a suggestion to check (`:weak`), one with no
  proposal (`:no_proposal`), one decided (`:already_decided`) or removed
  (`:gone`) since it was listed, and one whose proposal no longer fits it
  (`{:invalid, changeset}`). Returns what was decided and what was
  skipped, with why, in the order given.
  """
  @spec accept_proposals(Actor.t(), [QueueItem.t()]) ::
          {:ok, %{decided: [QueueItem.t()], skipped: [{QueueItem.t(), term()}]}}
          | {:error, term()}
  def accept_proposals(%Actor{} = actor, items) when is_list(items) do
    items = Enum.uniq_by(items, & &1.id)
    by_package = Enum.group_by(items, & &1.package_id)
    files = Map.new(by_package, fn {id, listed} -> {id, decision_files(id, listed)} end)
    ids = Enum.map(items, & &1.id)

    Audit.transaction(actor, "import.accept_proposals", fn ->
      packages =
        for id <- by_package |> Map.keys() |> Enum.reject(&is_nil/1) |> Enum.sort(),
            into: %{},
            do: {id, lock_package(id)}

      current =
        from(q in QueueItem, where: q.id in ^ids, order_by: q.id, lock: "FOR UPDATE")
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      {decided, skipped} =
        Enum.reduce(items, {[], []}, fn listed, acc ->
          item = current[listed.id]
          collect(acc, accept(actor, item, packages, files), item || listed)
        end)

      for {id, package} <- packages,
          do: settle(package, Enum.filter(decided, &(&1.package_id == id)), files[id])

      %{decided: Enum.reverse(decided), skipped: Enum.reverse(skipped)}
    end)
  end

  @doc """
  The decision accepting `item`'s proposal makes, or why it has none to
  accept (`:rejected`, `:weak`, `:no_proposal`;
  `Gallformers.Import.Proposals`).
  """
  @spec proposed_decision(QueueItem.t()) :: {:ok, map()} | {:none, Proposals.reason()}
  defdelegate proposed_decision(item), to: Proposals, as: :proposed

  @doc """
  Decides a group of identical disputes (`Gallformers.Import.Disputes`:
  the same statement, `subject["group"]`) as one question, in one
  transaction: `%{"keep" => true}` or `%{"skip" => true}` for every item,
  but those whose IDs are in `"except"`, which get the other. A group of
  Host disputes may be kept with the Host read as another plant (`%{"keep"
  => true, "host_reading" => reading}`), or on the plant chosen for their
  statements (`%{"keep" => true, "host_taxon_id" => id}`): each kept is
  decided so, each excepted `skip`. Each item is
  decided as `decide_queue_item/3` decides it, and logged for replay the
  same way; the package is then resolved again once. Returns the decided
  items.

  `{:error, :not_one_group}` unless `items` are disputes of one package
  sharing a group, every exception among them; `{:error, :invalid_decision}`
  for another decision; `{:error, :already_decided}` or `{:error, :gone}`
  when one of them is decided or removed since it was listed.
  """
  @spec decide_group(Actor.t(), [QueueItem.t()], map()) ::
          {:ok, [QueueItem.t()]}
          | {:error, :not_one_group | :invalid_decision | :already_decided | :gone | term()}
  def decide_group(%Actor{} = actor, items, decision) when is_list(items) and is_map(decision) do
    items = Enum.uniq_by(items, & &1.id)

    with {:ok, chosen, except} <- group_decision(decision),
         :ok <- one_group(items, except) do
      package_id = hd(items).package_id
      files = decision_files(package_id, items)
      ids = Enum.map(items, & &1.id)

      Audit.transaction(actor, "import.decide_group", fn ->
        package = package_id && lock_package(package_id)

        current =
          Repo.all(from(q in QueueItem, where: q.id in ^ids, order_by: q.id, lock: "FOR UPDATE"))

        cond do
          length(current) < length(ids) -> Repo.rollback(:gone)
          Enum.any?(current, &(&1.status == :decided)) -> Repo.rollback(:already_decided)
          one_group(current, except) != :ok -> Repo.rollback(:not_one_group)
          true -> :ok
        end

        decided =
          for item <- current do
            this = if item.id in except, do: other_choice(chosen), else: chosen
            actor |> decide(item, package, this, files) |> unwrap_or_rollback()
          end

        settle(package, decided, files)
        decided
      end)
    end
  end

  defp group_decision(decision) do
    {except, choice} = Map.pop(decision, "except", [])

    cond do
      not (is_list(except) and Enum.all?(except, &is_integer/1)) ->
        {:error, :invalid_decision}

      choice in [%{"keep" => true}, %{"skip" => true}] ->
        {:ok, choice, except}

      match?(%{"keep" => true, "host_reading" => %{}}, choice) and map_size(choice) == 2 ->
        {:ok, choice, except}

      match?(%{"keep" => true, "host_taxon_id" => id} when is_integer(id), choice) and
          map_size(choice) == 2 ->
        {:ok, choice, except}

      true ->
        {:error, :invalid_decision}
    end
  end

  defp other_choice(%{"keep" => true}), do: %{"skip" => true}
  defp other_choice(%{"skip" => true}), do: %{"keep" => true}

  defp one_group([], _except), do: {:error, :not_one_group}

  defp one_group([first | _] = items, except) do
    group = first.subject["group"]
    ids = Enum.map(items, & &1.id)

    if is_binary(group) and Enum.all?(except, &(&1 in ids)) and
         Enum.all?(items, fn item ->
           item.kind == :dispute and item.package_id == first.package_id and
             item.subject["group"] == group
         end),
       do: :ok,
       else: {:error, :not_one_group}
  end

  defp collect({decided, skipped}, {:ok, item}, _item), do: {[item | decided], skipped}

  defp collect({decided, skipped}, {:skip, reason}, item),
    do: {decided, [{item, reason} | skipped]}

  defp accept(_actor, nil, _packages, _files), do: {:skip, :gone}

  defp accept(_actor, %QueueItem{status: :decided}, _packages, _files),
    do: {:skip, :already_decided}

  defp accept(actor, item, packages, files) do
    case Proposals.proposed(item) do
      {:none, reason} ->
        {:skip, reason}

      {:ok, decision} ->
        case decide(actor, item, packages[item.package_id], decision, files[item.package_id]) do
          {:ok, item} -> {:ok, item}
          {:error, changeset} -> {:skip, {:invalid, changeset}}
        end
    end
  end

  @doc """
  Rejects an open item's proposal (or suggestion): the item stays open,
  marked with who rejected it and when, and accepting proposals in bulk
  leaves it out. The mark lasts until the proposal is restored
  (`restore_proposal/2`) or a resolution proposes something else.

  Not in the replay log: it changes no data, and the decision made
  afterwards is logged on its own. (After the cutover replay an item still
  open shows its proposal again.)

  `{:error, :no_proposal}` for an item with neither; `{:error,
  :already_decided}`, `{:error, :gone}` as for `decide_queue_item/3`.
  """
  @spec reject_proposal(Actor.t(), QueueItem.t()) ::
          {:ok, QueueItem.t()} | {:error, :no_proposal | :already_decided | :gone}
  def reject_proposal(%Actor{} = actor, %QueueItem{} = item),
    do: mark_proposal(actor, item, actor)

  @doc "Restores an open item's rejected proposal (`reject_proposal/2`)."
  @spec restore_proposal(Actor.t(), QueueItem.t()) ::
          {:ok, QueueItem.t()} | {:error, :already_decided | :gone}
  def restore_proposal(%Actor{} = actor, %QueueItem{} = item), do: mark_proposal(actor, item, nil)

  defp mark_proposal(actor, %QueueItem{id: id}, rejecting) do
    operation = if rejecting, do: "import.reject_proposal", else: "import.restore_proposal"

    Audit.transaction(actor, operation, fn ->
      item = Repo.one(from(q in QueueItem, where: q.id == ^id, lock: "FOR UPDATE"))

      cond do
        item == nil ->
          Repo.rollback(:gone)

        item.status == :decided ->
          Repo.rollback(:already_decided)

        rejecting && not Proposals.rejectable?(item) ->
          Repo.rollback(:no_proposal)

        true ->
          item |> QueueItem.reject_changeset(rejecting) |> Repo.update() |> unwrap_or_rollback()
      end
    end)
  end

  # -- notes -------------------------------------------------------------------

  @doc """
  Saves `actor`'s note on `item`, open or decided, for the next curator
  (`Gallformers.Import.QueueItemNote`; matter `d213`). A note is not part
  of the decision and is not replayed; it stays with the item. The text is
  trimmed; a blank one is refused (`{:error, changeset}`, on `:text`), as
  is a note on an item that is gone (on `:queue_item_id`).
  """
  @spec add_note(Actor.t(), QueueItem.t(), String.t()) ::
          {:ok, QueueItemNote.t()} | {:error, Changeset.t()}
  def add_note(%Actor{} = actor, %QueueItem{} = item, text) do
    changeset = QueueItemNote.create_changeset(item, actor, text)

    if changeset.valid? do
      Audit.transaction(actor, "import.add_note", fn ->
        changeset |> Repo.insert() |> unwrap_or_rollback()
      end)
    else
      {:error, changeset}
    end
  end

  @doc "`item`'s saved notes, oldest first."
  @spec list_notes(QueueItem.t()) :: [QueueItemNote.t()]
  def list_notes(%QueueItem{id: id}) do
    Repo.all(
      from(n in QueueItemNote, where: n.queue_item_id == ^id, order_by: [n.inserted_at, n.id])
    )
  end

  @doc """
  `item`'s notes to show, oldest first: its saved notes and, for an older
  decision that carries a `"note"`, that note (unsaved: `id` nil, by who
  decided, when).
  """
  @spec notes_for(QueueItem.t()) :: [QueueItemNote.t()]
  def notes_for(%QueueItem{} = item), do: with_decision_note(list_notes(item), item)

  @doc "`notes_for/1` of each of `items`, by item ID, in one query."
  @spec notes_by_item([QueueItem.t()]) :: %{integer() => [QueueItemNote.t()]}
  def notes_by_item(items) when is_list(items) do
    ids = Enum.map(items, & &1.id)

    saved =
      from(n in QueueItemNote,
        where: n.queue_item_id in ^ids,
        order_by: [n.inserted_at, n.id]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.queue_item_id)

    Map.new(items, &{&1.id, with_decision_note(Map.get(saved, &1.id, []), &1)})
  end

  defp with_decision_note(notes, %QueueItem{decision: %{"note" => text}} = item)
       when is_binary(text) and text != "" do
    legacy = %QueueItemNote{
      queue_item_id: item.id,
      text: text,
      author_user_id: item.decided_by_user_id,
      author_name: item.decided_by_name,
      inserted_at: item.decided_at
    }

    Enum.sort_by(notes ++ [legacy], & &1.inserted_at, DateTime)
  end

  defp with_decision_note(notes, _item), do: notes

  # Passes the notes of `stale` open items (about to be deleted) to the open
  # item now queued about the same statement, if there is one; the rest go
  # with their items.
  defp pass_on_notes(_package, _batch_id, []), do: :ok

  defp pass_on_notes(package, batch_id, stale) do
    noted =
      from(n in QueueItemNote,
        where: n.queue_item_id in ^Enum.map(stale, & &1.id),
        distinct: true,
        select: n.queue_item_id
      )
      |> Repo.all()
      |> MapSet.new()

    stale_ids = Enum.map(stale, & &1.id)

    for q <- stale,
        MapSet.member?(noted, q.id),
        to = replacing_item(package, batch_id, q.statement_ref, stale_ids) do
      from(n in QueueItemNote, where: n.queue_item_id == ^q.id)
      |> Repo.update_all(set: [queue_item_id: to])
    end

    :ok
  end

  defp replacing_item(_package, _batch_id, nil, _stale_ids), do: nil

  defp replacing_item(package, batch_id, ref, stale_ids) do
    from(q in QueueItem,
      where:
        q.package_id == ^package.id and q.status == :open and q.statement_ref == ^ref and
          q.id not in ^stale_ids,
      order_by: [desc: q.id],
      limit: 1,
      select: q.id
    )
    |> in_batch(batch_id)
    |> Repo.one()
  end

  defp in_batch(query, nil), do: where(query, [q], is_nil(q.batch_id))
  defp in_batch(query, batch_id), do: where(query, [q], q.batch_id == ^batch_id)

  # Records and honours `decision` on the open, locked `item` (its package
  # locked, or nil), inside the caller's transaction, and logs it. The
  # package is not resolved again (`settle/3`). {:ok, item}, or {:error,
  # changeset} for a decision that does not fit.
  defp decide(actor, item, package, decision, files) do
    changeset =
      item
      |> QueueItem.decide_changeset(decision, actor)
      |> Queue.validate_decision(item, decision)

    if changeset.valid? do
      # What carrying it out logged, and what it says it moved besides
      # (a split's answer), kept with the decision for Undo.
      {{decision, moved}, logged} =
        ReplayLog.collect(fn -> actor |> carry_out(item, decision) |> carried_or_rollback() end)

      carried_out = Enum.map(logged, &entry_json/1) ++ moved

      item =
        changeset
        |> Changeset.put_change(:decision, decision)
        |> Repo.update()
        |> unwrap_or_rollback()

      item =
        case item.kind do
          :gall_rename -> GallRenames.honour(actor, item)
          _kind -> tap(item, &honour(actor, &1, package, files))
        end

      log_decision(item, carried_out)
      {:ok, item}
    else
      {:error, changeset}
    end
  end

  defp carry_out(actor, item, decision) do
    cond do
      HostDecisions.host?(item) -> HostDecisions.carry_out(actor, item, decision)
      GallDecisions.gall?(item) -> GallDecisions.carry_out(actor, item, decision)
      Disputes.host?(item) -> GallDecisions.carry_out(actor, item, decision)
      SynonymDecisions.synonym?(item) -> SynonymDecisions.carry_out(actor, item, decision)
      SplitQuestions.split?(item) -> SplitQuestions.carry_out(actor, item, decision)
      true -> {:ok, decision}
    end
  end

  # The decision carried out, with the `"carried_out"` entries it gives
  # beyond what it logged (none, but for a split's answer).
  defp carried_or_rollback({:ok, decision}), do: {decision, []}
  defp carried_or_rollback({:ok, decision, moved}), do: {decision, moved}
  defp carried_or_rollback({:error, reason}), do: Repo.rollback(reason)

  # The package's files when a decision on `items` will resolve it again (a
  # batch's item, the package resolvable) or write a set-aside item's Facts
  # (its batch applied); nil otherwise, or when the bucket cannot be read
  # (a decision is then honoured on its statement alone, and the next
  # resolution does the rest; set-aside Facts read the files again).
  defp decision_files(nil, _items), do: nil

  defp decision_files(package_id, items) do
    package = get_package!(package_id)

    needed? =
      Enum.any?(items, fn item ->
        cond do
          not is_integer(item.batch_id) -> false
          written_later?(item) -> get_batch!(item.batch_id).status == :applied
          true -> package.status in @resolvable
        end
      end)

    with true <- needed?, {:ok, files} <- read_package_files(package) do
      files
    else
      _ -> nil
    end
  end

  # Applies a decision to its stored statement, inside the caller's
  # transaction; the package is resolved again afterwards (`settle/3`).
  defp honour(_actor, %QueueItem{batch_id: nil}, _package, _files), do: :ok

  # What was set aside bears on no statement; its Facts are written when
  # the gall batch is applied, or now if it is
  # (`Gallformers.Import.SetAside`).
  defp honour(actor, %QueueItem{kind: :set_aside_statement} = item, package, files) do
    batch = get_batch!(item.batch_id)

    if batch.status == :applied and batch.batch_type == :gall do
      files = files || package |> read_package_files() |> unwrap_or_rollback()
      write_set_aside(actor, package, batch, [item], files)
    end

    :ok
  end

  # A Trait term's question: the term changes, then its waiting uses are
  # settled, getting their Facts where their batch is applied
  # (`Gallformers.Import.TraitTerms`).
  defp honour(actor, %QueueItem{kind: :trait_term} = item, package, files) do
    actor |> TraitTerms.change_term(item) |> unwrap_or_rollback()
    %{"trait" => trait, "term" => term} = item.subject

    if TraitTerms.every_source?(item.decision) do
      decide_with(actor, item)
      categories = TraitTerms.settled_categories(item.decision)
      # Placed under its categories, or (no_fit) kept as text because it fits none.
      settled = Catalog.settle_pending_terms(actor, trait, term, categories, as: :no_fit)
      settled |> unwrap_or_rollback() |> write_settled(actor, package, files)
    else
      item
      |> TraitTerms.settlements()
      |> Enum.flat_map(&settle_uses(actor, item, &1))
      |> write_settled(actor, package, files)
    end
  end

  # A dispute dropped: a dropped Trait Fact's words stay as text, and the
  # term waiting on the dispute (its batch applied) is settled as text.
  defp honour(
         actor,
         %QueueItem{kind: :dispute, decision: %{"skip" => true}} = item,
         _package,
         _files
       ) do
    batch = get_batch!(item.batch_id)
    insert_texts(batch, Disputes.texts(item, batch.content))

    if Disputes.trait?(item) do
      %{"trait" => trait, "term" => term} = item.subject

      actor
      |> Catalog.settle_pending_terms(trait, term, nil, queue_item_id: item.id, as: :kept)
      |> unwrap_or_rollback()
    end

    honour_statement(item)
  end

  # A Trait dispute kept after its batch was applied: its Facts, which
  # waited, are written now (`Gallformers.Import.Disputes`).
  defp honour(
         actor,
         %QueueItem{kind: :dispute, decision: %{"keep" => true}} = item,
         package,
         files
       ) do
    batch = get_batch!(item.batch_id)

    if batch.status == :applied and Disputes.trait?(item) do
      files = files || package |> read_package_files() |> unwrap_or_rollback()
      write_kept_traits(actor, package, batch, item, files)
    end

    honour_statement(item)
  end

  defp honour(_actor, item, _package, _files), do: honour_statement(item)

  # Inside the caller's transaction, the package locked: the Trait Facts of
  # a kept dispute (its refs) for an applied gall batch, as applying the
  # batch would have written them (the term's standing or question), or
  # stored as waiting terms (on the term's question). The term waiting on
  # the dispute is settled under the categories its Facts were written on.
  defp write_kept_traits(actor, package, batch, item, files) do
    refs = Disputes.refs(item)
    others = for f <- List.wrap(batch.content["facts"]), f["id"] not in refs, do: f["id"]
    ours? = fn id -> id |> String.split("+") |> hd() |> then(&(&1 in refs)) end

    term_items =
      package
      |> list_queue_items(kind: :trait_term, status: :all)
      |> Enum.filter(&(&1.batch_id == batch.id))

    plan =
      TraitTerms.apply_plan(batch.content, decode(files["review.json"]),
        file: batch.file,
        drop: others,
        items: term_items
      )

    facts = Enum.filter(plan.facts, &ours?.(&1["id"]))

    write_later(actor, package, batch, files, fn ctx ->
      waiting =
        Enum.filter(plan.waiting, fn %{use: use} -> Enum.any?(use.facts, &(&1.ref in refs)) end)

      with :ok <- TraitTerms.record_edits(actor, plan.edits),
           {:ok, result} <- ApplyGall.run_facts(ctx, facts),
           :ok <-
             TraitTerms.store_waiting(
               Map.put(ctx, :term_items, term_items),
               waiting,
               ctx.gall_ids
             ),
           :ok <- settle_disputed(actor, item, facts) do
        {:ok, result}
      end
    end)
  end

  # The terms waiting on dispute `item`, settled under the categories
  # its kept Facts (`facts`, the contract's shape) were written on.
  defp settle_disputed(actor, item, facts) do
    facts
    |> Enum.group_by(&{&1["trait"], &1["term"]}, &get_in(&1, ["value", "value"]))
    |> Enum.reduce_while(:ok, fn {{trait, term}, categories}, :ok ->
      opts = [queue_item_id: item.id]

      case Catalog.settle_pending_terms(actor, trait, term, Enum.uniq(categories), opts) do
        {:ok, _settled} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # The question's waiting uses settled under `categories` (all of them, or
  # those of the Facts `refs`).
  defp settle_uses(actor, %QueueItem{subject: subject} = item, {categories, refs}) do
    narrowed = if refs == :all, do: [], else: [statement_refs: refs]
    opts = [queue_item_id: item.id] ++ narrowed

    actor
    |> Catalog.settle_pending_terms(subject["trait"], subject["term"], categories, opts)
    |> unwrap_or_rollback()
  end

  defp honour_statement(%QueueItem{batch_id: batch_id, statement_ref: ref} = item) do
    statement =
      Repo.one(
        from(s in BatchStatement,
          where: s.batch_id == ^batch_id and s.ref == ^ref and s.kind in [:taxon, :gall]
        )
      )

    if statement do
      decided = Queue.apply_decision(statement, Queue.statement_decision(item))

      if decided != statement do
        statement
        |> Changeset.change(
          Map.take(decided, [:resolution, :taxon_id, :gall_id, :method, :flags, :detail])
        )
        |> Repo.update!()
      end
    end

    :ok
  end

  # A dropped Trait Fact's words, kept as text on its Gall: `unmapped`
  # entries after the batch's own.
  defp insert_texts(_batch, []), do: :ok

  defp insert_texts(batch, texts) do
    last =
      Repo.one(from(u in BatchUnmapped, where: u.batch_id == ^batch.id, select: max(u.position)))

    rows =
      texts
      |> Enum.with_index((last || -1) + 1)
      |> Enum.map(fn {text, position} ->
        Map.merge(text, %{batch_id: batch.id, position: position})
      end)

    Repo.insert_all(BatchUnmapped, rows)
    :ok
  end

  # After decisions on `items` of `package` (locked, or nil): resolves the
  # package again when one of them is about a batch's statement and it can
  # be (the decisions then hold for each name in every batch, and the
  # Galls are matched again: a Gall waiting on its Inducer is matched once
  # the Inducer is decided), else brings those batches' status up to date.
  defp settle(nil, _items, _files), do: :ok

  defp settle(package, items, files) do
    batch_ids =
      for item <- items,
          is_integer(item.batch_id),
          not written_later?(item),
          uniq: true,
          do: item.batch_id

    cond do
      batch_ids == [] -> :ok
      files && package.status in @resolvable -> resolve(package, files)
      true -> Enum.each(batch_ids, &refresh_batch_status(get_batch!(&1)))
    end

    :ok
  end

  # Items bearing on no statement, whose Facts are written when their batch
  # is applied, or at once once it is: what was set aside, a Trait term.
  defp written_later?(%QueueItem{kind: :trait_term}), do: true

  # A Trait dispute decided after its batch was applied.
  defp written_later?(%QueueItem{kind: :dispute, batch_id: id} = item) when is_integer(id),
    do: Disputes.trait?(item) and get_batch!(id).status == :applied

  defp written_later?(item), do: SetAside.set_aside?(item)

  # Decides the other open questions about `item`'s term, in every
  # package, as `item` is: placing the term, or fitting none, holds for
  # every Source. Not logged: replaying `item`'s decision decides them again.
  defp decide_with(actor, %QueueItem{} = item) do
    decision =
      item.decision
      |> Map.take(["place", "no_fit"])
      |> Map.put("note", "settled for every Source by another package's question")

    from(q in QueueItem,
      where:
        q.kind == :trait_term and q.status == :open and q.statement_ref == ^item.statement_ref and
          q.id != ^item.id,
      lock: "FOR UPDATE"
    )
    |> Repo.all()
    |> Enum.each(fn q ->
      q |> QueueItem.decide_changeset(decision, actor) |> Repo.update() |> unwrap_or_rollback()
    end)
  end

  # Inside the caller's transaction (`package` locked, `files` its files or
  # nil): writes the Trait Facts of `settled` waiting terms under their
  # categories (one Fact each), each in its batch (applied: a waiting term
  # is stored when its batch is applied), attributed to that batch's Source.
  defp write_settled(settled, actor, package, files) do
    settled
    |> Enum.filter(&(&1.settled_categories != []))
    |> Enum.group_by(& &1.batch_id)
    |> Enum.sort()
    |> Enum.each(fn {batch_id, terms} ->
      batch = get_batch!(batch_id)

      {pkg, files} =
        if package && batch.package_id == package.id,
          do: {package, files || package |> read_package_files() |> unwrap_or_rollback()},
          else: batch.package_id |> lock_package() |> with_files()

      facts =
        Enum.flat_map(
          terms,
          &TraitTerms.facts_for(batch.content, &1.statement_ref, &1.settled_categories)
        )

      write_later(actor, pkg, batch, files, &ApplyGall.run_facts(&1, facts))
    end)
  end

  defp with_files(package), do: {package, package |> read_package_files() |> unwrap_or_rollback()}

  defp refresh_batch_status(%Batch{batch_type: :gall, status: status} = batch)
       when status in [:ready, :blocked] do
    held? = batch |> list_statements() |> Queue.holds_gall_batch?()
    new_status = if held?, do: :blocked, else: :ready

    if new_status != status do
      batch |> Batch.status_changeset(new_status) |> Repo.update() |> unwrap_or_rollback()
    end

    :ok
  end

  defp refresh_batch_status(_batch), do: :ok

  # The decision, keyed by stable references (`decision_key/1`); a decision
  # that may have changed the tree keeps the entries carrying it out
  # logged before it (`"carried_out"`), and a split's answer what it
  # moved, for Undo (`Gallformers.Import.Undo`).
  defp log_decision(%QueueItem{} = item, carried_out) do
    payload = %{"decision" => StableRef.encode_decision(item.decision)}

    payload =
      case item.kind do
        :gall_rename -> Map.put(payload, "from", item.proposal["from"])
        _kind -> payload
      end

    payload =
      if Undo.tree_item?(item),
        do: Map.put(payload, "carried_out", carried_out),
        else: payload

    ReplayLog.append!(:queue_decision, decision_key(item), payload)
  end

  defp entry_json(%ReplayEntry{kind: kind, key: key, payload: payload}),
    do: %{"kind" => Atom.to_string(kind), "key" => key, "payload" => payload || %{}}

  # A decision's `:queue_decision` key. A rename proposal and a split
  # question come from no package: found again by their Gall (and the name
  # decided for, the split taxon).
  defp decision_key(%QueueItem{kind: :gall_rename} = item), do: GallRenames.replay_key(item)
  defp decision_key(%QueueItem{kind: :split_inducer} = item), do: SplitQuestions.replay_key(item)

  # A same-date conflict a merge brought about comes from no package
  # (`Gallformers.Import.Merge`): found again by its Gall and statement ref.
  defp decision_key(%QueueItem{kind: :same_date_conflict, package_id: nil} = item) do
    gall_id = item.subject["gall_id"]

    %{
      "kind" => "same_date_conflict",
      "merge" => true,
      "gall" => gall_id && StableRef.gall(gall_id),
      "statement_ref" => item.statement_ref
    }
  end

  defp decision_key(%QueueItem{} = item) do
    package = get_package!(item.package_id)
    batch = item.batch_id && get_batch!(item.batch_id)

    %{
      "package" => package.key,
      "batch_id" => batch && batch.producer_batch_id,
      "kind" => Atom.to_string(item.kind),
      "statement_ref" => item.statement_ref
    }
  end

  # -- undo ------------------------------------------------------------------

  @doc """
  Undoes `actor`'s or anyone's decision on `item` (matter `f14c`, "Undo
  rule"; `Gallformers.Import.Undo` says what each kind puts back): allowed
  only while nothing depends on it — the Source isn't approved yet, and
  nothing the decision changed has been edited since, per the audit log.
  The tree edits it made are reversed, the item opens again (its ID and
  notes kept) and its package is resolved again, in one audited
  transaction, logged for replay (`:queue_decision_undone`; a taxonomic
  statement's is its reopening, `reopen_taxonomic_statement/2`).

  Returns the item, open again (or the question resolving again asks in
  its place; nil when none is needed any more). Refused (nothing
  changes) with why (`undo_refusal/1` says it in words): `:not_decided`, `:gone`,
  `:source_approved`, `:package_denied`, `:no_trail` (the audit trail
  holds no record of the decision), `{:edited, edit}` (who changed what
  since, and when), `{:cannot_undo, why}`, `{:referenced, references}` (a
  taxon it created is used since).
  """
  @spec undo_decision(Actor.t(), QueueItem.t()) ::
          {:ok, QueueItem.t() | nil} | {:error, Undo.refusal() | term()}
  def undo_decision(%Actor{} = actor, %QueueItem{kind: :taxonomy_acceptance} = item) do
    Audit.transaction(actor, "import.undo_decision", fn ->
      item = item.id |> lock_item() |> undoable(nil)

      case TaxonomicDecisions.decide(actor, :reopen, item.subject["attribution_id"]) do
        {:ok, _result} -> Repo.get!(QueueItem, item.id)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def undo_decision(%Actor{} = actor, %QueueItem{} = item) do
    files = item.package_id && undo_files(get_package!(item.package_id))

    Audit.transaction(actor, "import.undo_decision", fn ->
      # The package first, as resolving locks it before its items.
      package = item.package_id && lock_package(item.package_id)
      item = item.id |> lock_item() |> undoable(package)
      ops = item |> carried_out() |> Undo.reversal() |> unwrap_or_rollback()
      key = decision_key(item)
      undo(actor, item, package, ops, files, key)
    end)
  end

  @doc """
  Undoes the decisions on `items` (a group of disputes decided together,
  `decide_group/3`), each as `undo_decision/2` undoes it, all or none: the
  first refusal rolls them all back. Returns the items as they are now.
  """
  @spec undo_decisions(Actor.t(), [QueueItem.t()]) ::
          {:ok, [QueueItem.t() | nil]} | {:error, Undo.refusal() | term()}
  def undo_decisions(%Actor{} = actor, items) when is_list(items) do
    Audit.transaction(actor, "import.undo_decision", fn ->
      for item <- items do
        case undo_decision(actor, item) do
          {:ok, undone} -> undone
          {:error, reason} -> Repo.rollback(reason)
        end
      end
    end)
  end

  @doc "Why `undo_decision/2` refused, in words, with the record to change instead (`Gallformers.Import.Undo.refusal/1`)."
  @spec undo_refusal(term()) :: %{text: String.t(), link: {:taxon | :gall, integer()} | nil}
  defdelegate undo_refusal(reason), to: Undo, as: :refusal

  @doc """
  Replays a logged undo (`Gallformers.Import.Replay`): `item` (found by
  the entry's key, or nil when no item asks any more) is reopened if
  decided, the logged reverse tree edits made where not done already, and
  `package` (or nil) resolved again, logged again with `key`.
  """
  @spec replay_undo(Actor.t(), QueueItem.t() | nil, Package.t() | nil, map(), map()) ::
          {:ok, QueueItem.t() | nil} | {:error, term()}
  def replay_undo(%Actor{} = actor, item, package, key, payload) do
    files = package && undo_files(package)

    Audit.transaction(actor, "import.undo_decision", fn ->
      package = package && lock_package(package.id)
      item = item && lock_item(item.id)
      undo(actor, item, package, List.wrap(payload["reverse"]), files, key)
    end)
  end

  defp lock_item(id), do: Repo.one(from(q in QueueItem, where: q.id == ^id, lock: "FOR UPDATE"))

  # The locked `item`, if the rule lets it be undone; else rolls back with why.
  defp undoable(nil, _package), do: Repo.rollback(:gone)
  defp undoable(%QueueItem{status: :open}, _package), do: Repo.rollback(:not_decided)

  defp undoable(%QueueItem{} = item, package) do
    batch_status = item.batch_id && get_batch!(item.batch_id).status
    :ok = item |> Undo.check(package, batch_status) |> or_rollback()

    case Undo.decision_transaction(item.id) do
      nil ->
        Repo.rollback(:no_trail)

      transaction_id ->
        :ok = item |> Undo.reversible(transaction_id) |> or_rollback()

        case Undo.edited_since(transaction_id) do
          nil -> item
          edit -> Repo.rollback({:edited, edit})
        end
    end
  end

  defp or_rollback(:ok), do: :ok
  defp or_rollback({:error, reason}), do: Repo.rollback(reason)

  # What the decision's carrying out logged before it, from its latest
  # `:queue_decision` entry. A decision that may have changed the tree and
  # kept nothing was made before decisions kept them.
  defp carried_out(%QueueItem{} = item) do
    if Undo.tree_item?(item) do
      key = decision_key(item)

      entry =
        Repo.one(
          from(e in ReplayEntry,
            where: e.kind == :queue_decision and e.key == ^key,
            order_by: [desc: e.id],
            limit: 1
          )
        )

      case entry do
        %ReplayEntry{payload: %{"carried_out" => entries}} when is_list(entries) -> entries
        _ -> Repo.rollback({:cannot_undo, :no_record})
      end
    else
      []
    end
  end

  # The package's files when an undo will resolve it again; nil otherwise,
  # or when the bucket cannot be read (the next resolution does it then).
  defp undo_files(%Package{status: status} = package) when status in @resolvable do
    case read_package_files(package) do
      {:ok, files} -> files
      _error -> nil
    end
  end

  defp undo_files(_package), do: nil

  # Inside the caller's transaction (the package locked): puts back what
  # decided `item` changed, reopens it, makes the reverse tree edits `ops`,
  # resolves the package again and logs the undo under `key`.
  defp undo(actor, item, package, ops, files, key) do
    item =
      case item do
        %QueueItem{status: :decided} ->
          :ok = Undo.put_back(actor, item, package)
          Undo.reopen(item)

        other ->
          other
      end

    if package, do: Undo.clear_statements(package, Undo.deleted_taxa(ops))
    :ok = Undo.run(actor, ops)

    if package && files && package.status in @resolvable,
      do: resolve(Repo.get!(Package, package.id), files)

    ReplayLog.append!(:queue_decision_undone, key, %{"reverse" => ops})
    item && (Repo.get(QueueItem, item.id) || asked_now(item))
  end

  # The open item resolving again queued about `item`'s statement in its
  # place (another kind of question now), or nil when none is needed.
  defp asked_now(%QueueItem{package_id: nil}), do: nil

  defp asked_now(%QueueItem{} = item) do
    from(q in QueueItem,
      where:
        q.package_id == ^item.package_id and q.status == :open and
          q.statement_ref == ^item.statement_ref,
      order_by: [desc: q.id],
      limit: 1
    )
    |> in_batch(item.batch_id)
    |> Repo.one()
  end

  @doc """
  Writes the Facts a decided set-aside item (`Gallformers.Import.SetAside`;
  its `decision` as given) states, when its gall batch is applied already:
  one per covered Gall, attributed to the batch's Source with the entries'
  evidence, as applying the batch writes them. Writing again changes
  nothing. `{:ok, :not_applied}` while the batch is not applied (applying
  it writes them). `decide_queue_item/3` calls it for a decision made after
  the batch was applied.
  """
  @spec apply_set_aside_decision(Actor.t(), QueueItem.t()) ::
          {:ok, :written | :not_applied} | {:error, term()}
  def apply_set_aside_decision(%Actor{} = actor, %QueueItem{batch_id: batch_id} = item)
      when is_integer(batch_id) do
    package = get_package!(item.package_id)

    with {:ok, files} <- read_package_files(package) do
      Audit.transaction(actor, "import.apply_set_aside_decision", fn ->
        package = lock_package(package.id)
        batch = get_batch!(batch_id)

        if batch.status == :applied and batch.batch_type == :gall do
          write_set_aside(actor, package, batch, [item], files)
          :written
        else
          :not_applied
        end
      end)
    end
  end

  # Inside the caller's transaction, the package locked: the set-aside
  # items' Facts for an applied gall batch, its Galls as applied.
  defp write_set_aside(actor, package, batch, items, files),
    do: write_later(actor, package, batch, files, &ApplyGall.run_set_aside(&1, items))

  # Inside the caller's transaction, the package locked: what `run` (given
  # the batch's context, with its Galls as applied) writes for an applied
  # gall batch, recorded as its statements.
  defp write_later(actor, package, batch, files, run) do
    galls =
      for %{kind: :gall, gall_id: id} = s <- list_statements(batch),
          is_integer(id) and "skipped" not in s.flags,
          into: %{},
          do: {s.ref, id}

    result =
      actor
      |> batch_context(package, batch, files)
      |> Map.put(:gall_ids, galls)
      |> run.()
      |> unwrap_or_rollback()

    refs = Enum.map(result.statements, & &1.ref)

    Repo.delete_all(
      from(s in BatchStatement,
        where: s.batch_id == ^batch.id and s.kind == :fact and s.ref in ^refs
      )
    )

    record_applied(package, batch, result)
  end

  # -- approval ----------------------------------------------------------------

  @doc """
  Whether an open `item` of a batch of `batch_type` (nil for the package)
  holds the package's approval (`Gallformers.Import.Queue.blocking?/2`).
  """
  @spec blocking?(QueueItem.t(), :taxonomy | :gall | nil) :: boolean()
  defdelegate blocking?(item, batch_type), to: Queue

  @doc """
  Approves a package awaiting review and has the import worker apply it
  (`Gallformers.Import.Worker`; inline in tests).

  Approval waits for every open queue item a batch needs
  (`Gallformers.Import.Queue.blocking?/2`: `{:error, {:open_items, items}}`)
  and for every batch to be free of unresolved Host names
  (`{:error, {:blocked, batches}}`). Only a package `:awaiting_review` can
  be approved (`{:error, :not_approvable}`).
  """
  @spec approve_package(Actor.t(), Package.t()) ::
          {:ok, Package.t()}
          | {:error,
             :not_approvable | {:open_items, [QueueItem.t()]} | {:blocked, [Batch.t()]} | term()}
  def approve_package(%Actor{} = actor, %Package{} = package) do
    package = get_package!(package.id)
    pending = pending_batches(package)

    with :ok <- approvable(package),
         [] <- open_blocking_items(package, nil) |> none_or(:open_items),
         [] <- Enum.filter(pending, &(&1.status == :blocked)) |> none_or(:blocked),
         {:ok, package} <-
           Audit.transaction(actor, "import.approve_package", fn ->
             package = lock_package(package.id)
             if package.status != :awaiting_review, do: Repo.rollback(:not_approvable)

             package
             |> Package.status_changeset(:approved)
             |> Repo.update()
             |> unwrap_or_rollback()
           end),
         {:ok, _job} <- enqueue_package(actor, package) do
      {:ok, get_package!(package.id)}
    end
  end

  @doc """
  Approves each of `packages` in turn (`approve_package/2`), as the
  Gallformers notes' bulk approve does (`6611` Task 7): those nothing holds
  are approved; the others are refused, each with `approve_package/2`'s
  reason. Both lists keep the order given.
  """
  @spec approve_packages(Actor.t(), [Package.t()]) :: %{
          approved: [Package.t()],
          refused: [{Package.t(), term()}]
        }
  def approve_packages(%Actor{} = actor, packages) when is_list(packages) do
    results = Enum.map(packages, &{&1, approve_package(actor, &1)})

    %{
      approved: for({_package, {:ok, approved}} <- results, do: approved),
      refused: for({package, {:error, reason}} <- results, do: {package, reason})
    }
  end

  defp approvable(%Package{status: :awaiting_review}), do: :ok
  defp approvable(_package), do: {:error, :not_approvable}

  defp none_or([], _tag), do: []
  defp none_or(found, tag), do: {:error, {tag, found}}

  # Open items that hold `batch` (or, with nil, any batch) and the package.
  defp open_blocking_items(package, batch) do
    types = package |> list_batches() |> Map.new(&{&1.id, &1.batch_type})

    package
    |> list_queue_items()
    |> Enum.filter(fn item ->
      (batch == nil or item.batch_id in [nil, batch.id]) and
        Queue.blocking?(item, types[item.batch_id])
    end)
  end

  defp pending_batches(package),
    do: package |> list_batches() |> Enum.reject(&(&1.status in [:applied, :denied]))

  # -- the Facts preview and edits -------------------------------------------------

  @doc """
  What approving `package` would write, given the answers so far (matter
  `f14c`, item 4; `Gallformers.Import.Preview`): the apply the approval
  runs, run as `actor` (default the system actor `"preview"`) in one
  transaction that is always rolled back. Every batch not applied or
  denied is applied, the taxonomy batch first and the package resolved
  again before the next, whatever its status: a batch held by a question
  writes what resolves, and what waits on a question says which. A
  package question not decided yet (its Source, the Source a notice
  retracts) is taken as a new Source and no retraction, for the preview
  only. The curator's edits on Facts (`edit_fact/5`) are honoured, as
  approval honours them.

  Returns:

      %{
        package_id: id,
        ready?: whether `approve_package/2` would approve it now,
        blocking: %{count, by_kind: %{kind => n}, items: [%{id, kind,
                    statement_ref, batch_id}], blocked_batches: [file]},
        galls: [Gall header with its `facts` by category],
        taxonomy: %{new_taxa: [...], acts: [entries]},
        counts: %{new, held, conflict, waiting, dropped},
        errors: [%{file, reason}],  # a batch the preview could not apply
        applied: [file]              # batches applied already
      }

  The shape of a Gall header and a Fact entry is
  `Gallformers.Import.FactsView`'s. `{:error, reason}` when the package's
  files cannot be read.
  """
  @spec preview_package(Package.t(), Actor.t()) :: {:ok, map()} | {:error, term()}
  def preview_package(%Package{} = package, %Actor{} = actor \\ Actor.system("preview")) do
    package = get_package!(package.id)
    batches = list_batches(package)
    pending = pending_batches(package)

    with {:ok, collected} <- preview_batches(actor, package, pending) do
      items = list_queue_items(package)

      {:ok,
       collected
       |> Enum.filter(&Map.has_key?(&1, :entries))
       |> Preview.finish(items)
       |> Map.merge(%{
         package_id: package.id,
         ready?: ready?(package, items, pending),
         blocking: blocking(package, items, pending),
         errors:
           for(%{error: reason, batch: b} <- collected, do: %{file: b.file, reason: reason}),
         applied: for(%{status: :applied, file: file} <- batches, do: file)
       })}
    end
  end

  defp preview_batches(_actor, _package, []), do: {:ok, []}

  defp preview_batches(actor, package, pending) do
    with {:ok, files} <- read_package_files(package) do
      # Nothing of it is kept: no Gall index refresh, no object stored (a
      # new Source's document), and the transaction rolled back.
      Catalog.without_gall_index_refresh(fn ->
        Private.without_writes(fn -> rolled_back(actor, package, pending, files) end)
      end)
    end
  end

  defp rolled_back(actor, package, pending, files) do
    actor
    |> Audit.transaction("import.preview_package", fn ->
      Repo.rollback({:preview, preview_in_transaction(actor, package, pending, files)})
    end)
    |> case do
      {:error, {:preview, collected}} -> {:ok, collected}
      {:error, reason} -> {:error, reason}
    end
  end

  # As applying does, the package is resolved again before a batch after
  # the first, against the taxa the batch before created. The stored
  # statements are current otherwise: each decision resolves the package
  # again, and applying a taxonomy batch changes the tree only by creating
  # its new taxa. A package question not decided yet is taken as a new
  # Source and no retraction.
  defp preview_in_transaction(actor, package, pending, files) do
    defaults = %{"source" => %{"new" => true}, "retracts" => %{"skip" => true}}

    {collected, _created?} =
      Enum.map_reduce(pending, false, fn batch, created? ->
        if created?, do: package.id |> get_package!() |> resolve(files)
        package = get_package!(package.id)
        collected = preview_batch(actor, package, get_batch!(batch.id), files, defaults)
        {collected, created_taxa?(collected)}
      end)

    collected
  end

  # Applies one batch inside the preview's transaction and collects what it wrote.
  defp preview_batch(actor, package, batch, files, defaults) do
    ctx = apply_context(actor, package, batch, files, defaults)
    plan = Preview.plan(ctx)

    case runner(batch).run(ctx) do
      {:ok, result} ->
        collected =
          Preview.collect(ctx, result,
            plan: plan,
            items: list_queue_items(package),
            batches: list_batches(package),
            edits: FactEdits.for_batch(batch.id)
          )

        # The next batch resolves against this one, applied.
        batch |> Batch.status_changeset(:applied) |> Repo.update!()
        collected

      {:error, reason} ->
        %{batch: batch, error: reason}
    end
  end

  # A statement ref in batch order: "f2" before "f10"; none last.
  defp ref_order(nil), do: {1, 0, ""}

  defp ref_order(ref) do
    case Regex.run(~r/\A\D*(\d+)/, ref) do
      [_, n] -> {0, String.to_integer(n), ref}
      nil -> {0, 0, ref}
    end
  end

  defp created_taxa?(%{created: %{taxa: taxa}}), do: MapSet.size(taxa) > 0
  defp created_taxa?(_failed), do: false

  defp ready?(package, items, pending) do
    types = package |> list_batches() |> Map.new(&{&1.id, &1.batch_type})

    package.status == :awaiting_review and
      not Enum.any?(items, &Queue.blocking?(&1, types[&1.batch_id])) and
      not Enum.any?(pending, &(&1.status == :blocked))
  end

  defp blocking(package, items, pending) do
    types = package |> list_batches() |> Map.new(&{&1.id, &1.batch_type})
    open = Enum.filter(items, &Queue.blocking?(&1, types[&1.batch_id]))

    %{
      count: length(open),
      by_kind: Enum.frequencies_by(open, & &1.kind),
      items:
        for(
          q <- open,
          do: %{id: q.id, kind: q.kind, statement_ref: q.statement_ref, batch_id: q.batch_id}
        ),
      blocked_batches: for(%{status: :blocked, file: file} <- pending, do: file)
    }
  end

  @doc """
  Edits Fact (or act) `ref` of `batch` before approval
  (`Gallformers.Import.FactEdits`): `%{"drop" => true}`,
  `%{"host_taxon_id" => plant}` (a Host statement), `%{"values" => [v]}`
  (a Trait statement) or `%{"note" => text}`, any with a `"note"`.
  Applying the batch, and so the preview, honours it; the replay log
  records it. Only a package awaiting review, and a batch not applied or
  denied (`{:error, :not_editable}`).
  """
  @spec edit_fact(Actor.t(), Package.t(), Batch.t(), String.t(), map()) ::
          {:ok, StatementEdit.t()} | {:error, term()}
  defdelegate edit_fact(actor, package, batch, ref, edit), to: FactEdits, as: :edit

  @doc "Removes an edit on a Fact, undoing it (`edit_fact/5`); the replay log records it."
  @spec remove_fact_edit(Actor.t(), StatementEdit.t()) ::
          {:ok, StatementEdit.t()} | {:error, :not_editable | :not_found}
  defdelegate remove_fact_edit(actor, edit), to: FactEdits, as: :remove

  @doc "A package's edits on its Facts, by batch, statement ref and kind."
  @spec list_fact_edits(Package.t()) :: [StatementEdit.t()]
  defdelegate list_fact_edits(package), to: FactEdits, as: :list

  @doc """
  What Source `source_id` states (its attributions), as the Facts page
  shows it (`Gallformers.Import.FactsView`): `galls`, its gall Facts
  grouped by Gall and category, each entry with the Fact's `standing`; and
  `taxonomy`, `%{new_taxa: [], acts}`, its taxonomic statements
  (`FactsView.act_entries/1`), each with the Fact's standing and the
  curator's mark (accepted, declined with the reason, or awaiting a
  curator; matter `f923`). Every entry has its statement ref where an
  import batch wrote it.

  Options: `gall_ids` keeps the gall Facts to those resting on these Galls
  (`Gallformers.Catalog.facts_about_galls/1`), for a Source stating Facts
  about thousands of Galls (the legacy data); its taxonomic statements are
  all there either way.
  """
  @spec facts_for_source(integer(), keyword()) :: %{galls: [map()], taxonomy: map()}
  def facts_for_source(source_id, opts \\ []) when is_integer(source_id) do
    fact_ids = source_gall_fact_ids(source_id, opts[:gall_ids])
    taxonomic = Facts.list_source_attributions(source_id, "taxon_")
    refs = statement_refs(fact_ids ++ Map.keys(taxonomic))

    entries =
      for e <- FactsView.entries(source_id, fact_ids) do
        {batch_id, ref} = Map.get(refs, e.fact_id, {e.batch_id, nil})

        value =
          case e.value do
            %{of_fact_id: of} = v -> %{v | of_ref: refs[of] && elem(refs[of], 1)}
            v -> v
          end

        %{e | ref: ref, batch_id: batch_id, value: value} |> Map.drop([:slot])
      end
      |> Enum.sort_by(&{&1.batch_id || 0, ref_order(&1.ref), &1.fact_id})

    names = entries |> Enum.map(& &1.gall) |> Enum.filter(&is_integer/1) |> FactsView.gall_names()

    headers =
      for {id, %{name: name}} <- Enum.sort_by(names, fn {_id, n} -> n.name end) do
        %{
          key: id,
          ref: nil,
          gall_id: id,
          new: false,
          name_as_written: nil,
          name: name,
          status: :resolved,
          question: nil,
          why: nil
        }
      end

    acts =
      for e <- taxonomic |> Map.values() |> FactsView.act_entries() do
        {batch_id, ref} = Map.get(refs, e.fact_id, {e.batch_id, nil})
        %{e | ref: ref, batch_id: batch_id} |> Map.drop([:slot])
      end
      |> Enum.sort_by(&{&1.batch_id || 0, ref_order(&1.ref), &1.fact_id})

    %{galls: FactsView.group(headers, entries), taxonomy: %{new_taxa: [], acts: acts}}
  end

  # The gall Facts the Source states, in ID order; only those resting on
  # `gall_ids` when given.
  defp source_gall_fact_ids(source_id, gall_ids) do
    query =
      from(a in Facts.Attribution,
        join: f in Facts.Fact,
        on: f.id == a.fact_id,
        where: a.source_id == ^source_id and like(f.kind, "gall_%"),
        order_by: a.fact_id,
        select: a.fact_id
      )

    case gall_ids do
      nil ->
        Repo.all(query)

      ids ->
        resting = for row <- Catalog.facts_about_galls(ids), do: row.fact_id
        Repo.all(from([a] in query, where: a.fact_id in ^resting))
    end
  end

  # -- corrections to a Source's Facts (matter `f14c`) ---------------------------

  @doc """
  Corrects Source `source_id`'s statement of Fact `fact_id` after approval
  (`Gallformers.Import.SourceCorrections`): `:withdraw` (the Source didn't
  say it), or the Fact it did state instead, `{:host, plant_id}`,
  `{:values, [value]}`, `{:parent, taxon_id | nil}` or
  `{:accepted, taxon_id}`, its words carried over. The Fact is never
  edited; other Sources' statements of it stay. `note` (why) is required.
  Audited, recorded (`list_source_corrections/1`, moving the Source's
  Updated date) and logged for replay. Options: `accept: true` accepts a
  taxonomic statement stated anew in the same step (else it awaits a
  curator, asked in the taxonomy queue).
  """
  @spec correct_source_fact(
          Actor.t(),
          integer(),
          integer(),
          SourceCorrections.correction(),
          String.t() | nil,
          keyword()
        ) :: {:ok, SourceCorrections.result()} | {:error, SourceCorrections.error()}
  defdelegate correct_source_fact(actor, source_id, fact_id, correction, note, opts \\ []),
    to: SourceCorrections,
    as: :correct

  @doc "Source `source_id`'s corrections to its Facts, newest first."
  @spec list_source_corrections(integer()) :: [SourceCorrection.t()]
  defdelegate list_source_corrections(source_id), to: SourceCorrections, as: :list

  @doc "How many gall Facts Source `source_id` states."
  @spec source_fact_count(integer()) :: non_neg_integer()
  defdelegate source_fact_count(source_id), to: SourceCorrections, as: :gall_fact_count

  @doc """
  The Galls Source `source_id` states Facts about matching `query` (as the
  site's Gall search), at most `limit`: `%{id, name}`.
  """
  @spec search_source_galls(integer(), String.t(), pos_integer()) :: [map()]
  defdelegate search_source_galls(source_id, query, limit),
    to: SourceCorrections,
    as: :search_galls

  # The batch and statement ref that wrote each of `fact_ids`.
  defp statement_refs(fact_ids) do
    from(s in BatchStatement,
      where: s.kind in [:fact, :act] and s.fact_id in ^fact_ids,
      select: {s.fact_id, {s.batch_id, s.ref}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Where taxon `taxon_id` stands in the taxonomic Facts, and on whose word
  (matter `f923` Task 10; `Gallformers.Import.FactsView.position/1`): its
  current placement and name, each with the Source whose statement decides
  it, and the papers that disagree (awaiting a curator, or declined with
  the reason), newest first. For a taxon's page.
  """
  @spec taxonomic_position(integer()) :: %{
          placement: map() | nil,
          name: map() | nil,
          disagreeing: [map()]
        }
  def taxonomic_position(taxon_id) when is_integer(taxon_id), do: FactsView.position(taxon_id)

  @doc """
  The splits in effect that taxon `taxon_id` is part of, newest first: the
  taxon divided, its daughters and the Source deciding each
  (`Gallformers.Import.FactsView.splits/1`). With
  `Gallformers.Taxa.merged_into/1` (lumps), a taxon's split and lump history.
  """
  @spec taxon_splits(integer()) :: [map()]
  def taxon_splits(taxon_id) when is_integer(taxon_id), do: FactsView.splits(taxon_id)

  @doc """
  The gall Facts about Gall `gall_id` (`Gallformers.Catalog.facts_about_galls/1`),
  grouped by category as `facts_for_source/1` groups a Source's, all under
  the one Gall: each entry with the Fact's `standing` and its `sources`
  (`Gallformers.Import.FactsView.gall_entries/1`). Facts never shown
  (`:unsupported`) are left out. One header, its `facts` empty when the
  Gall has none.
  """
  @spec facts_for_gall(integer()) :: [map()]
  def facts_for_gall(gall_id) when is_integer(gall_id) do
    entries =
      [gall_id]
      |> Catalog.facts_about_galls()
      |> Enum.map(& &1.fact_id)
      |> FactsView.gall_entries()
      |> Enum.reject(&(&1.standing == :unsupported))
      |> Enum.map(&(&1 |> Map.put(:gall, gall_id) |> Map.drop([:slot])))

    name = get_in(FactsView.gall_names([gall_id]), [gall_id, :name])

    header = %{
      key: gall_id,
      ref: nil,
      gall_id: gall_id,
      new: false,
      name_as_written: nil,
      name: name,
      status: :resolved,
      question: nil,
      why: nil
    }

    FactsView.group([header], entries)
  end

  # -- denial ------------------------------------------------------------------

  @doc """
  Denies a package: it and its batches become `:denied` with `reason` (the
  same for each), and its open queue items are dropped (decided ones are
  kept), so nothing of it is applied. The replay log records it by the
  package's key.

  Refused (`{:error, :not_deniable}`) for a package approved or denied
  already, or with a batch applied (deny its other batches one by one,
  `deny_batch/3`). `{:error, changeset}` (errors on `:denied_reason`) when
  `reason` is blank.
  """
  @spec deny_package(Actor.t(), Package.t(), String.t() | nil) ::
          {:ok, Package.t()} | {:error, :not_deniable | Changeset.t()}
  def deny_package(%Actor{} = actor, %Package{} = package, reason) do
    Audit.transaction(actor, "import.deny_package", fn ->
      package = lock_package(package.id)
      batches = list_batches(package)

      if package.status not in @deniable or Enum.any?(batches, &(&1.status == :applied)),
        do: Repo.rollback(:not_deniable)

      package = deny_whole_package(package, batches, reason)

      ReplayLog.append!(:package_denied, %{"package" => package.key}, %{
        "reason" => package.denied_reason
      })

      package
    end)
  end

  @doc """
  Denies one batch of a package: it becomes `:denied` with `reason` and its
  open queue items are dropped (decided ones are kept). Resolving and
  applying the package leave it out; the package waits on for its other
  batches, and is denied too when none is left that is not denied. The
  replay log records it by the package's key and the producer's
  `batch_id`.

  Refused (`{:error, :not_deniable}`) for a batch applied or denied already,
  or of a package approved or denied. `{:error, changeset}` (errors on
  `:denied_reason`) when `reason` is blank.
  """
  @spec deny_batch(Actor.t(), Batch.t(), String.t() | nil) ::
          {:ok, Batch.t()} | {:error, :not_deniable | Changeset.t()}
  def deny_batch(%Actor{} = actor, %Batch{} = batch, reason) do
    Audit.transaction(actor, "import.deny_batch", fn ->
      package = lock_package(batch.package_id)
      batch = Repo.one!(from(b in Batch, where: b.id == ^batch.id, lock: "FOR UPDATE"))

      if package.status not in @deniable or batch.status in [:applied, :denied],
        do: Repo.rollback(:not_deniable)

      batch = batch |> Batch.deny_changeset(reason) |> Repo.update() |> unwrap_or_rollback()
      Repo.delete_all(from(q in QueueItem, where: q.batch_id == ^batch.id and q.status == :open))

      ReplayLog.append!(
        :batch_denied,
        %{"package" => package.key, "batch_id" => batch.producer_batch_id},
        %{"reason" => batch.denied_reason}
      )

      batches = list_batches(package)

      if Enum.all?(batches, &(&1.status == :denied)),
        do: deny_whole_package(package, batches, batch.denied_reason)

      batch
    end)
  end

  # Inside the caller's transaction, the package row locked: the package
  # and its batches not yet denied become denied, and its open items go.
  defp deny_whole_package(package, batches, reason) do
    package = package |> Package.deny_changeset(reason) |> Repo.update() |> unwrap_or_rollback()

    for batch <- batches, batch.status != :denied do
      batch
      |> Batch.deny_changeset(package.denied_reason)
      |> Repo.update()
      |> unwrap_or_rollback()
    end

    Repo.delete_all(
      from(q in QueueItem, where: q.package_id == ^package.id and q.status == :open)
    )

    package
  end

  @doc """
  Enqueues the import worker for `package`, acting as `actor`: one waiting
  job per package (a newer enqueue replaces the waiting job's actor).
  """
  @spec enqueue_package(Actor.t(), Package.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_package(%Actor{} = actor, %Package{id: id}) do
    %{"package_id" => id, "actor" => Actor.to_meta(actor)}
    |> Worker.new(replace: [available: [:args], scheduled: [:args], retryable: [:args]])
    |> Oban.insert()
  end

  @doc """
  Takes a package one step on (`Gallformers.Import.Worker`): a received
  package is validated (with the readiness gate unless every batch is
  Gallformers' own) and, if valid, resolved; a validated one is resolved;
  an approved one is applied. Other packages are left as they are.
  """
  @spec advance_package(Actor.t(), integer()) :: {:ok, Package.t()} | {:error, term()}
  def advance_package(%Actor{} = actor, package_id) do
    package = get_package!(package_id)

    case package.status do
      :received ->
        with {:ok, files} <- read_package_files(package),
             {:ok, package} <- validate_package(actor, package, review: review_required?(files)) do
          if package.status == :validated,
            do: resolve_package(actor, package),
            else: {:ok, package}
        end

      status when status in [:validated, :resolving] ->
        resolve_package(actor, package)

      :approved ->
        apply_package(actor, package)

      _other ->
        {:ok, package}
    end
  end

  @doc """
  Whether a package's files need the readiness gate (`review.json`): every
  package but one whose batches are all Gallformers' own statements.
  """
  @spec review_required?(Validator.package()) :: boolean()
  def review_required?(files) do
    sources =
      for name <- Validator.batch_files(),
          bytes = files[name],
          is_binary(bytes),
          {:ok, %{} = batch} <- [Jason.decode(bytes)],
          do: batch["source"]

    sources == [] or not Enum.all?(sources, &match?(%{"gallformers" => true}, &1))
  end

  # -- Gallformers' own statements ---------------------------------------------

  @doc """
  Takes in Gallformers' own statements written in a form (a curator's range
  exclusion, the curation tray's Fact items;
  `priv/import/GALLFORMERS_STATEMENTS.md`, built by
  `Gallformers.Import.GallformersFragment`) as a package of
  their own: `batches` maps a batch file name (`"gall.json"`,
  `"taxonomy.json"`) to the decoded batch, its source `{"gallformers":
  true}`. Each batch is given a fresh producer `batch_id` (any it has is
  replaced) and written to the private bucket under a fresh key; the
  package is registered as `actor` (the submitter), validated (no review,
  `review_required?/1`) and resolved, then approved when nothing needs a
  decision, and the import worker applies it.

  Returns the package: `:approved` (applied by the worker; inline in
  tests), `:awaiting_review` when a queue item or an unresolved Host name
  needs an admin first, or `:invalid` with its problems.
  `{:error, :not_gallformers}` when `batches` is empty, names another file
  or has a batch that is not Gallformers' own.
  """
  @spec submit_gallformers_fragment(Actor.t(), %{String.t() => map()}) ::
          {:ok, Package.t()} | {:error, :not_gallformers | term()}
  def submit_gallformers_fragment(%Actor{} = actor, batches) when is_map(batches) do
    key = "gallformers-" <> Ecto.UUID.generate()
    attrs = if actor.type == :user, do: %{submitter_user_id: actor.id}, else: %{}

    with :ok <- gallformers_batches(batches),
         :ok <- put_fragment(key, batches),
         {:ok, package} <- register_package(actor, key, attrs),
         {:ok, package} <- advance_package(actor, package.id) do
      approve_if_clear(actor, package)
    end
  end

  defp gallformers_batches(batches) do
    gallformers? = fn {name, batch} ->
      name in Validator.batch_files() and is_map(batch) and
        match?(%{"gallformers" => true}, batch["source"])
    end

    if map_size(batches) > 0 and Enum.all?(batches, gallformers?),
      do: :ok,
      else: {:error, :not_gallformers}
  end

  defp put_fragment(key, batches) do
    Enum.reduce_while(batches, :ok, fn {name, batch}, :ok ->
      bytes = batch |> Map.put("batch_id", Ecto.UUID.generate()) |> Jason.encode!()

      case Private.put(Package.prefix(key) <> name, bytes) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {name, reason}}}
      end
    end)
  end

  defp approve_if_clear(actor, %Package{status: :awaiting_review} = package) do
    case approve_package(actor, package) do
      {:ok, package} -> {:ok, package}
      {:error, {held, _found}} when held in [:open_items, :blocked] -> {:ok, package}
      {:error, reason} -> {:error, reason}
    end
  end

  defp approve_if_clear(_actor, package), do: {:ok, package}

  # -- applying ----------------------------------------------------------------

  @doc """
  Applies an approved package's batches that are not applied yet, in order:
  the taxonomy batch first; before each batch the package is resolved
  again, so the gall batch resolves against the taxonomy batch's new taxa.
  Each batch is applied in one transaction (`Gallformers.Import.ApplyTaxonomy`,
  `Gallformers.Import.ApplyGall`), and a batch already applied is left as
  it is, so applying again changes nothing.

  A batch that the fresh resolution holds (a blocked Host, a new open item
  it needs) is not applied: the package goes back to `:awaiting_review` for
  the admin to decide and approve again.

  `{:error, :not_approved}` for a package that is not approved; an error
  from a batch rolls that batch back and is returned.
  """
  @spec apply_package(Actor.t(), Package.t()) :: {:ok, Package.t()} | {:error, term()}
  def apply_package(%Actor{} = actor, %Package{} = package) do
    package = get_package!(package.id)

    cond do
      package.status != :approved ->
        {:error, :not_approved}

      pending_batches(package) == [] ->
        {:ok, package}

      true ->
        with {:ok, files} <- read_package_files(package) do
          apply_pending(actor, package, files)
        end
    end
  end

  defp apply_pending(actor, package, files) do
    result =
      package
      |> pending_batches()
      |> Enum.reduce_while(:ok, fn batch, :ok ->
        case resolve_and_apply(actor, package, batch, files) do
          {:ok, _} -> {:cont, :ok}
          other -> {:halt, other}
        end
      end)

    case result do
      :ok ->
        {:ok, get_package!(package.id)}

      {:held, _batch} ->
        Audit.transaction(actor, "import.hold_package", fn ->
          package.id
          |> lock_package()
          |> Package.status_changeset(:awaiting_review)
          |> Repo.update()
          |> unwrap_or_rollback()
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Resolves the package again, then applies `batch` if nothing holds it:
  # {:ok, batch}, {:held, batch} or {:error, reason}.
  defp resolve_and_apply(actor, package, batch, files) do
    {:ok, _package} =
      Audit.transaction(actor, "import.resolve_package", fn ->
        package.id |> lock_package() |> resolve(files)
      end)

    package = get_package!(package.id)
    batch = get_batch!(batch.id)

    cond do
      batch.status == :applied -> {:ok, batch}
      batch.status != :ready -> {:held, batch}
      open_blocking_items(package, batch) != [] -> {:held, batch}
      true -> apply_batch(actor, package, batch, files)
    end
  end

  defp apply_batch(actor, package, batch, files) do
    Audit.transaction(actor, "import.apply_batch", fn ->
      batch = Repo.one!(from(b in Batch, where: b.id == ^batch.id, lock: "FOR UPDATE"))

      if batch.status == :applied,
        do: batch,
        else: apply_locked_batch(actor, lock_package(package.id), batch, files)
    end)
  end

  # Inside the batch's transaction, the batch row locked.
  defp apply_locked_batch(actor, package, batch, files) do
    ctx = apply_context(actor, package, batch, files)
    result = ctx |> runner(batch).run() |> unwrap_or_rollback()

    record_applied(package, batch, result)

    ReplayLog.append!(
      :batch_applied,
      %{"batch_id" => batch.producer_batch_id, "package" => package.key},
      %{"file" => batch.file}
    )

    batch |> Batch.status_changeset(:applied) |> Repo.update() |> unwrap_or_rollback()
  end

  defp runner(%Batch{batch_type: :taxonomy}), do: ApplyTaxonomy
  defp runner(%Batch{batch_type: :gall}), do: ApplyGall

  # What applying `batch` takes (`Gallformers.Import.ApplyTaxonomy`), inside
  # its transaction: its statements, decisions honoured, and the curator's
  # edits on its Facts (`Gallformers.Import.FactEdits`, which win).
  # `defaults` are package decisions to take where none is made (the
  # preview's).
  defp apply_context(actor, package, batch, files, defaults \\ %{}) do
    statements = list_statements(batch)
    decided = Queue.decided(batch.id)
    trait_disputes = open_trait_disputes(package, batch)
    edits = batch.id |> FactEdits.for_batch() |> FactEdits.overlay()

    actor
    |> batch_context(package, batch, files, defaults)
    |> Map.merge(%{
      taxa: for(%{kind: :taxon} = s <- statements, into: %{}, do: {s.ref, s}),
      galls: for(%{kind: :gall} = s <- statements, into: %{}, do: {s.ref, s}),
      drop:
        waiting_on(trait_disputes) |> Map.merge(Queue.drops(decided)) |> Map.merge(edits.drop),
      hosts:
        GallDecisions.chosen_hosts(decided, batch.content || %{})
        |> Map.merge(Disputes.chosen_hosts(decided))
        |> Map.merge(edits.hosts),
      trait_values: edits.trait_values,
      trait_disputes: trait_disputes,
      set_aside: Enum.filter(decided, &SetAside.set_aside?/1),
      review: decode(files["review.json"]),
      term_items:
        package
        |> list_queue_items(kind: :trait_term, status: :all)
        |> Enum.filter(&(&1.batch_id == batch.id))
    })
  end

  # The batch's open Trait disputes (`Gallformers.Import.Disputes`).
  defp open_trait_disputes(package, batch) do
    for q <- list_queue_items(package, kind: :dispute),
        q.batch_id == batch.id,
        Disputes.trait?(q),
        do: q
  end

  # The Trait Facts whose disputes are open: they wait, unwritten, until
  # decided, stored as waiting terms; ref to why.
  defp waiting_on(trait_disputes) do
    for q <- trait_disputes,
        ref <- Disputes.refs(q),
        into: %{},
        do: {ref, "waiting on its dispute (#{q.statement_ref})"}
  end

  # What writing a batch's Facts needs, inside its transaction (the package
  # locked): its Source (matched, decided or created, with its document
  # stored; the package records it), the document's items by ref, and the
  # note a Gallformers statement quotes.
  defp batch_context(actor, package, batch, files, defaults \\ %{}) do
    decisions = Map.merge(defaults, package_decisions(package))

    {:ok, source, items} =
      actor
      |> SourceStep.ensure(package, batch.content["source"], files, decisions)
      |> ok_or_rollback()

    if package.source_id == nil do
      package |> Changeset.change(source_id: source.id) |> Repo.update() |> unwrap_or_rollback()
    end

    %{
      actor: actor,
      source: source,
      batch: batch,
      items: items,
      note: SourceStep.note(batch.content["source"], files)
    }
  end

  defp ok_or_rollback({:ok, _source, _items} = ok), do: ok
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp package_decisions(package) do
    from(q in QueueItem,
      where: q.package_id == ^package.id and is_nil(q.batch_id) and q.status == :decided,
      select: {q.statement_ref, q.decision}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp record_applied(package, batch, result) do
    rows = for row <- result.statements, do: Map.put(row, :batch_id, batch.id)
    Repo.insert_all(BatchStatement, rows)

    for %{id: id} = update <- result.updates do
      from(s in BatchStatement, where: s.id == ^id)
      |> Repo.update_all(set: update |> Map.delete(:id) |> Map.to_list())
    end

    insert_queue_items(result.queue, package, batch.id)
  end

  # -- replay ------------------------------------------------------------------

  @doc "The replay log's entries, in order (`Gallformers.Import.Replay`)."
  @spec list_replay_entries() :: [ReplayEntry.t()]
  def list_replay_entries, do: ReplayLog.list()

  @doc """
  Exports the whole replay log to a file in the private bucket
  (`Gallformers.Import.ReplayExport`), for replay on production after the
  cutover data migration. Returns the file's key and the entry count.
  """
  @spec export_replay_log() ::
          {:ok, %{key: String.t(), count: non_neg_integer()}} | {:error, term()}
  def export_replay_log, do: ReplayExport.export()

  @doc "The entries of an exported replay log, in order."
  @spec read_replay_export(String.t()) :: {:ok, [ReplayExport.entry()]} | {:error, term()}
  def read_replay_export(key), do: ReplayExport.read(key)

  @doc """
  Replays an exported replay log (`Gallformers.Import.Replay.run/2`) as
  `actor`: how many entries were replayed, or the first that could not be.
  """
  @spec replay_exported(Actor.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def replay_exported(%Actor{} = actor, key) do
    with {:ok, entries} <- ReplayExport.read(key) do
      Replay.run(entries, actor: actor)
    end
  end

  @doc """
  At cutover, after the replay: carries phase 1's taxonomy decisions over
  as `actor` (`Gallformers.Import.TaxonomyCarryOver`, matter `f923` Task
  9): each "change the tree" decision on a synonym question, in replay-log
  `entries` or among the decided queue items, and each act a curator
  followed, becomes the acceptance of the Source's statements the tree
  holds. Returns the report; what couldn't be carried is in its
  `unmatched`, for a curator. Running it again accepts nothing new.
  """
  @spec carry_over_taxonomy_decisions(Actor.t(), [ReplayEntry.t() | map()]) ::
          {:ok, TaxonomyCarryOver.report()}
  defdelegate carry_over_taxonomy_decisions(actor, entries), to: TaxonomyCarryOver, as: :run

  @doc """
  `carry_over_taxonomy_decisions/2` with the entries of the exported
  replay log `key` (the one `replay_exported/2` replayed).
  """
  @spec carry_over_exported(Actor.t(), String.t()) ::
          {:ok, TaxonomyCarryOver.report()} | {:error, term()}
  def carry_over_exported(%Actor{} = actor, key) do
    with {:ok, entries} <- ReplayExport.read(key) do
      TaxonomyCarryOver.run(actor, entries)
    end
  end

  @doc "A carry-over report (`carry_over_taxonomy_decisions/2`) as text."
  @spec format_carry_over(TaxonomyCarryOver.report()) :: String.t()
  defdelegate format_carry_over(report), to: TaxonomyCarryOver, as: :format

  @doc false
  # Replay (`Gallformers.Import.Replay`): applies the batch with producer
  # `batch_id` of `package` as it was approved, resolving the package again
  # first. A package whose batches are all applied becomes `:approved`.
  @spec apply_batch_for_replay(Actor.t(), Package.t(), String.t()) ::
          {:ok, Batch.t()} | {:error, term()}
  def apply_batch_for_replay(%Actor{} = actor, %Package{} = package, producer_batch_id) do
    with %Batch{} = batch <-
           Enum.find(list_batches(package), &(&1.producer_batch_id == producer_batch_id)) ||
             {:error, {:no_batch, producer_batch_id}},
         {:ok, files} <- read_package_files(package),
         {:ok, batch} <- resolve_and_apply(actor, package, batch, files) |> held_as_error() do
      if pending_batches(package) == [] do
        Audit.transaction(actor, "import.approve_package", fn ->
          package.id
          |> lock_package()
          |> Package.status_changeset(:approved)
          |> Repo.update()
          |> unwrap_or_rollback()
        end)
      end

      {:ok, batch}
    end
  end

  defp held_as_error({:held, batch}),
    do:
      {:error,
       {:held, batch.producer_batch_id,
        open_blocking_items(get_package!(batch.package_id), batch)}}

  defp held_as_error(other), do: other

  # -- the Host-name step and taxonomy admin -----------------------------------

  @doc """
  The Host-name step (`d585`): adds `name` as a synonym of `taxon` (as
  `Gallformers.Taxa.add_synonym/4`, `opts` `:sensu` and `:authorship`) and
  records it in the replay log, in one transaction. Resolve the package
  again afterwards.
  """
  @spec record_synonym_added(Actor.t(), Taxa.taxon_ref(), String.t(), keyword()) ::
          {:ok, Taxa.TaxonName.t()} | {:error, Changeset.t()}
  def record_synonym_added(%Actor{} = actor, taxon, name, opts \\ []) do
    Audit.transaction(actor, "import.record_synonym_added", fn ->
      taxon_id = taxon_id(taxon)
      synonym = actor |> Taxa.add_synonym(taxon_id, name, opts) |> unwrap_or_rollback()

      ReplayLog.append!(
        :synonym_added,
        %{"taxon" => StableRef.taxon(taxon_id), "name" => name},
        %{"sensu" => opts[:sensu], "authorship" => opts[:authorship]}
      )

      synonym
    end)
  end

  @doc """
  The Host-name step (`d585`): adds a plant (`attrs`: `:name`, `:rank`,
  `:parent_id`, optional `:authorship`; origin `:powo`, kingdom Plantae)
  and records it in the replay log, in one transaction.
  """
  @spec record_plant_added(Actor.t(), map()) :: {:ok, Taxa.Taxon.t()} | {:error, Changeset.t()}
  def record_plant_added(%Actor{} = actor, attrs) when is_map(attrs) do
    Audit.transaction(actor, "import.record_plant_added", fn ->
      plant =
        actor
        |> Taxa.create_taxon(
          attrs
          |> Map.take([:name, :rank, :parent_id, :authorship])
          |> Map.merge(%{origin: :powo, kingdom: "Plantae"})
        )
        |> unwrap_or_rollback()

      ReplayLog.append!(
        :plant_added,
        %{"name" => attrs[:name], "rank" => to_string(attrs[:rank])},
        %{
          "parent" => attrs[:parent_id] && StableRef.taxon(attrs[:parent_id]),
          "authorship" => attrs[:authorship]
        }
      )

      plant
    end)
  end

  @typedoc "A taxonomy admin's edit to the editorial tree."
  @type taxonomy_edit ::
          {:place, Taxa.taxon_ref(), Taxa.taxon_ref() | nil}
          | {:rename, Taxa.taxon_ref(), String.t()}
          | {:add_common_name, Taxa.taxon_ref(), String.t()}
          | {:create_taxon, map()}
          | TaxonomyEdits.edit()

  @doc """
  A taxonomy admin's editorial edit (phase 1: curator edits, no Facts) —
  applying a taxonomy disagreement, say — made through `Gallformers.Taxa`
  and recorded in the replay log, in one transaction:

    * `{:place, taxon, parent}` — `Gallformers.Taxa.place/3`
    * `{:rename, taxon, new_name}` — `Gallformers.Taxa.rename/3`
    * `{:add_common_name, taxon, name}` — `Gallformers.Taxa.add_common_name/3`
    * `{:create_taxon, attrs}` — `Gallformers.Taxa.create_taxon/2`
      (`:name`, `:rank`, `:parent_id`, `:kingdom`, `:origin`)
    * `{:update_editorial, taxon, attrs}` — `Gallformers.Taxa.update_editorial/3`
    * `{:set_authorship, taxon, authorship}` — `Gallformers.Taxa.set_authorship/3`
    * `{:remove_synonym, name}` — `Gallformers.Taxa.remove_synonym/2`
    * `{:remove_common_name, name}` — `Gallformers.Taxa.remove_common_name/2`
    * `{:delete_taxon, taxon}` — `Gallformers.Taxa.delete_taxon/2`
    * `{:set_host_range, taxon, entries}` — `Gallformers.Ranges.update_taxon_places/3`
    * `{:set_wcvp, taxon, attrs}` — `Gallformers.Ranges.Wcvp.put_link/3`

  The last seven are `Gallformers.Import.TaxonomyEdits`'s, which says how
  each is logged.
  """
  @spec record_taxonomy_edit(Actor.t(), taxonomy_edit()) :: {:ok, term()} | {:error, term()}
  def record_taxonomy_edit(%Actor{} = actor, edit) do
    Audit.transaction(actor, "import.record_taxonomy_edit", fn ->
      {key, payload} = edit_entry(edit)
      result = actor |> run_edit(edit) |> unwrap_or_rollback()
      ReplayLog.append!(:taxonomy_edit, key, payload)
      result
    end)
  end

  # The stable key and payload, taken before the edit changes any name.
  defp edit_entry({:place, taxon, parent}) do
    {%{"op" => "place", "taxon" => StableRef.taxon(taxon_id(taxon))},
     %{"parent" => parent && StableRef.taxon(taxon_id(parent))}}
  end

  defp edit_entry({:rename, taxon, new_name}),
    do: {%{"op" => "rename", "taxon" => StableRef.taxon(taxon_id(taxon))}, %{"name" => new_name}}

  defp edit_entry({:add_common_name, taxon, name}) do
    {%{"op" => "add_common_name", "taxon" => StableRef.taxon(taxon_id(taxon))}, %{"name" => name}}
  end

  defp edit_entry({:create_taxon, attrs}) do
    {%{"op" => "create_taxon", "name" => attrs[:name], "rank" => to_string(attrs[:rank])},
     %{
       "parent" => attrs[:parent_id] && StableRef.taxon(attrs[:parent_id]),
       "kingdom" => attrs[:kingdom],
       "origin" => to_string(attrs[:origin] || :curated)
     }}
  end

  defp edit_entry(edit), do: TaxonomyEdits.entry(edit)

  defp run_edit(actor, {:place, taxon, parent}), do: Taxa.place(actor, taxon, parent)
  defp run_edit(actor, {:rename, taxon, name}), do: Taxa.rename(actor, taxon, name)

  defp run_edit(actor, {:add_common_name, taxon, name}),
    do: Taxa.add_common_name(actor, taxon, name)

  defp run_edit(actor, {:create_taxon, attrs}),
    do: Taxa.create_taxon(actor, Map.put_new(attrs, :origin, :curated))

  defp run_edit(actor, edit), do: TaxonomyEdits.run(actor, edit)

  @doc """
  A taxonomy admin's change to a non-plant taxon, credited to the Source it
  follows (matter `f923` Task 8; `Gallformers.Import.TaxonomyStatements`):
  recorded as `basis`'s taxonomic statement, accepted at once by `actor`,
  so the tree follows it where it wins. `basis` is `{:source, source_id}`,
  `{:citation, attrs}` (a Source made on the spot: title, authors, date,
  optional DOI) or `{:gallformers, reason}` (no Source: Gallformers' own
  position, with its reason). `change`: `{:place, taxon, parent}`,
  `{:name, taxon, %{name, rank, authorship}}`, `{:add_synonym, taxon,
  name}`, `{:remove_synonym, synonym}`, `{:add_common_name, taxon, name}`,
  `{:remove_common_name, common}`, `{:create_taxon, attrs, child_ids}`,
  `{:move_all, taxon_ids, parent}`.

  `{:error, {:outranked, message}}` when an accepted newer statement
  already decides it (nothing changes); `{:error, :plant}` for a plant,
  whose edits stay editorial (`record_taxonomy_edit/2`).
  """
  @spec record_taxonomy_change(
          Actor.t(),
          TaxonomyStatements.basis(),
          TaxonomyStatements.change()
        ) :: {:ok, term()} | {:error, term()}
  defdelegate record_taxonomy_change(actor, basis, change), to: TaxonomyStatements, as: :record

  @doc """
  Creates a Source from a citation entered on the spot (`title`,
  `authors`, `authored`, optional `doi`), audited and logged for replay
  (`Gallformers.Import.SourceEdits.record_create/2`).
  """
  @spec record_source_created(Actor.t(), map()) ::
          {:ok, Gallformers.Sources.Source.t()} | {:error, Changeset.t()}
  defdelegate record_source_created(actor, attrs), to: SourceEdits, as: :record_create

  @doc """
  A WCVP action of the taxonomy admin or the bulk range review, made
  through `Gallformers.Ranges.Wcvp` and recorded in the replay log as the
  state it left, in one transaction (`Gallformers.Import.TaxonomyEdits`):
  `{:match, taxon}`, `{:sync, taxon}` (or `{:sync, taxon, ref_data}`),
  `{:ignore, taxon_ids}`, `{:clear_match_status, taxon_ids}`,
  `{:confirm_ranges, taxon_ids}`. A match or sync that finds nothing keeps
  the `no_match` status it set and returns `{:error, message}`.
  """
  @spec record_wcvp_edit(Actor.t(), TaxonomyEdits.wcvp_edit()) ::
          {:ok, term()} | {:error, term()}
  defdelegate record_wcvp_edit(actor, edit), to: TaxonomyEdits, as: :record_wcvp

  # The taxonomy admin's writes of several edits as one
  # (`Gallformers.Import.TaxonomyAdmin`): all of their edits or none, each
  # in the replay log.

  @doc """
  Saves a plant's Host range and, when `link_attrs` is not empty, its WCVP
  link's fields (`Gallformers.Import.TaxonomyAdmin.save_host_range/4`).
  """
  @spec record_host_range_saved(Actor.t(), integer(), [TaxonomyAdmin.range_entry()], map()) ::
          {:ok, :ok} | {:error, term()}
  defdelegate record_host_range_saved(actor, taxon_id, entries, link_attrs),
    to: TaxonomyAdmin,
    as: :save_host_range

  @doc """
  Creates a taxon, moves `child_ids` under it and gives a plant its Host
  range (`Gallformers.Import.TaxonomyAdmin.create_taxon/4`).
  """
  @spec record_taxon_created(Actor.t(), map(), [integer()], [TaxonomyAdmin.range_entry()]) ::
          {:ok, Taxa.Taxon.t()} | {:error, term()}
  defdelegate record_taxon_created(actor, attrs, child_ids, entries),
    to: TaxonomyAdmin,
    as: :create_taxon

  @doc """
  Adds a plant from its WCVP record under its WCVP genus and family, with
  its range and WCVP link (`Gallformers.Import.TaxonomyAdmin.add_plant_from_wcvp/4`).
  """
  @spec record_plant_added_from_wcvp(
          Actor.t(),
          map(),
          Taxa.Rank.t(),
          [TaxonomyAdmin.range_entry()]
        ) :: {:ok, Taxa.Taxon.t()} | {:error, term()}
  defdelegate record_plant_added_from_wcvp(actor, wcvp, rank, entries),
    to: TaxonomyAdmin,
    as: :add_plant_from_wcvp

  @doc """
  The rank a plant's name is at, read from its infraspecific marker
  (`%{taxon_name: name}`; `Gallformers.Import.TaxonomyAdmin.wcvp_rank/1`).
  """
  @spec wcvp_rank(map()) :: Taxa.Rank.t()
  defdelegate wcvp_rank(record), to: TaxonomyAdmin

  @doc "Moves each of `taxon_ids` under `parent_id` (`Gallformers.Import.TaxonomyAdmin.move_all/3`)."
  @spec record_taxa_moved(Actor.t(), [integer()], integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defdelegate record_taxa_moved(actor, taxon_ids, parent_id), to: TaxonomyAdmin, as: :move_all

  defp taxon_id(%Taxa.Taxon{id: id}), do: id
  defp taxon_id(id) when is_integer(id), do: id

  # -- curators' notes (matter `ec2c`) --------------------------------------------

  @doc """
  Notes the Fact about Gall `gall_id` that `key` names (a Gall page key,
  `Gallformers.Catalog.find_gall_fact/2`) and records it in the replay log,
  in one transaction (`Gallformers.Import.CurationNotes`). `opts`:
  `:author_name`, when replaying. `{:error, :no_fact}` when there is no such
  Fact.
  """
  @spec record_fact_note(
          Actor.t(),
          integer(),
          Catalog.gall_fact_key(),
          String.t(),
          keyword()
        ) :: {:ok, Gallformers.Catalog.FactNote.t()} | {:error, term()}
  defdelegate record_fact_note(actor, gall_id, key, text, opts \\ []), to: CurationNotes

  @doc """
  Records a "based on" note on taxon `taxon_id`'s edit of `about`
  (`"name"`, `"synonyms"`, `"range"`; `Gallformers.Taxa.add_taxon_note/5`)
  and logs it, in one transaction (`Gallformers.Import.CurationNotes`).
  """
  @spec record_taxon_note(Actor.t(), integer(), String.t(), String.t(), keyword()) ::
          {:ok, Taxa.TaxonNote.t()} | {:error, term()}
  defdelegate record_taxon_note(actor, taxon_id, about, text, opts \\ []), to: CurationNotes

  # -- deletes and merges (matter `ec2c`, "Deletes") ------------------------------

  @doc """
  What deleting a Gall or taxon would do and what blocks it
  (`Gallformers.Import.Deletion`), for the screen that asks to be sure:

      %{
        subject: %{type: :gall | :taxon, id, name},  # a taxon's also :rank, :kingdom
        operation: :delete | :cascade | :collapse | :blocked,
        deletable: boolean,
        galls: [%{id, name}],                        # the Galls deleted
        taxa: [%{id, name, rank}],                   # the taxa deleted, the subject first
        children: [%{id, name, rank}],               # a taxon's direct children
        parent: %{id, name, rank} | nil,             # where a collapse re-places them
        facts: [%{fact_id, kind, about, rests_on, text, sources: [%{id, title, name}]}],
        sources: [%{id, title, name, own, facts}],   # the Facts' Sources, with counts
        images: [%{id, path, owner}],
        notes: [%{gall_id, versions}],               # Gallformers note versions
        legacy_citations: [%{gall_id, source}],
        cleanup: [%{kind, count, text}],             # import rows cleaned up with it
        blockers: [%{kind, record, record_name, source, count, text, action}]
      }

  `about`, `rests_on`, `owner` and `record` are `{:gall, id}` or `{:taxon,
  id}`. `{:error, :not_found}` when there is no such record.
  """
  @spec deletion_impact(Deletion.subject()) :: {:ok, Deletion.impact()} | {:error, :not_found}
  defdelegate deletion_impact(subject), to: Deletion, as: :impact

  @doc """
  Deletes a Gall or taxon (`Gallformers.Import.Deletion`): rechecked under
  the tree lock, audited, logged for replay (`:deletion`), the images'
  stored files removed after the commit and `{:records_deleted, %{galls,
  taxa, by}}` broadcast on `records_topic/0`. Returns the impact as carried
  out and the files that could not be removed.

  `{:error, :not_found}` when it is gone (deleted by another user);
  `{:error, {:blocked, blockers}}` when something blocks it now.
  """
  @spec record_deletion(Actor.t(), Deletion.subject()) ::
          {:ok, %{impact: Deletion.impact(), storage_errors: [{String.t(), term()}]}}
          | {:error, :not_found | {:blocked, [Deletion.blocker()]} | term()}
  defdelegate record_deletion(actor, subject), to: Deletion, as: :record

  @doc """
  What merging Gall (`{:gall, absorbed_id, survivor_id}`) or plant
  (`{:plant, absorbed_id, survivor_id}`) would do, writing nothing
  (`Gallformers.Import.Merge`). A Gall merge:

      %{
        type: :gall,
        absorbed: %{id, name, code}, survivor: %{id, name, code},
        facts: [%{from, to, kind, text, outcome, with_gall,
                  sources: [%{id, title, name, outcome}]}],
        standings: [%{fact_id, text, from, to}],  # the survivor's Facts recency changed
        conflicts: [%{type, fact_ids, text}],     # same-date ties: curator questions
        queued: [queue_item_id],                  # record_merge/2 only
        alias: String.t() | nil,                  # the absorbed name, as an alias
        redirects: %{id, code},
        images: non_neg_integer(),                # moved over
        note: :appended | :moved | :kept | :none,
        repointed: [%{gall_id, text}],            # other Galls now pointing at the survivor
        cleanup: [%{kind, count, text}],
        blockers: [blocker]
      }

  A Fact's `outcome` is `:moved`, `:combined` (the survivor held it) or
  `:dropped` (it joined the two Galls); a Source's `:moved`,
  `:already_held` or `:dropped`. A plant merge has `type: :plant`,
  `absorbed`/`survivor` `%{id, name, rank}`, `synonyms` and `common_names`
  (moved over), `facts`, `standings`, `conflicts`, `queued`,
  `galls_requalified` (IDs), `images`, `range: %{dropped}`, `redirects:
  %{id}`, `cleanup`, `blockers`.

  Errors: `:not_found`, `:same_record`, `:not_a_plant` (a plant merge of
  anything but two plants at species rank or below). `actor` is whom the
  rolled-back transaction is audited as (by default a system actor).
  """
  @spec merge_preview(Merge.spec(), Actor.t()) :: {:ok, Merge.result()} | {:error, term()}
  defdelegate merge_preview(spec, actor \\ Actor.system("merge preview")), to: Merge, as: :preview

  @doc """
  Merges (`merge_preview/1` for the result): audited, logged for replay
  (`:merge`), `{:records_merged, %{type, absorbed_id, survivor_id, by}}`
  broadcast on `records_topic/0`. `{:error, {:blocked, blockers}}` when
  something blocks it; nothing changes then.
  """
  @spec record_merge(Actor.t(), Merge.spec()) :: {:ok, Merge.result()} | {:error, term()}
  defdelegate record_merge(actor, spec), to: Merge, as: :record

  # -- taxonomic statements (matter `f923`) -----------------------------------

  @doc """
  Accepts a Source's taxonomic statement (attribution `attribution_id`), so
  it counts and the tree follows it where it wins
  (`Gallformers.Facts.accept/3`), and logs it for replay
  (`Gallformers.Import.TaxonomicDecisions`).
  """
  @spec accept_taxonomic_statement(Actor.t(), integer()) ::
          {:ok, Gallformers.Facts.attribute_result()} | {:error, term()}
  def accept_taxonomic_statement(%Actor{} = actor, attribution_id),
    do: TaxonomicDecisions.decide(actor, :accept, attribution_id)

  @doc """
  Declines a Source's taxonomic statement with `reason` (required), so it
  never counts until reopened (`Gallformers.Facts.decline/4`); logged for
  replay.
  """
  @spec decline_taxonomic_statement(Actor.t(), integer(), String.t()) ::
          {:ok, Gallformers.Facts.attribute_result()} | {:error, term()}
  def decline_taxonomic_statement(%Actor{} = actor, attribution_id, reason),
    do: TaxonomicDecisions.decide(actor, :decline, attribution_id, reason)

  @doc """
  Reopens a Source's taxonomic statement, clearing its acceptance or
  decline (`Gallformers.Facts.reopen/2`); logged for replay.
  """
  @spec reopen_taxonomic_statement(Actor.t(), integer()) ::
          {:ok, Gallformers.Facts.attribute_result()} | {:error, term()}
  def reopen_taxonomic_statement(%Actor{} = actor, attribution_id),
    do: TaxonomicDecisions.decide(actor, :reopen, attribution_id)

  # -- the taxonomy queue (matter `f923` Task 6) ----------------------------------

  # A taxonomy question is decided as its statement: accepted or declined
  # through `TaxonomicDecisions` (which closes the question and logs the
  # decision for replay), never resolving its package again.
  defp decide_taxonomy_question(actor, item, decision),
    do: TaxonomyQueue.decide(actor, item, decision)

  @doc """
  The taxonomy questions (`Gallformers.Import.TaxonomyQueue`): Sources'
  taxonomic statements that differ from the tree, newer than what it
  follows, for a curator to accept or decline, across Sources; oldest
  first. Options: `:status` (default `:open`; `:all`), `:source_id`.
  """
  @spec list_taxonomy_questions(keyword()) :: [QueueItem.t()]
  def list_taxonomy_questions(opts \\ []), do: TaxonomyQueue.list(opts)

  @doc """
  How many questions the taxonomy queue shows open: the taxonomy questions
  and the split questions, every Source's or `source_id`'s.
  """
  @spec count_taxonomy_questions(integer() | nil) :: non_neg_integer()
  def count_taxonomy_questions(source_id \\ nil),
    do: TaxonomyQueue.count(source_id) + SplitQuestions.count(source_id)

  @doc """
  The split questions (`Gallformers.Import.SplitQuestions`): for each Gall
  on a taxon an accepted split divided, which taxon induces it now; oldest
  first. Options: `:status` (default `:open`; `:all`), `:source_id` (the
  splitting Source's).
  """
  @spec list_split_questions(keyword()) :: [QueueItem.t()]
  def list_split_questions(opts \\ []), do: SplitQuestions.list(opts)

  @doc """
  What accepting every open taxonomy question of Source `source_id` would
  do to the tree (`t:Gallformers.Import.TaxonomyQueue.preview/0`): the
  acceptances made in a transaction always rolled back.
  """
  @spec preview_accept_rest(integer(), Actor.t()) ::
          {:ok, TaxonomyQueue.preview()} | {:error, term()}
  def preview_accept_rest(source_id, %Actor{} = actor \\ Actor.system("taxonomy preview")),
    do: TaxonomyQueue.preview_rest(source_id, actor)

  @doc """
  Accepts every open taxonomy question of Source `source_id` ("Accept the
  rest of this paper"), all or none; its declined statements stay
  declined. Each acceptance is logged for replay.
  `{:error, {item_id, reason}}` when the tree refuses one.
  """
  @spec accept_rest(Actor.t(), integer()) ::
          {:ok, %{accepted: [QueueItem.t()]}} | {:error, term()}
  def accept_rest(%Actor{} = actor, source_id), do: TaxonomyQueue.accept_rest(actor, source_id)

  @doc """
  How the tree differs now from the statement a taxonomy question asks
  about, in words; nil when it agrees now.
  """
  @spec taxonomy_tree_now(QueueItem.t()) :: String.t() | nil
  defdelegate taxonomy_tree_now(item), to: TaxonomyQueue, as: :tree_now

  @doc "Why a taxonomic decision was refused (the tree's reason, most often), in words."
  @spec taxonomy_refusal(term()) :: String.t()
  defdelegate taxonomy_refusal(reason), to: TaxonomyQueue, as: :refusal_text

  @doc ~S|The PubSub topic deletes and merges are broadcast on: `"catalog:records"`.|
  @spec records_topic() :: String.t()
  defdelegate records_topic(), to: Deletion, as: :topic

  @doc "Subscribes the caller to `records_topic/0`."
  @spec subscribe_records() :: :ok | {:error, term()}
  def subscribe_records, do: Phoenix.PubSub.subscribe(Gallformers.PubSub, Deletion.topic())

  # -- the Source editor -------------------------------------------------------

  @doc """
  A Source editor's edit (matter a856, Task 10), made through
  `Gallformers.Sources` with its Facts' standings recomputed and recorded in
  the replay log, in one transaction (`Gallformers.Import.SourceEdits`):

    * `{:update_details, source, attrs}` — `Gallformers.Sources.update_source_details/3`
    * `{:retract, source, notice, date}` — `Gallformers.Sources.retract_source/4`
    * `{:unretract, source}` — `Gallformers.Sources.unretract_source/2`
  """
  @spec record_source_edit(Actor.t(), SourceEdits.edit()) ::
          {:ok, Gallformers.Sources.Source.t()} | {:error, Changeset.t() | term()}
  defdelegate record_source_edit(actor, edit), to: SourceEdits, as: :record

  @doc """
  Each of `source_ids`' two dates, by Source ID: `%{ingested, updated,
  legacy?}` — when its first package's batch was applied, when its data
  was last edited, and whether it is from the old data (with no Ingested
  date) (`Gallformers.Import.SourceDates`, matter `f14c`).
  """
  @spec source_dates([integer()]) :: %{integer() => Gallformers.Import.SourceDates.dates()}
  defdelegate source_dates(source_ids), to: Gallformers.Import.SourceDates, as: :for_sources

  # -- the Trait vocabulary ----------------------------------------------------

  @doc """
  Adds a Trait value (`Gallformers.Catalog.add_trait_value/2`: `:trait`,
  `:value`, `:definition`, all required) and records it in the replay log,
  in one transaction (`Gallformers.Import.VocabEdits`).
  """
  @spec record_trait_value_added(Actor.t(), map()) ::
          {:ok, Gallformers.Catalog.Vocab.TraitValue.t()} | {:error, Changeset.t()}
  defdelegate record_trait_value_added(actor, attrs), to: VocabEdits

  @doc """
  Changes a term (`d213`: place it, mark it ambiguous or unambiguous, mark
  it as fitting no category, move it, record a spot check — through
  `Gallformers.Catalog.place_term/6` and its siblings) and records the
  change in the replay log, in one transaction
  (`Gallformers.Import.VocabEdits.record_term_edit/3`).
  """
  @spec record_term_edit(Actor.t(), VocabEdits.term_edit(), keyword()) ::
          {:ok, Gallformers.Catalog.Vocab.TraitTermMapping.t()} | {:error, term()}
  defdelegate record_term_edit(actor, edit, opts \\ []), to: VocabEdits

  @doc """
  Places `term` for every Source under `categories` (one value, or a list:
  each value the term's words name, `d213`), as a superadmin does from the
  vocabulary page (recorded for replay as a `:trait_term_edit` placed by
  `:superadmin`, with the set): the open questions about the term, in
  every package, are decided as placing it, and its uses waiting or kept
  as text, in every Source, get their Facts, one per category
  (`settle_placed_term/4`).
  """
  @spec place_term(Actor.t(), String.t(), String.t(), VocabEdits.categories()) ::
          {:ok, Gallformers.Catalog.Vocab.TraitTermMapping.t()} | {:error, term()}
  def place_term(%Actor{} = actor, trait, term, categories)
      when is_binary(trait) and is_binary(term) and
             (is_binary(categories) or is_list(categories)) do
    Audit.transaction(actor, "import.place_term", fn ->
      placed =
        actor
        |> VocabEdits.record_term_edit({:place, trait, term, categories, :superadmin})
        |> unwrap_or_rollback()

      actor |> settle_placed_term(trait, term, categories) |> unwrap_or_rollback()
      placed
    end)
  end

  @doc """
  After a superadmin placed `term` under `categories` (`place_term/4`, and
  its replay): decides the open questions about the term as placing it,
  and settles its uses waiting or kept as text, in every Source, writing
  their Facts.
  """
  @spec settle_placed_term(Actor.t(), String.t(), String.t(), VocabEdits.categories()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def settle_placed_term(%Actor{} = actor, trait, term, categories) do
    Audit.transaction(actor, "import.settle_placed_term", fn ->
      decision = %{"place" => categories, "note" => "placed for every Source by a superadmin"}

      from(q in QueueItem,
        where:
          q.kind == :trait_term and q.status == :open and
            q.statement_ref == ^TraitTerms.statement_ref(trait, term),
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Enum.each(fn q ->
        q |> QueueItem.decide_changeset(decision, actor) |> Repo.update() |> unwrap_or_rollback()
      end)

      settled =
        actor
        |> Catalog.settle_pending_terms(trait, term, categories, text: true)
        |> unwrap_or_rollback()

      write_settled(settled, actor, nil, nil)
      length(settled)
    end)
  end

  # -- seeding the term table (`d213`, Task F) -------------------------------------

  @doc """
  Gathers the Trait terms of the producer packages under `dirs` into seed
  candidates for a superadmin, skipping the terms the term table holds
  (`Gallformers.Import.TermCandidates.gather/2`; `mix
  gallformers.import.term_candidates`).
  """
  @spec gather_term_candidates(Actor.t(), [String.t()]) ::
          {:ok, TermCandidates.summary()} | {:error, term()}
  defdelegate gather_term_candidates(actor, dirs), to: TermCandidates, as: :gather

  @doc "The open seed candidates, by Trait, most used first; `decided: true` adds the decided."
  @spec list_term_candidates(keyword()) :: [TermCandidate.t()]
  defdelegate list_term_candidates(opts \\ []), to: TermCandidates, as: :list

  @doc "A seed candidate by ID, raising if there is none."
  @spec get_term_candidate!(integer()) :: TermCandidate.t()
  defdelegate get_term_candidate!(id), to: TermCandidates, as: :get!

  @doc """
  Rules on a seed candidate — `{:place, category}`, `{:ambiguous,
  candidates}` or `:no_fit` — as a term edit recorded for replay, and
  marks it decided (`Gallformers.Import.TermCandidates.decide/3`).
  """
  @spec decide_term_candidate(Actor.t(), TermCandidate.t(), TermCandidates.decision()) ::
          {:ok, TermCandidate.t()} | {:error, term()}
  defdelegate decide_term_candidate(actor, candidate, decision), to: TermCandidates, as: :decide

  @doc """
  Places each of `candidates` whose uses all suggest one category under
  it; skips the others (`Gallformers.Import.TermCandidates.place_by_suggestion/2`).
  """
  @spec place_term_candidates(Actor.t(), [TermCandidate.t()]) ::
          {:ok, %{placed: non_neg_integer(), skipped: non_neg_integer(), failed: list()}}
  defdelegate place_term_candidates(actor, candidates),
    to: TermCandidates,
    as: :place_by_suggestion

  # -- helpers -----------------------------------------------------------------

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
