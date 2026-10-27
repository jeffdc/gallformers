defmodule Gallformers.Catalog.GallRenames do
  @moduledoc """
  The Catalog's side of rename proposals (`86e7` §3): which Galls' derived
  names a taxonomy change changes, and applying an accepted rename. The
  proposals themselves are admin queue items, kept by `Gallformers.Import`
  (`Gallformers.Import.GallRenames`), which hears the same "taxon changed"
  events after `Gallformers.Catalog.TaxonListener`.

  ## Which Galls a change touches

  A Gall's name follows its Inducer's accepted name (species rank and
  below), its Inducer's genus or family (an undescribed Gall's, with a
  descriptor) and its Host qualifier's accepted name
  (`Gallformers.Catalog.GallName`). Taxa never rename a taxon's
  descendants, so:

    * a **rename** touches the Galls whose current Inducer is the taxon, or
      is under it with a descriptor (a renamed genus or family), and the
      Galls whose Host qualifier is the taxon;
    * a **move** touches the Galls with a descriptor whose current Inducer
      is in the moved subtree (an "Unknown (Family)" Gall whose family
      changes; a subgenus or section carried to another genus).

  Of those, Galls with a name override (their name shown doesn't change)
  and Galls whose parts give no name are left out; the rest are listed
  with the name their parts give now, whether or not it changed.
  """
  import Ecto.Query, only: [from: 2, dynamic: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog.Assert
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.GallName
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Event

  @typedoc """
  A Gall a taxonomy change touches: its stored name (`from`), the name its
  parts give now (`to`), and whether `to` is another Gall's name shown,
  ignoring case (`collision`).
  """
  @type change :: %{
          gall_id: integer(),
          from: String.t(),
          to: String.t(),
          collision: boolean()
        }

  @typedoc "Why an accepted rename can't be applied."
  @type accept_error ::
          :collision
          | :overridden
          | :no_gallformers_source
          | {:not_derivable, GallName.error() | :several_inducers}
          | Ecto.Changeset.t()

  @doc "The Galls without an override whose derived name `event` may change, as `t:change/0`s."
  @spec name_changes(Event.t()) :: [change()]
  def name_changes(%Event{type: type, taxon_id: taxon_id}) when type in [:move, :rename] do
    gall_ids = candidates(type, taxon_id)

    galls =
      Repo.all(
        from(g in Gall, where: g.id in ^gall_ids and is_nil(g.name_override), order_by: g.id)
      )

    for gall <- galls, {:ok, to} <- [GallName.for_gall(gall)] do
      %{
        gall_id: gall.id,
        from: gall.name,
        to: to,
        collision: to != gall.name and name_taken_by_other?(to, gall.id)
      }
    end
  end

  def name_changes(%Event{}), do: []

  defp candidates(type, taxon_id) do
    subtree = [taxon_id] |> Taxa.subtree_ids() |> Map.get(taxon_id, [taxon_id])

    # A species-rank Inducer's name follows no ancestor: only a renamed
    # Inducer itself, or a descriptor-named Gall, can change.
    touched =
      if type == :rename,
        do: dynamic([r, gall: g], not is_nil(g.descriptor) or r.subject_taxon_id == ^taxon_id),
        else: dynamic([gall: g], not is_nil(g.descriptor))

    by_inducer =
      from(r in Current.relationships("inducer_of"),
        join: g in Gall,
        as: :gall,
        on: g.id == r.object_gall_id,
        where: r.subject_taxon_id in ^subtree,
        where: ^touched,
        select: g.id
      )

    by_host =
      if type == :rename,
        do:
          Repo.all(from(g in Gall, where: g.host_qualifier_taxon_id == ^taxon_id, select: g.id)),
        else: []

    Enum.uniq(Repo.all(by_inducer) ++ by_host)
  end

  # Whether a Gall other than `gall_id` shows `name`, ignoring case.
  defp name_taken_by_other?(name, gall_id) do
    Repo.exists?(
      from(g in Gall,
        where:
          g.id != ^gall_id and
            fragment("lower(COALESCE(?, ?))", g.name_override, g.name) ==
              fragment("lower(?)", ^name)
      )
    )
  end

  @doc """
  Applies an accepted rename proposal to Gall `gall_id`: its `name` becomes
  the name its parts give now, and the name it showed before becomes an
  alias Fact (`kind: :former_label`) stated by the Gallformers Source today.
  The Gallformers code is never touched. The ID tool's lookup table row is
  refreshed.

  Refused (nothing changes) when the new name is another Gall's name shown
  (`:collision`), the Gall has a name override (`:overridden`), its parts
  give no name (`{:not_derivable, reason}`), or there is no Gallformers
  Source. When the parts give the name it already has, nothing changes.
  Returns the Gall with the name shown before (`from`) and after (`to`).
  """
  @spec accept(Actor.t(), integer()) ::
          {:ok, %{gall: Gall.t(), from: String.t(), to: String.t()}}
          | {:error, accept_error()}
  def accept(%Actor{} = actor, gall_id) when is_integer(gall_id) do
    Audit.transaction(actor, "catalog.accept_gall_rename", fn ->
      gall = Repo.one!(from(g in Gall, where: g.id == ^gall_id, lock: "FOR UPDATE"))
      if gall.name_override, do: Repo.rollback(:overridden)

      case GallName.for_gall(gall) do
        {:error, reason} -> Repo.rollback({:not_derivable, reason})
        {:ok, same} when same == gall.name -> %{gall: gall, from: gall.name, to: same}
        {:ok, to} -> rename(actor, gall, to)
      end
    end)
  end

  defp rename(actor, gall, to) do
    if name_taken_by_other?(to, gall.id), do: Repo.rollback(:collision)
    gallformers = Sources.get_gallformers_source() || Repo.rollback(:no_gallformers_source)
    from = Gall.display_name(gall)

    renamed = gall |> Gall.rename_changeset(to) |> Repo.update() |> ok_or_rollback()

    if String.downcase(from) != String.downcase(to) do
      Assert.assert(
        AliasFact,
        actor,
        %{gall_id: gall.id, name: from, kind: :former_label},
        %{
          source_id: gallformers.id,
          stance: :confirm,
          stated: Date.to_iso8601(Date.utc_today()),
          statement_text:
            "The Gall's name until a taxonomy change renamed it \"#{to}\" (rename accepted)."
        }
      )
      |> ok_or_rollback()
    end

    :ok = GallIndex.enqueue_refresh([gall.id])
    %{gall: renamed, from: from, to: to}
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
