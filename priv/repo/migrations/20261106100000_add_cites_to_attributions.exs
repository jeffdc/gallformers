defmodule Gallformers.Repo.Migrations.AddCitesToAttributions do
  @moduledoc """
  A Gallformers statement may cite the Source the curator follows (matter
  `ec2c`, curation: "per Weld 1959"; `cites` on `statement_evidence` in
  `priv/import/schema/common.schema.json`). The attribution records it:
  `cites_as_written`, the Source as the curator named it, and
  `cited_source_id`, that Source when Gallformers holds it (nilified if the
  Source is deleted; the words stay). Quote evidence keeps its own `cites`
  on `attribution_evidence.cites_as_written`.
  """
  use Ecto.Migration

  def change do
    alter table(:attributions) do
      add :cites_as_written, :text
      add :cited_source_id, references(:source, on_delete: :nilify_all)
    end

    create index(:attributions, [:cited_source_id], where: "cited_source_id IS NOT NULL")
  end
end
