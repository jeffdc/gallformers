defmodule Gallformers.Repo.Migrations.CreateRecordRedirects do
  @moduledoc """
  Deletes and merges (matter `ec2c`, "Deletes"):

    * `gall_redirects` — a Gall merged into another (`Gallformers.Import.record_merge/2`)
      leaves its ID, and its Gallformers code, redirecting to the surviving
      Gall (`Gallformers.Catalog.gall_redirect/1`), so iNat links and outside
      references keep working. A redirect goes with the Gall it points to
      (`ON DELETE CASCADE`); merging that Gall in turn re-points it.
    * `taxon_redirects` — the same for a plant merged into another
      (`Gallformers.Taxa.taxon_redirect/1`).
    * `replay_log.kind` gains `deletion` and `merge`, so deletes and merges
      made on preview are replayed after the cutover data migration.
    * `queue_items`: a same-date conflict a merge brings about
      (`:same_date_conflict`) comes from no package, as a rename proposal
      does.

  The redirects are audited, and public: the public pages' redirects read
  them. The kind check is rebuilt from the kinds it allows now plus these,
  so kinds other migrations add are kept whatever order they run in.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @kinds ["deletion", "merge"]

  def up do
    create table(:gall_redirects, primary_key: false) do
      add :from_gall_id, :bigint, primary_key: true
      add :from_code, :text
      add :gall_id, references(:galls, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:gall_redirects, [:from_code], where: "from_code IS NOT NULL")
    create index(:gall_redirects, [:gall_id])
    Audit.track_table("gall_redirects", primary_key_columns: ["from_gall_id"])

    create table(:taxon_redirects, primary_key: false) do
      add :from_taxon_id, :bigint, primary_key: true
      add :taxon_id, references(:taxa, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:taxon_redirects, [:taxon_id])
    Audit.track_table("taxon_redirects", primary_key_columns: ["from_taxon_id"])

    replace_kind_check(Enum.uniq(current_kinds() ++ @kinds))

    drop constraint(:queue_items, :queue_items_package_check)

    create constraint(:queue_items, :queue_items_package_check,
             check:
               "(kind = 'gall_rename' AND package_id IS NULL) OR " <>
                 "(kind <> 'gall_rename' AND (package_id IS NOT NULL OR kind = 'same_date_conflict'))"
           )
  end

  def down do
    # Audited tables: the deletions are recorded as this migration.
    Carbonite.Migrations.insert_migration_transaction("drop_record_redirects")
    execute "DELETE FROM queue_items WHERE kind = 'same_date_conflict' AND package_id IS NULL"

    drop constraint(:queue_items, :queue_items_package_check)

    create constraint(:queue_items, :queue_items_package_check,
             check: "(package_id IS NULL) = (kind = 'gall_rename')"
           )

    execute "DELETE FROM replay_log WHERE kind IN (#{list(@kinds)})"
    replace_kind_check(current_kinds() -- @kinds)

    Audit.untrack_table("taxon_redirects")
    drop table(:taxon_redirects)
    Audit.untrack_table("gall_redirects")
    drop table(:gall_redirects)
  end

  defp current_kinds do
    %{rows: [[definition]]} =
      repo().query!(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'replay_log_kind_check'"
      )

    Regex.scan(~r/'([a-z_]+)'/, definition, capture: :all_but_first) |> List.flatten()
  end

  defp replace_kind_check(kinds) do
    drop constraint(:replay_log, :replay_log_kind_check)
    create constraint(:replay_log, :replay_log_kind_check, check: "kind IN (#{list(kinds)})")
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
