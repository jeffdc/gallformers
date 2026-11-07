defmodule Gallformers.Curation do
  @moduledoc """
  Curation (matter `ec2c`, "Change-set interface"): a curator's change set,
  the tray that follows them across pages. Every Gallformers edit goes
  through the same Fact process as Source intake; the tray is where a
  curator's edits collect before they do.

  Every call takes the curator's `%Actor{}` (a `:user`); a set is private
  to its author until applied. One set per curator, saved with their
  account (`Gallformers.Curation.ChangeSet`); its items
  (`Gallformers.Curation.Item`) are

    * **Fact items** — `%{kind: :fact, gall_id, action: :add | :withdraw |
      :correct, key, to}`: Gallformers' statements, confirming, denying, or
      denying `key` and confirming `to`;
    * **notes** — `%{kind: :note, gall_id, key, text}`: a note on a Fact, a
      record of its own (`Gallformers.Catalog.FactNote`);
    * **editorial items** — `%{kind: :editorial, subject: {:gall, id} |
      {:plant, id}, field, value}` (`based_on` on a plant's).

  Keys are the Gall page's (`Gallformers.Catalog.find_gall_fact/2`); specs
  and evidence are checked by `Gallformers.Curation.Spec`. One item per Fact
  key (of each kind) or field: another edit of it replaces it.

  **Review** (`preview/1`, `Gallformers.Curation.Review`) flags each item
  against current data and the audit trail. **Apply** (`apply/2`,
  `apply_item/3`, `Gallformers.Curation.Applying`) applies each item on its
  own: editorial items and notes at once; Fact items as one package of
  Gallformers' statements that the import job applies, the items waiting in
  the tray for the outcome (`Gallformers.Curation.PackageListener`).

  Drafts are not data: the tables are not audited or replayed, and stay out
  of the public snapshot. What an item becomes when applied — the package,
  the editorial edit, the note — is audited and replayed as any other.

  ## PubSub

  `"curation:user:<id>"` gets `{:change_set, :changed}` when the curator's
  set changes and `{:change_set, {:outcome, item_id, outcome}}` when a
  submitted item's outcome arrives (`:applied`, `{:waiting_review,
  package_id}`, `{:held, reason}`); `"curation:gall:<id>"` and
  `"curation:plant:<id>"` get `{:change_set, :others_changed}` when anyone's
  items about that subject change (`subscribe/1`, `subscribe_subject/1`).
  """
  use Boundary,
    deps: [
      Gallformers.Audit,
      Gallformers.Catalog,
      Gallformers.Facts,
      Gallformers.Import,
      Gallformers.INaturalist,
      Gallformers.Places,
      Gallformers.Repo,
      Gallformers.Sources,
      Gallformers.Taxa
    ],
    exports: [ChangeSet, Item, Key, PackageListener]

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit.Actor
  alias Gallformers.Audit.ChangeLog
  alias Gallformers.Catalog
  alias Gallformers.Curation.Applying
  alias Gallformers.Curation.ChangeSet
  alias Gallformers.Curation.FromObservation
  alias Gallformers.Curation.Item
  alias Gallformers.Curation.Key
  alias Gallformers.Curation.Review
  alias Gallformers.Curation.Spec
  alias Gallformers.Curation.Wording
  alias Gallformers.Facts
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @pubsub Gallformers.PubSub

  @typedoc "An item's subject."
  @type subject :: {:gall | :plant, integer()}

  @typedoc """
  Evidence for Fact items: text ("my judgement" is text alone), the
  Observations that support it, and the Source it follows (cited by
  Gallformers' statement).
  """
  @type evidence :: %{
          text: String.t() | nil,
          observations: [%{provider: String.t(), id: String.t()}],
          source_id: integer() | nil
        }

  @typedoc """
  A preview flag: `kind` (`:new`, `:held`, `:adds_statement`, `:supersedes`,
  `:changed_since`, `:needs_confirmation`, `:editorial`, `:needs_reason`,
  `:blocked`), `text` (its words) and `flag`, the contract's term: `:new`,
  `{:held, sources}`, `:adds_statement` (a held Fact gains Gallformers'
  statement), `{:supersedes, statements}`, `{:changed_since, user, at}`,
  `:needs_confirmation`, `:editorial`, `:needs_reason`, `{:blocked, reason}`.
  """
  @type flag :: %{kind: atom(), text: String.t(), flag: term()}

  @typedoc "An item as Review shows it."
  @type preview_entry :: %{
          id: integer(),
          kind: :fact | :note | :editorial,
          text: String.t(),
          subject: subject(),
          subject_name: String.t(),
          key: Key.t(),
          state: :in_tray | :waiting,
          flags: [flag()],
          item: Item.t()
        }

  @typedoc "What `apply/2` did with each item: by item ID."
  @type apply_result :: %{
          applied: [integer()],
          submitted: [integer()],
          held: [{integer(), String.t()}]
        }

  # -- the set -------------------------------------------------------------------

  @doc "The curator's open set with its items, or nil."
  @spec open_set(Actor.t()) :: ChangeSet.t() | nil
  def open_set(%Actor{type: :user, id: user_id}) do
    case Repo.get_by(ChangeSet, user_id: user_id) do
      nil -> nil
      set -> decorate_set(set)
    end
  end

  @doc """
  Adds an item to the curator's set (made if they have none): `{:ok, item}`
  (decorated: its `id`, `text`, `key`, …), or `{:error, reason}` —
  `:no_such_gall`, `:no_such_plant`, `:no_such_taxon`, `:no_such_place`,
  `:invalid_key` (a key that cannot name a Fact of the Gall, such as an
  unknown Trait value), `:no_fact` (a note on a Fact the Gall does not
  have), `:unknown_field`, `:invalid_value`, `:invalid_spec`, or
  `:waiting` (the same edit is submitted, waiting for its outcome).

  An edit of a key or field the set has an item for replaces that item's
  edit, keeping its ID and evidence; what it saw is taken again.
  """
  @spec add_item(Actor.t(), map()) :: {:ok, Item.t()} | {:error, atom()}
  def add_item(%Actor{type: :user} = actor, spec) when is_map(spec) do
    with {:ok, checked} <- Spec.check(spec) do
      {type, subject_id} = checked.subject
      now = DateTime.utc_now()

      result =
        Repo.transaction(fn ->
          set = ensure_set(actor)

          existing =
            Repo.one(
              from(i in Item,
                where:
                  i.change_set_id == ^set.id and i.kind == ^checked.kind and
                    i.subject_type == ^type and i.subject_id == ^subject_id and
                    i.key == ^checked.key,
                lock: "FOR UPDATE"
              )
            )

          attrs = [
            stored_spec: checked.stored,
            seen: seen(checked),
            seen_at: now,
            stored_outcome: nil
          ]

          case existing do
            %Item{status: :draft} = item ->
              item |> Ecto.Changeset.change(attrs) |> Repo.update!()

            %Item{} ->
              Repo.rollback(:waiting)

            nil ->
              Repo.insert!(
                struct(
                  %Item{
                    change_set_id: set.id,
                    kind: checked.kind,
                    subject_type: type,
                    subject_id: subject_id,
                    key: checked.key
                  },
                  attrs
                )
              )
          end
        end)

      with {:ok, item} <- result do
        changed(actor, [checked.subject])
        {:ok, decorate(item)}
      end
    end
  end

  @doc "Takes an item out of the curator's set. `{:error, :not_found}` if it is not theirs."
  @spec remove_item(Actor.t(), integer()) :: :ok | {:error, :not_found}
  def remove_item(%Actor{type: :user} = actor, item_id) do
    case own_item(actor, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        Repo.delete!(item)
        drop_empty_set(item.change_set_id)
        changed(actor, [{item.subject_type, item.subject_id}])
        :ok
    end
  end

  @doc "Discards the curator's set and every item in it (the UI confirms first)."
  @spec discard(Actor.t()) :: :ok
  def discard(%Actor{type: :user, id: user_id} = actor) do
    case Repo.get_by(ChangeSet, user_id: user_id) do
      nil ->
        :ok

      set ->
        subjects =
          Repo.all(
            from(i in Item,
              where: i.change_set_id == ^set.id,
              distinct: true,
              select: {i.subject_type, i.subject_id}
            )
          )

        Repo.delete!(set)
        changed(actor, subjects)
        :ok
    end
  end

  @doc """
  Sets the evidence for the set's Fact items (`t:evidence/0`; an item's own
  evidence overrides it). `{:error, :invalid_evidence}` for an Observation
  of another provider or a Source Gallformers does not hold.
  """
  @spec set_evidence(Actor.t(), map()) :: {:ok, ChangeSet.t()} | {:error, :invalid_evidence}
  def set_evidence(%Actor{type: :user} = actor, evidence) do
    with {:ok, stored} <- Spec.check_evidence(evidence) do
      {:ok, set} =
        Repo.transaction(fn ->
          actor |> ensure_set() |> Ecto.Changeset.change(evidence: stored) |> Repo.update!()
        end)

      changed(actor, [])
      {:ok, decorate_set(set)}
    end
  end

  @doc "Sets one item's own evidence, or with nil makes it use the set's."
  @spec set_item_evidence(Actor.t(), integer(), map() | nil) ::
          {:ok, Item.t()} | {:error, :not_found | :invalid_evidence}
  def set_item_evidence(%Actor{type: :user} = actor, item_id, evidence) do
    stored = if is_nil(evidence), do: {:ok, nil}, else: Spec.check_evidence(evidence)

    with {:ok, stored} <- stored,
         %Item{} = item <- own_item(actor, item_id) || {:error, :not_found} do
      item = item |> Ecto.Changeset.change(evidence: stored) |> Repo.update!()
      changed(actor, [])
      {:ok, decorate(item)}
    end
  end

  # -- add from observation ------------------------------------------------------

  @typedoc """
  An item `from_observation/3` proposes: `spec` as `add_item/2` takes it
  (`gall_id` nil until the curator chooses the Gall), its display text,
  `why` it was proposed, and whether it is pre-`selected`.
  """
  @type proposed_item :: %{
          role: :occurrence | :host,
          spec: map(),
          text: String.t(),
          why: String.t(),
          selected: boolean()
        }

  @typedoc "What `from_observation/3` proposes from one iNaturalist observation."
  @type observation_proposal :: %{
          observation: %{
            id: integer(),
            url: String.t(),
            taxon_name: String.t() | nil,
            observed_on: Date.t() | nil,
            place_guess: String.t() | nil,
            observer: String.t()
          },
          inat_observation: Gallformers.INaturalist.Observation.t(),
          evidence: evidence(),
          gall: %{
            gall_id: integer() | nil,
            candidates: [%{id: integer(), name: String.t(), datacomplete: boolean()}],
            why: String.t() | nil
          },
          items: [proposed_item()],
          needs: [%{kind: :gall | :place | :host, text: String.t()}],
          photos: [Gallformers.INaturalist.Photo.t()]
        }

  @doc """
  Add from observation: reads one iNaturalist observation (`url_or_id`, a
  URL or bare ID) and proposes tray items for the curator to confirm. It
  adds nothing to the tray: the curator adds the items they keep with
  `add_item/2` (each `spec`, its `gall_id` set to the Gall chosen), and
  sets `evidence` — the observation — on them (`set_item_evidence/3`) or
  on the set (`set_evidence/2`).

    * `items`: a recorded occurrence `{:occurrence, place_id}` for the
      observation's state or province, `when` its observed date (never a
      season Fact); a Host `{:host, taxon_id}` for each plant the "Host
      Plant ID" field and the description name, matched as intake matches
      a Host. Several readings of one name are all offered, the proposed
      one (if any) `selected`.
    * `gall`: `gall_id` given; otherwise the Galls of the observation's
      taxon as Inducer (`candidates`), `gall_id` pre-selected when there
      is only one or the "Gallformers Code" field names one, else nil.
    * `needs`: what the curator must give (`:gall`, `:place`, `:host`),
      in words.
    * `photos` and `inat_observation`: for the iNaturalist image import
      (`GallformersWeb.Admin.InatImportComponent`, whose `fetch_result`
      takes `{:ok, inat_observation}`).

  Errors: `:invalid_input` (not an observation URL or ID), `:not_found`
  (no such observation), `:unavailable` (iNaturalist could not be reached
  or answered with an error), `:no_such_gall`.
  """
  @spec from_observation(Actor.t(), String.t() | integer(), integer() | nil) ::
          {:ok, observation_proposal()}
          | {:error, :invalid_input | :not_found | :unavailable | :no_such_gall}
  def from_observation(%Actor{type: :user}, url_or_id, gall_id),
    do: FromObservation.propose(url_or_id, gall_id)

  # -- reading -------------------------------------------------------------------

  @doc """
  Review: each of the curator's items with its flags (`t:flag/0`), computed
  against current data now. Items waiting for an outcome have no flags.
  """
  @spec preview(Actor.t()) :: [preview_entry()]
  def preview(%Actor{type: :user} = actor) do
    case open_set(actor) do
      nil -> []
      set -> Enum.map(set.items, &entry(actor, &1, set.evidence))
    end
  end

  defp entry(actor, item, set_evidence) do
    flags =
      if item.status == :draft,
        do: actor |> Review.flags(item, set_evidence) |> Enum.map(&flag/1),
        else: []

    %{
      id: item.id,
      kind: item.kind,
      text: item.text,
      subject: item.subject,
      subject_name: item.subject_name,
      key: item.key,
      state: item.state,
      flags: flags,
      item: item
    }
  end

  defp flag(flag) do
    kind = if is_tuple(flag), do: elem(flag, 0), else: flag
    %{kind: kind, text: Wording.flag_text(flag), flag: flag}
  end

  @doc "The curator's items about one Gall or plant, by key (a key may have a Fact item and a note)."
  @spec pending_for(Actor.t(), subject()) :: %{Key.t() => [Item.t()]}
  def pending_for(%Actor{type: :user, id: user_id}, {type, id}) do
    from(i in Item,
      join: s in ChangeSet,
      on: s.id == i.change_set_id,
      where: s.user_id == ^user_id and i.subject_type == ^type and i.subject_id == ^id,
      order_by: i.id
    )
    |> Repo.all()
    |> Enum.map(&decorate/1)
    |> Enum.group_by(& &1.key)
  end

  @doc """
  The curators with unapplied items about a Gall or plant:
  `[%{user: %{id, name}, count, since}]`, `since` their oldest item's time;
  without `except` (a curator) itself.
  """
  @spec others_pending(subject(), Actor.t() | nil) :: [
          %{user: %{id: integer(), name: String.t()}, count: pos_integer(), since: DateTime.t()}
        ]
  def others_pending({type, id}, except \\ nil) do
    except_id = except && except.id

    from(i in Item,
      join: s in ChangeSet,
      on: s.id == i.change_set_id,
      where: i.subject_type == ^type and i.subject_id == ^id,
      group_by: [s.user_id, s.user_name],
      order_by: [min(i.inserted_at), s.user_id],
      select: %{
        user_id: s.user_id,
        name: s.user_name,
        count: count(i.id),
        since: min(i.inserted_at)
      }
    )
    |> Repo.all()
    |> Enum.reject(&(&1.user_id == except_id))
    |> Enum.map(&%{user: %{id: &1.user_id, name: &1.name}, count: &1.count, since: &1.since})
  end

  @doc """
  What the indicator on every page shows: how many items the curator has,
  each as a line ("<subject>: <item>"), and when the oldest was added
  (for the "left a while" reminder).
  """
  @spec summary(Actor.t()) :: %{
          count: non_neg_integer(),
          lines: [String.t()],
          oldest_at: DateTime.t() | nil
        }
  def summary(%Actor{type: :user} = actor) do
    case open_set(actor) do
      nil ->
        %{count: 0, lines: [], oldest_at: nil}

      %ChangeSet{items: items} ->
        %{
          count: length(items),
          lines: Enum.map(items, &"#{&1.subject_name}: #{&1.text}"),
          oldest_at: items |> Enum.map(& &1.inserted_at) |> Enum.min(DateTime, fn -> nil end)
        }
    end
  end

  # -- applying ------------------------------------------------------------------

  @doc """
  Applies the curator's items, each on its own (never all-or-nothing).
  `opts`: `confirm:` the IDs of items that need confirmation (a Gall's code
  or name parts) and have it.

    * editorial items and notes apply at once (`applied`);
    * a Fact item Gallformers itself states already, with the same
      Observations, is a no-op (`applied`, nothing written); one only other
      Sources hold is submitted, adding Gallformers' statement;
    * the other Fact items become one Gallformers package (`submitted`):
      they wait in the tray for its outcome, broadcast per item;
    * an item that is blocked, needs a reason or needs confirmation it was
      not given, or fails, stays in the tray (`held`, with the reason).

  Items already waiting for an outcome are left as they are. When anything
  was applied or submitted, the pages listing the curators' changes hear
  of it (`Gallformers.Audit.ChangeLog.changed/0`).
  """
  @spec apply(Actor.t(), keyword()) :: {:ok, apply_result()}
  def apply(%Actor{type: :user} = actor, opts \\ []) do
    case open_set(actor) do
      nil -> {:ok, %{applied: [], submitted: [], held: []}}
      set -> {:ok, apply_items(actor, set, Enum.filter(set.items, &(&1.status == :draft)), opts)}
    end
  end

  @doc """
  Applies one of the curator's items alone (as `apply/2`): a Fact item in a
  package of its own. `{:error, :not_found}` if it is not theirs.
  """
  @spec apply_item(Actor.t(), integer(), keyword()) ::
          {:ok, apply_result()} | {:error, :not_found}
  def apply_item(%Actor{type: :user} = actor, item_id, opts \\ []) do
    with %ChangeSet{} = set <- open_set(actor),
         %Item{status: :draft} = item <- Enum.find(set.items, &(&1.id == item_id)) do
      {:ok, apply_items(actor, set, [item], opts)}
    else
      %Item{} -> {:ok, %{applied: [], submitted: [], held: []}}
      nil -> {:error, :not_found}
    end
  end

  defp apply_items(actor, set, items, opts) do
    confirmed = Keyword.get(opts, :confirm, [])

    decided =
      Enum.map(items, fn item ->
        flags = actor |> Review.flags(item, set.evidence) |> Map.new(&{flag_kind(&1), &1})
        {item, decide(item, flags, confirmed)}
      end)

    {applied_now, failed_now} = run_now(actor, for({item, :now} <- decided, do: item))
    noops = for {item, :noop} <- decided, do: item
    to_submit = for {item, :submit} <- decided, do: {item, Applying.evidence(item, set.evidence)}
    {submission, submitted, failed_submit} = submit(actor, to_submit)

    applied = applied_now ++ noops

    held =
      for({item, {:hold, reason}} <- decided, do: {item, reason}) ++ failed_now ++ failed_submit

    Enum.each(applied, &Repo.delete!/1)
    Enum.each(held, fn {item, reason} -> hold!(item, reason) end)
    drop_empty_set(set.id)
    changed(actor, Enum.map(items, & &1.subject))

    with {:ok, package, _refs} <- submission, do: settle_package(package.id)
    if applied_now != [] or submitted != [], do: ChangeLog.changed()

    %{
      applied: Enum.map(applied, & &1.id),
      submitted: Enum.map(submitted, & &1.id),
      held: Enum.map(held, fn {item, reason} -> {item.id, reason} end)
    }
  end

  # Editorial items and notes: {applied, [{item, reason}]}.
  defp run_now(actor, items) do
    Enum.reduce(items, {[], []}, fn item, {applied, held} ->
      case Applying.run(actor, item) do
        :ok -> {applied ++ [item], held}
        {:error, reason} -> {applied, held ++ [{item, "Can't apply: " <> reason}]}
      end
    end)
  end

  # Fact items: {submission, submitted items, [{item, reason}]}.
  defp submit(_actor, []), do: {nil, [], []}

  defp submit(actor, to_submit) do
    {submission, unnamed} = Applying.submit(actor, to_submit)
    {submitted, failed} = record_submission(submission, to_submit)
    {submission, submitted, unnamed ++ failed}
  end

  defp flag_kind(flag) when is_tuple(flag), do: elem(flag, 0)
  defp flag_kind(flag), do: flag

  defp decide(item, flags, confirmed) do
    cond do
      Map.has_key?(flags, :blocked) ->
        {:hold, Wording.flag_text(flags.blocked)}

      Map.has_key?(flags, :needs_reason) ->
        {:hold, Wording.flag_text(:needs_reason)}

      Map.has_key?(flags, :needs_confirmation) and item.id not in confirmed ->
        {:hold, Wording.flag_text(:needs_confirmation)}

      item.kind != :fact ->
        :now

      Map.has_key?(flags, :held) and not Map.has_key?(flags, :adds_statement) ->
        :noop

      true ->
        :submit
    end
  end

  defp record_submission(nil, _to_submit), do: {[], []}

  defp record_submission({:ok, package, refs}, to_submit) do
    items = for {item, _evidence} <- to_submit, Map.has_key?(refs, item.id), do: item
    Enum.each(items, &put_submitted(&1.id, package.id, refs[&1.id]))
    {items, []}
  end

  defp record_submission({:error, reason}, to_submit),
    do: {[], for({item, _evidence} <- to_submit, do: {item, reason})}

  defp hold!(item, reason) do
    item
    |> Repo.reload!()
    |> Ecto.Changeset.change(
      status: :draft,
      package_id: nil,
      package_refs: [],
      stored_outcome: %{"held" => reason}
    )
    |> Repo.update!()
  end

  @doc false
  # Marks an item submitted in package `package_id` as Fact refs `refs`.
  @spec put_submitted(integer(), integer(), [String.t()]) :: :ok
  def put_submitted(item_id, package_id, refs) do
    from(i in Item, where: i.id == ^item_id)
    |> Repo.update_all(
      set: [
        status: :submitted,
        package_id: package_id,
        package_refs: refs,
        stored_outcome: nil,
        updated_at: DateTime.utc_now()
      ]
    )

    :ok
  end

  @doc """
  Brings the items waiting on package `package_id` up to date with it
  (`Gallformers.Curation.Applying.outcomes/2`), broadcasting each outcome
  that changed: an applied item leaves the tray; one held goes back to it,
  with the reason; one waiting for review is marked so, with the package.
  """
  @spec settle_package(integer()) :: :ok
  def settle_package(package_id) when is_integer(package_id) do
    package_id
    |> Applying.waiting_on()
    |> then(&Applying.outcomes(package_id, &1))
    |> Enum.group_by(fn {item, _outcome} -> item.change_set_id end)
    |> Enum.each(fn {set_id, outcomes} -> settle_set(set_id, outcomes) end)
  end

  defp settle_set(set_id, outcomes) do
    set = Repo.get(ChangeSet, set_id)

    told =
      for {item, outcome} <- outcomes, told = settle_item(item, outcome), do: {item, told}

    if set && told != [] do
      drop_empty_set(set_id)

      for {item, outcome} <- told do
        broadcast(user_topic(set.user_id), {:change_set, {:outcome, item.id, outcome}})
      end

      broadcast(user_topic(set.user_id), {:change_set, :changed})

      for subject <- Enum.uniq(for {item, _} <- told, do: {item.subject_type, item.subject_id}),
          do: broadcast(subject_topic(subject), {:change_set, :others_changed})
    end

    :ok
  end

  defp settle_item(item, :applied) do
    Repo.delete!(item)
    :applied
  end

  defp settle_item(%Item{status: :in_review}, {:waiting_review, _id}), do: nil

  defp settle_item(item, {:waiting_review, _id} = outcome) do
    item |> Ecto.Changeset.change(status: :in_review) |> Repo.update!()
    outcome
  end

  defp settle_item(item, {:held, reason} = outcome) do
    hold!(item, reason)
    outcome
  end

  defp settle_item(_item, :waiting), do: nil

  # -- PubSub --------------------------------------------------------------------

  @doc ~s(Subscribes the calling process to the curator's set: `"curation:user:<id>"`.)
  @spec subscribe(Actor.t()) :: :ok | {:error, term()}
  def subscribe(%Actor{type: :user, id: id}),
    do: Phoenix.PubSub.subscribe(@pubsub, user_topic(id))

  @doc ~s(Subscribes the calling process to a subject's page: `"curation:gall:<id>"`, `"curation:plant:<id>"`.)
  @spec subscribe_subject(subject()) :: :ok | {:error, term()}
  def subscribe_subject(subject), do: Phoenix.PubSub.subscribe(@pubsub, subject_topic(subject))

  @doc "The topic of a curator's set."
  @spec user_topic(integer()) :: String.t()
  def user_topic(user_id), do: "curation:user:#{user_id}"

  @doc "The topic of a subject's page."
  @spec subject_topic(subject()) :: String.t()
  def subject_topic({type, id}), do: "curation:#{type}:#{id}"

  defp changed(%Actor{id: user_id}, subjects) do
    broadcast(user_topic(user_id), {:change_set, :changed})

    for subject <- Enum.uniq(subjects),
        do: broadcast(subject_topic(subject), {:change_set, :others_changed})

    :ok
  end

  defp broadcast(topic, message), do: Phoenix.PubSub.broadcast(@pubsub, topic, message)

  # -- helpers -------------------------------------------------------------------

  defp ensure_set(%Actor{id: user_id, name: name}) do
    Repo.insert!(
      %ChangeSet{user_id: user_id, user_name: name},
      on_conflict: [set: [user_name: name, updated_at: DateTime.utc_now()]],
      conflict_target: :user_id,
      returning: true
    )
  end

  defp drop_empty_set(set_id) do
    unless Repo.exists?(from(i in Item, where: i.change_set_id == ^set_id)),
      do: Repo.delete_all(from(s in ChangeSet, where: s.id == ^set_id))

    :ok
  end

  defp own_item(%Actor{id: user_id}, item_id) when is_integer(item_id) do
    Repo.one(
      from(i in Item,
        join: s in ChangeSet,
        on: s.id == i.change_set_id,
        where: i.id == ^item_id and s.user_id == ^user_id
      )
    )
  end

  defp own_item(_actor, _item_id), do: nil

  # What an item saw when added: the Facts its key names and their standings,
  # or the field's value.
  defp seen(%{kind: kind, subject: {:gall, gall_id}, key: key}) when kind in [:fact, :note] do
    case Catalog.find_gall_fact(gall_id, key) do
      {:ok, nil} -> %{"fact_id" => nil}
      {:ok, id} -> %{"fact_id" => id, "standing" => to_string(Facts.get_fact!(id).standing)}
      {:error, _} -> %{}
    end
  end

  defp seen(%{kind: :editorial, subject: {:gall, id}, key: {:editorial, field}}) do
    gall = Catalog.get_gall!(id)

    value =
      case field do
        :completeness ->
          gall.datacomplete

        :abundance ->
          gall.abundance_id

        :code ->
          gall.gallformers_code

        :default_source_id ->
          gall.default_source_id

        :name_parts ->
          Map.take(gall, [:form_label, :descriptor, :host_qualifier_taxon_id, :name_override])
      end

    %{"value" => value}
  end

  defp seen(%{kind: :editorial, subject: {:plant, id}}), do: %{"name" => Taxa.accepted_name(id)}

  defp decorate_set(%ChangeSet{} = set) do
    set = Repo.preload(set, :items, force: true)
    %{set | evidence: Spec.decode_evidence(set.evidence), items: Enum.map(set.items, &decorate/1)}
  end

  defp decorate(%Item{} = item) do
    spec = Applying.decode_spec(item)

    %{
      item
      | subject: {item.subject_type, item.subject_id},
        subject_name: Wording.subject_name({item.subject_type, item.subject_id}),
        spec: spec,
        text: Wording.item_text(spec),
        evidence: Spec.decode_evidence(item.evidence),
        state: if(item.status == :draft, do: :in_tray, else: :waiting),
        outcome: outcome(item)
    }
  end

  defp outcome(%Item{status: :in_review, package_id: id}), do: {:waiting_review, id}
  defp outcome(%Item{stored_outcome: %{"held" => reason}}), do: {:held, reason}
  defp outcome(_item), do: nil
end
