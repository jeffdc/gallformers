defmodule Gallformers.Import.FactEdits do
  @moduledoc """
  A curator's edits on a package's Facts before approval (matter `f14c`,
  item 4), stored as `Gallformers.Import.StatementEdit`s, by batch and
  statement ref.

  ## Edits

  `edit/5` takes the edit as a map, any of them with a `"note"` (text):

  | Edit | Does |
  |---|---|
  | `%{"drop" => true}` | the Fact (or act) is not written |
  | `%{"host_taxon_id" => plant}` | a Host Fact (`host_of`) is written on that plant, of any rank, for this statement only |
  | `%{"values" => [value, ...]}` | a Trait Fact is written on these values of its Trait, one Fact each, the Source's term kept on the attribution |
  | `%{"note" => text}` | a note only |

  Editing a statement again with the same kind replaces that edit; edits
  of other kinds stay. Removing an edit (`remove/2`) undoes it.

  Only a package awaiting review can be edited, and only a batch not
  applied or denied (`{:error, :not_editable}`); the ref must be a Fact
  (an act, in a taxonomy batch) of the batch (`{:error, :no_statement}`).

  ## Honoured by applying

  `overlay/1` gives, for a batch's edits, what its apply context takes:
  `drop` (ref to why), `hosts` (ref to plant) and `trait_values` (ref to
  values); `Gallformers.Import.ApplyGall` and
  `Gallformers.Import.ApplyTaxonomy` honour them, so the Facts preview
  shows them. Edits win over what a decision chose for the same statement.
  They change no resolution and no question: a dropped Fact's dispute
  still asks, and a Host edit does not resolve a Host name.

  ## The replay log

  Each edit is logged (`:fact_edit`, keyed by the package's key, the
  producer's `batch_id`, the statement ref and the kind; its value with
  stable references, `Gallformers.Import.StableRef`), as is each removal
  (`:fact_edit_removed`). Replayed before the batch is applied again, the
  edit is made again (`replay/5`), unless the batch holds it already or is
  applied or denied (a replay run again).
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.StatementEdit
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @type edit :: map()

  # -- editing -------------------------------------------------------------------

  @doc """
  Makes `edit` on statement `ref` of `batch` (of `package`), as `actor`:
  stored, replacing the statement's edit of the same kind, and logged for
  replay. Returns the stored edit.
  """
  @spec edit(Actor.t(), Package.t(), Batch.t(), String.t(), edit()) ::
          {:ok, StatementEdit.t()}
          | {:error, :not_editable | :no_statement | String.t() | Changeset.t()}
  def edit(%Actor{} = actor, %Package{} = package, %Batch{} = batch, ref, edit)
      when is_binary(ref) and is_map(edit) do
    with {:ok, kind, value, note} <- parse(edit) do
      Audit.transaction(actor, "import.edit_fact", fn ->
        {package, batch} = lock(package, batch)

        with :ok <- editable(package, batch),
             {:ok, statement} <- statement(batch, ref),
             :ok <- check(kind, value, statement, batch) do
          stored = Repo.get_by(StatementEdit, batch_id: batch.id, statement_ref: ref, kind: kind)

          (stored || %StatementEdit{})
          |> StatementEdit.changeset(actor, %{
            package_id: package.id,
            batch_id: batch.id,
            statement_ref: ref,
            kind: kind,
            value: value,
            note: note
          })
          |> Repo.insert_or_update()
          |> then(fn
            {:ok, stored} ->
              log(:fact_edit, package, batch, stored)
              stored

            {:error, changeset} ->
              Repo.rollback(changeset)
          end)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @doc """
  Removes `edit`, undoing it, as `actor`; logged for replay. Refused once
  its batch is applied or denied, or its package is no longer awaiting
  review (`{:error, :not_editable}`).
  """
  @spec remove(Actor.t(), StatementEdit.t()) ::
          {:ok, StatementEdit.t()} | {:error, :not_editable | :not_found}
  def remove(%Actor{} = actor, %StatementEdit{} = edit) do
    Audit.transaction(actor, "import.remove_fact_edit", fn ->
      {package, batch} =
        lock(Repo.get!(Package, edit.package_id), Repo.get!(Batch, edit.batch_id))

      with :ok <- editable(package, batch),
           %StatementEdit{} = stored <- Repo.get(StatementEdit, edit.id) do
        Repo.delete!(stored)
        log(:fact_edit_removed, package, batch, stored)
        stored
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "A package's edits, by batch, statement ref and kind."
  @spec list(Package.t()) :: [StatementEdit.t()]
  def list(%Package{id: package_id}) do
    from(e in StatementEdit,
      where: e.package_id == ^package_id,
      order_by: [e.batch_id, e.statement_ref, e.kind]
    )
    |> Repo.all()
  end

  @doc "A batch's edits."
  @spec for_batch(integer()) :: [StatementEdit.t()]
  def for_batch(batch_id) do
    Repo.all(from(e in StatementEdit, where: e.batch_id == ^batch_id, order_by: e.id))
  end

  defp lock(package, batch) do
    {Repo.one!(from(p in Package, where: p.id == ^package.id, lock: "FOR UPDATE")),
     Repo.one!(from(b in Batch, where: b.id == ^batch.id, lock: "FOR UPDATE"))}
  end

  defp editable(%Package{id: id, status: :awaiting_review}, %Batch{package_id: id, status: status})
       when status not in [:applied, :denied],
       do: :ok

  defp editable(_package, _batch), do: {:error, :not_editable}

  # -- the edit's shape --------------------------------------------------------------

  defp parse(edit) do
    {note, rest} = Map.pop(edit, "note")

    if is_nil(note) or is_binary(note),
      do: parse(rest, note),
      else: {:error, "note must be text"}
  end

  defp parse(%{"drop" => true} = rest, note) when map_size(rest) == 1, do: {:ok, :drop, %{}, note}

  defp parse(%{"host_taxon_id" => _} = rest, note) when map_size(rest) == 1, do: host(rest, note)
  defp parse(%{"values" => _} = rest, note) when map_size(rest) == 1, do: values(rest, note)
  defp parse(rest, note) when map_size(rest) == 0 and is_binary(note), do: {:ok, :note, %{}, note}
  defp parse(_rest, _note), do: {:error, "must be one of drop, host_taxon_id, values or a note"}

  defp host(%{"host_taxon_id" => id} = value, note) do
    if plant?(id), do: {:ok, :host, value, note}, else: {:error, "host_taxon_id must be a plant"}
  end

  defp values(%{"values" => values}, note) do
    values = List.wrap(values)

    if values != [] and Enum.all?(values, &is_binary/1) and Enum.uniq(values) == values,
      do: {:ok, :trait_value, %{"values" => values}, note},
      else: {:error, "values must be one or more values, none twice"}
  end

  defp plant?(id), do: is_integer(id) and match?(%{kingdom: "Plantae"}, Taxa.get_taxon(id))

  # The Fact (or act) `ref` of the batch.
  defp statement(%Batch{content: content}, ref) do
    statements = List.wrap(content["facts"]) ++ List.wrap(content["acts"])

    case Enum.find(statements, &(&1["id"] == ref)) do
      nil -> {:error, :no_statement}
      statement -> {:ok, statement}
    end
  end

  defp check(:host, _value, statement, _batch) do
    if match?(%{"kind" => "relationship", "type" => "host_of"}, statement),
      do: :ok,
      else: {:error, "host_taxon_id goes only on a Host statement"}
  end

  defp check(:trait_value, %{"values" => values}, statement, _batch) do
    case statement do
      %{"kind" => "trait", "trait" => trait} ->
        case Enum.reject(values, &Catalog.get_trait_value(trait, &1)) do
          [] -> :ok
          unknown -> {:error, "not values of #{trait}: #{Enum.join(unknown, ", ")}"}
        end

      _ ->
        {:error, "values go only on a Trait statement"}
    end
  end

  defp check(_kind, _value, _statement, _batch), do: :ok

  # -- applying ----------------------------------------------------------------------

  @doc """
  What a batch's `edits` change in applying it: `drop` (ref to why),
  `hosts` (ref to plant) and `trait_values` (ref to values).
  """
  @spec overlay([StatementEdit.t()]) :: %{
          drop: %{String.t() => String.t()},
          hosts: %{String.t() => integer()},
          trait_values: %{String.t() => [String.t()]}
        }
  def overlay(edits) do
    %{
      drop:
        for(%StatementEdit{kind: :drop} = e <- edits, into: %{}, do: {e.statement_ref, why(e)}),
      hosts:
        for(
          %StatementEdit{kind: :host, value: %{"host_taxon_id" => id}} = e <- edits,
          into: %{},
          do: {e.statement_ref, id}
        ),
      trait_values:
        for(
          %StatementEdit{kind: :trait_value, value: %{"values" => values}} = e <- edits,
          into: %{},
          do: {e.statement_ref, values}
        )
    }
  end

  defp why(%StatementEdit{author_name: author, note: nil}), do: "an edit by #{author}"
  defp why(%StatementEdit{author_name: author, note: note}), do: "an edit by #{author}: #{note}"

  # -- the replay log ----------------------------------------------------------------

  defp log(kind, package, batch, edit) do
    payload =
      if kind == :fact_edit,
        do: %{"value" => StableRef.encode_decision(edit.value), "note" => edit.note},
        else: %{}

    ReplayLog.append!(kind, key(package, batch, edit), payload)
  end

  defp key(package, batch, edit) do
    %{
      "package" => package.key,
      "batch_id" => batch.producer_batch_id,
      "statement_ref" => edit.statement_ref,
      "kind" => Atom.to_string(edit.kind)
    }
  end

  @doc """
  Replays a `:fact_edit` or `:fact_edit_removed` entry (`key`, `payload`)
  on `package` (ready: resolved), as `actor`. Done already (a replay run
  again): an edit the batch holds with that value and note, a removal of
  an edit that is not there, and either once the batch is applied or
  denied.
  """
  @spec replay(Actor.t(), Package.t(), :fact_edit | :fact_edit_removed, map(), map()) ::
          :ok | {:error, term()}
  def replay(actor, package, kind, key, payload) do
    with {:ok, batch} <- batch(package, key["batch_id"]) do
      case kind do
        # Its batch applied or denied, an edit has done its part (or can't).
        _kind when batch.status in [:applied, :denied] ->
          :ok

        :fact_edit ->
          with {:ok, value} <- StableRef.decode_decision(payload["value"] || %{}) do
            input = input(key, value, payload)

            if held?(batch, key["statement_ref"], input) do
              :ok
            else
              with {:ok, _edit} <- edit(actor, package, batch, key["statement_ref"], input),
                   do: :ok
            end
          end

        :fact_edit_removed ->
          kind = String.to_existing_atom(key["kind"])

          case Repo.get_by(StatementEdit,
                 batch_id: batch.id,
                 statement_ref: key["statement_ref"],
                 kind: kind
               ) do
            nil -> :ok
            stored -> with {:ok, _} <- remove(actor, stored), do: :ok
          end
      end
    end
  end

  # Whether the batch holds the edit already, with that value and note.
  defp held?(batch, ref, input) do
    with {:ok, kind, value, note} <- parse(input),
         %StatementEdit{value: ^value, note: ^note} <-
           Repo.get_by(StatementEdit, batch_id: batch.id, statement_ref: ref, kind: kind) do
      true
    else
      _ -> false
    end
  end

  defp batch(package, producer_batch_id) do
    case Repo.get_by(Batch, package_id: package.id, producer_batch_id: producer_batch_id) do
      nil -> {:error, {:no_batch, producer_batch_id}}
      batch -> {:ok, batch}
    end
  end

  # The edit as `edit/5` takes it, from its kind, value and note.
  defp input(%{"kind" => kind}, value, payload) do
    base =
      case kind do
        "drop" -> %{"drop" => true}
        "note" -> %{}
        _ -> value
      end

    if payload["note"], do: Map.put(base, "note", payload["note"]), else: base
  end
end
