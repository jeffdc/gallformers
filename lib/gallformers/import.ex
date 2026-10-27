defmodule Gallformers.Import do
  @moduledoc """
  Import: taking a package (the contract in `priv/import/`) into Gallformers
  (`9449` §5; decisions in `e381`, `d585`).

  A package is one Source's `document.json`, `taxonomy.json`, `gall.json`
  and `review.json`, delivered to the private bucket under
  `import/<key>/`. The steps:

    1. **Register** (`register_package/3`): records the package as
       `:received`.
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
       honoured). Unresolved Host names hold the gall batch (`d585`). The
       package's Source is matched (`Gallformers.Import.SourceStep`) and
       phase 6 disputes from `review.json` are queued.
    4. **Decide** (`decide_queue_item/3`): an admin answers each open item,
       recorded with who and when. The same queue holds rename proposals,
       which come from taxonomy changes rather than packages
       (`Gallformers.Import.GallRenames`, `list_gall_renames/1`).
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
  denials, and the Host-name step's and taxonomy admin's edits
  (`record_synonym_added/4`, `record_plant_added/2`,
  `record_taxonomy_edit/2`, `record_wcvp_edit/2`).
  `Gallformers.Import.Replay` replays it after the cutover data migration:
  `export_replay_log/0` writes preview's log to the private bucket and
  `replay_exported/2` replays that file on production
  (`Gallformers.Import.ReplayExport`; `Gallformers.Release` runs both).

  ## Writes

  Every write is audited (`Gallformers.Audit`) as the given actor.
  `batch_statements` and `batch_unmapped` are derived from a batch and not
  audited themselves, but are written inside audited transactions.
  """
  use Boundary,
    deps: [
      Gallformers.Audit,
      Gallformers.Catalog,
      Gallformers.Facts,
      Gallformers.Licenses,
      Gallformers.Places,
      Gallformers.Ranges,
      Gallformers.Repo,
      Gallformers.Sources,
      Gallformers.Storage,
      Gallformers.Taxa
    ],
    exports: [
      Batch,
      BatchStatement,
      BatchUnmapped,
      Package,
      QueueItem,
      Replay,
      ReplayEntry,
      Validator,
      Validator.Problem,
      Worker
    ]

  import Ecto.Query

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Import.ApplyGall
  alias Gallformers.Import.ApplyTaxonomy
  alias Gallformers.Import.Batch
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.BatchUnmapped
  alias Gallformers.Import.GallMatcher
  alias Gallformers.Import.GallRenames
  alias Gallformers.Import.Package
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Import.ReplayExport
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.Resolver
  alias Gallformers.Import.SourceEdits
  alias Gallformers.Import.SourceStep
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.TaxonomyAdmin
  alias Gallformers.Import.TaxonomyEdits
  alias Gallformers.Import.Validator
  alias Gallformers.Import.Validator.Problem
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

    for batch <- batches do
      store_resolution(package, resolve_batch(batch, taxonomy, texts, review))
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
    Repo.delete_all(
      from(q in QueueItem,
        where: q.package_id == ^package.id and is_nil(q.batch_id) and q.status == :open
      )
    )

    decided =
      from(q in QueueItem,
        where: q.package_id == ^package.id and is_nil(q.batch_id) and q.status == :decided,
        select: q.statement_ref
      )
      |> Repo.all()

    items
    |> Enum.reject(&(&1.statement_ref in decided))
    |> insert_queue_items(package, nil)
  end

  defp document_texts(nil), do: []

  defp document_texts(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{} = doc} -> doc |> Docling.items() |> Enum.map(&Docling.item_text/1)
      _ -> []
    end
  end

  # Resolves one batch, honouring its decided queue items: the statements,
  # the queue items they call for (less those already decided, and less
  # unresolved names no act or Fact needs), and its status.
  defp resolve_batch(%Batch{content: content} = batch, taxonomy, texts, review) do
    decided = Queue.decided(batch.id)
    context = Resolver.context(content, taxonomy: taxonomy, document_texts: texts)
    taxa = content |> Resolver.resolve_taxa(context) |> Queue.overlay(decided)

    {statements, queue, status} =
      case batch.batch_type do
        :taxonomy ->
          {taxa, Resolver.queue_items(taxa), :ready}

        :gall ->
          galls = content |> GallMatcher.match_galls(taxa) |> Queue.overlay(decided)

          {taxa ++ galls, Resolver.queue_items(taxa) ++ GallMatcher.queue_items(galls),
           if(Queue.holds_gall_batch?(taxa), do: :blocked, else: :ready)}
      end

    needed = needed_taxon_refs(batch.batch_type, content)
    decided_refs = for(%{kind: kind} = q <- decided, kind != :dispute, do: q.statement_ref)
    decided_disputes = for(%{kind: :dispute} = q <- decided, do: q.statement_ref)

    queue =
      Enum.filter(queue, fn item ->
        item.statement_ref not in decided_refs and
          (not String.starts_with?(item.statement_ref, "t") or item.statement_ref in needed)
      end) ++
        Enum.reject(
          Queue.dispute_items(review, batch.file),
          &(&1.statement_ref in decided_disputes)
        )

    %{batch: batch, statements: statements, queue: queue, status: status}
  end

  # The taxon refs a batch's acts or Galls and Facts need resolved. A
  # synonymy act's `name` is a name, not a taxon: it need not resolve.
  defp needed_taxon_refs(:taxonomy, content) do
    for act <- List.wrap(content["acts"]),
        role <- ["taxon", "parent", "accepted", "into"],
        ref <- List.wrap(act[role]),
        uniq: true,
        do: ref
  end

  defp needed_taxon_refs(:gall, content) do
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

    Repo.delete_all(from(q in QueueItem, where: q.batch_id == ^batch.id and q.status == :open))
    insert_queue_items(resolution.queue, package, batch.id)

    batch
    |> Batch.status_changeset(resolution.status)
    |> Repo.update()
    |> unwrap_or_rollback()
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

  @doc "A batch's statements with their resolutions: taxa, then Galls, each in batch order."
  @spec list_statements(Batch.t()) :: [BatchStatement.t()]
  def list_statements(%Batch{id: batch_id}) do
    Repo.all(from(s in BatchStatement, where: s.batch_id == ^batch_id, order_by: s.id))
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

  # -- decisions ---------------------------------------------------------------

  @doc """
  Records an admin's `decision` on an open queue item, with who (`actor`)
  and when (`Gallformers.Import.Queue` lists what each kind takes). The
  decision is honoured at once — a decided taxon or Gall statement follows
  it, and a gall batch held only by a decided Host name is freed — and
  every later resolution keeps it. The replay log records it.

  `{:error, :already_decided}` for a decided item; `{:error, changeset}`
  (errors on `:decision`) for a decision that does not fit the item.
  """
  @spec decide_queue_item(Actor.t(), QueueItem.t(), map()) ::
          {:ok, QueueItem.t()} | {:error, :already_decided | Changeset.t()}
  def decide_queue_item(%Actor{} = actor, %QueueItem{} = item, decision) do
    Audit.transaction(actor, "import.decide_queue_item", fn ->
      item = Repo.one!(from(q in QueueItem, where: q.id == ^item.id, lock: "FOR UPDATE"))
      if item.status == :decided, do: Repo.rollback(:already_decided)

      item =
        item
        |> QueueItem.decide_changeset(decision, actor)
        |> Queue.validate_decision(item, decision)
        |> Repo.update()
        |> unwrap_or_rollback()

      item =
        case item.kind do
          :gall_rename -> GallRenames.honour(actor, item)
          _kind -> tap(item, &honour/1)
        end

      log_decision(item)
      item
    end)
  end

  # Applies a decision to its stored statement and the batch's status.
  defp honour(%QueueItem{batch_id: nil}), do: :ok

  defp honour(%QueueItem{batch_id: batch_id, statement_ref: ref, decision: decision}) do
    statement =
      Repo.one(
        from(s in BatchStatement,
          where: s.batch_id == ^batch_id and s.ref == ^ref and s.kind in [:taxon, :gall]
        )
      )

    if statement do
      decided = Queue.apply_decision(statement, decision)

      if decided != statement do
        statement
        |> Changeset.change(
          Map.take(decided, [:resolution, :taxon_id, :gall_id, :method, :flags])
        )
        |> Repo.update!()
      end
    end

    refresh_batch_status(get_batch!(batch_id))
  end

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

  defp log_decision(%QueueItem{kind: :gall_rename} = item) do
    ReplayLog.append!(:queue_decision, GallRenames.replay_key(item), %{
      "decision" => StableRef.encode_decision(item.decision),
      "from" => item.proposal["from"]
    })
  end

  defp log_decision(%QueueItem{} = item) do
    package = get_package!(item.package_id)
    batch = item.batch_id && get_batch!(item.batch_id)

    ReplayLog.append!(
      :queue_decision,
      %{
        "package" => package.key,
        "batch_id" => batch && batch.producer_batch_id,
        "kind" => Atom.to_string(item.kind),
        "statement_ref" => item.statement_ref
      },
      %{"decision" => StableRef.encode_decision(item.decision)}
    )
  end

  # -- approval ----------------------------------------------------------------

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
  exclusion, say; `priv/import/GALLFORMERS_STATEMENTS.md`) as a package of
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
    {:ok, source, items} =
      actor
      |> SourceStep.ensure(package, batch.content["source"], files, package_decisions(package))
      |> ok_or_rollback()

    if package.source_id == nil do
      package |> Changeset.change(source_id: source.id) |> Repo.update() |> unwrap_or_rollback()
    end

    statements = list_statements(batch)

    ctx = %{
      actor: actor,
      source: source,
      batch: batch,
      items: items,
      taxa: for(%{kind: :taxon} = s <- statements, into: %{}, do: {s.ref, s}),
      galls: for(%{kind: :gall} = s <- statements, into: %{}, do: {s.ref, s}),
      drop: batch.id |> Queue.decided() |> Queue.drops()
    }

    runner = if batch.batch_type == :taxonomy, do: ApplyTaxonomy, else: ApplyGall
    result = ctx |> runner.run() |> unwrap_or_rollback()

    record_applied(package, batch, result)

    ReplayLog.append!(
      :batch_applied,
      %{"batch_id" => batch.producer_batch_id, "package" => package.key},
      %{"file" => batch.file}
    )

    batch |> Batch.status_changeset(:applied) |> Repo.update() |> unwrap_or_rollback()
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
    * `{:remove_synonym, name}` — `Gallformers.Taxa.remove_synonym/2`
    * `{:remove_common_name, name}` — `Gallformers.Taxa.remove_common_name/2`
    * `{:delete_taxon, taxon}` — `Gallformers.Taxa.delete_taxon/2`
    * `{:set_host_range, taxon, entries}` — `Gallformers.Ranges.update_taxon_places/3`
    * `{:set_wcvp, taxon, attrs}` — `Gallformers.Ranges.Wcvp.put_link/3`

  The last six are `Gallformers.Import.TaxonomyEdits`'s, which says how
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

  @doc "Moves each of `taxon_ids` under `parent_id` (`Gallformers.Import.TaxonomyAdmin.move_all/3`)."
  @spec record_taxa_moved(Actor.t(), [integer()], integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defdelegate record_taxa_moved(actor, taxon_ids, parent_id), to: TaxonomyAdmin, as: :move_all

  defp taxon_id(%Taxa.Taxon{id: id}), do: id
  defp taxon_id(id) when is_integer(id), do: id

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

  # -- helpers -----------------------------------------------------------------

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
