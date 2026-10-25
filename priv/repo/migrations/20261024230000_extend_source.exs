defmodule Gallformers.Repo.Migrations.ExtendSource do
  @moduledoc """
  Extends `source` in place with the new back-end's descriptive fields
  (`9449` §2): kind, authors as written, the authored date with its precision,
  identifiers, the license as a value and as written, and retraction.

  The existing columns stay, because today's code still reads and writes
  them. `source` is not audited: the old admin pages write it outside
  `Gallformers.Audit`.

  `kind` is nullable for now: existing Sources have none until they are
  classified. Source 58 (Gallformers Notes) becomes the one `gallformers`
  Source; databases without that row (the test database) are left as they are.
  """
  use Ecto.Migration

  @kinds ~w(publication website database unpublished research_data gallformers)

  def up do
    alter table(:source) do
      add :kind, :text
      add :authors, {:array, :text}, null: false, default: []
      add :authored_date, :date
      add :authored_precision, :text
      add :authored_as_written, :text
      add :doi, :text
      add :url, :text
      add :isbn, :text
      add :license_value, :text
      add :license_as_written, :text
      add :retracted_by_id, references(:source, on_delete: :restrict)
      add :retracted_on, :date
    end

    create constraint(:source, :source_kind_check,
             check: "kind IS NULL OR kind IN (#{Enum.map_join(@kinds, ", ", &"'#{&1}'")})"
           )

    create constraint(:source, :source_authored_precision_check,
             check: "authored_precision IS NULL OR authored_precision IN ('year', 'month', 'day')"
           )

    # A date always has its precision, and a partial date is stored as its
    # first day (1897 -> 1897-01-01, 1897-05 -> 1897-05-01).
    create constraint(:source, :source_authored_date_precision,
             check: """
             (authored_date IS NULL) = (authored_precision IS NULL)
             AND (authored_precision IS DISTINCT FROM 'month'
                  OR EXTRACT(DAY FROM authored_date) = 1)
             AND (authored_precision IS DISTINCT FROM 'year'
                  OR (EXTRACT(MONTH FROM authored_date) = 1
                      AND EXTRACT(DAY FROM authored_date) = 1))
             """
           )

    create constraint(:source, :source_retraction_complete,
             check: "(retracted_by_id IS NULL) = (retracted_on IS NULL)"
           )

    create constraint(:source, :source_not_self_retracted, check: "retracted_by_id <> id")

    create index(:source, [:retracted_by_id])

    create unique_index(:source, [:kind],
             where: "kind = 'gallformers'",
             name: :source_one_gallformers
           )

    execute("UPDATE source SET kind = 'gallformers' WHERE id = 58")
  end

  def down do
    drop index(:source, [:kind], name: :source_one_gallformers)
    drop index(:source, [:retracted_by_id])
    drop constraint(:source, :source_not_self_retracted)
    drop constraint(:source, :source_retraction_complete)
    drop constraint(:source, :source_authored_date_precision)
    drop constraint(:source, :source_authored_precision_check)
    drop constraint(:source, :source_kind_check)

    alter table(:source) do
      remove :retracted_on
      remove :retracted_by_id
      remove :license_as_written
      remove :license_value
      remove :isbn
      remove :url
      remove :doi
      remove :authored_as_written
      remove :authored_precision
      remove :authored_date
      remove :authors
      remove :kind
    end
  end
end
