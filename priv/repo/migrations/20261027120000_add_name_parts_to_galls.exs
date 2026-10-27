defmodule Gallformers.Repo.Migrations.AddNamePartsToGalls do
  @moduledoc """
  A Gall's name parts (`86e7` Task 1): the stored qualifiers its name is
  derived from (`Gallformers.Catalog.GallName`), besides its Inducer (a
  Fact) and its generation (`generation_value_id`):

    * `host_qualifier_taxon_id` — a Host taxon, rendered "(on Quercus
      douglasii)". A foreign key to `taxa`, as `relationship_facts`' taxon
      columns are.
    * `form_label` — free text, rendered "(australis)", "(bud)".
    * `descriptor` — an undescribed Gall's descriptor, e.g.
      `q-havardii-cup-gall`.

  The name shown (`COALESCE(name_override, name)`) becomes unique ignoring
  case: `galls_display_name_index` is rebuilt on its lower-cased value.

  `galls` is audited; its Carbonite trigger records every column, so the new
  columns need nothing more.
  """
  use Ecto.Migration

  def up do
    alter table(:galls) do
      add :host_qualifier_taxon_id, references(:taxa, on_delete: :restrict)
      add :form_label, :text
      add :descriptor, :text
    end

    create index(:galls, [:host_qualifier_taxon_id])

    create constraint(:galls, :galls_form_label_present,
             check: "form_label IS NULL OR form_label <> ''"
           )

    create constraint(:galls, :galls_descriptor_present,
             check: "descriptor IS NULL OR descriptor <> ''"
           )

    drop index(:galls, [], name: :galls_display_name_index)

    create unique_index(:galls, ["lower(COALESCE(name_override, name))"],
             name: :galls_display_name_index
           )
  end

  def down do
    drop index(:galls, [], name: :galls_display_name_index)
    create unique_index(:galls, ["COALESCE(name_override, name)"], name: :galls_display_name_index)

    drop constraint(:galls, :galls_descriptor_present)
    drop constraint(:galls, :galls_form_label_present)
    drop index(:galls, [:host_qualifier_taxon_id])

    alter table(:galls) do
      remove :descriptor
      remove :form_label
      remove :host_qualifier_taxon_id
    end
  end
end
