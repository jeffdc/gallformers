defmodule Gallformers.Repo.Migrations.CreateFacts do
  @moduledoc """
  Creates the Facts tables (`9449` §2): `facts`, `attributions`,
  `attribution_evidence`, `attribution_names` and `attribution_observations`.
  All are audited.

  A Fact's typed details live in tables owned by `Catalog` and `Taxa`, keyed
  by `fact_id`; those arrive with their own tasks. `standing` is precomputed
  by `Gallformers.Facts` whenever a Fact's attributions change.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @standings ~w(current withdrawn superseded retracted unsupported)
  @providers ~w(inaturalist bugguide other)

  def up do
    create table(:facts) do
      add :kind, :text, null: false
      add :standing, :text, null: false, default: "unsupported"
      # Facts competing for one value share a slot, e.g. "gall:123:detachable".
      add :slot, :text

      timestamps(type: :utc_datetime)
    end

    create constraint(:facts, :facts_standing_check, check: "standing IN (#{list(@standings)})")
    create constraint(:facts, :facts_kind_present, check: "kind <> ''")
    create index(:facts, [:slot], where: "slot IS NOT NULL")

    Audit.track_table("facts")

    create table(:attributions) do
      add :fact_id, references(:facts, on_delete: :restrict), null: false
      add :source_id, references(:source, on_delete: :restrict), null: false
      add :stance, :text, null: false
      # The Source's authored date, or a Gallformers statement's own date, as
      # a partial date (first day of its period plus precision). Null for
      # undated legacy statements.
      add :stated_on, :date
      add :stated_precision, :text
      add :value_as_written, :text
      # The import batch that last wrote this attribution. Task 11 (`9449`)
      # adds the foreign key to `import_batches` when that table exists.
      add :batch_id, :bigint
      # Gallformers' own statement (Gallformers attributions only).
      add :statement_text, :text
      # Occurrences: when and at what stage, as the Source writes them.
      add :when_as_written, :text
      add :stage_as_written, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:attributions, [:fact_id, :source_id])
    create index(:attributions, [:source_id])
    create index(:attributions, [:batch_id], where: "batch_id IS NOT NULL")

    create constraint(:attributions, :attributions_stance_check,
             check: "stance IN ('confirm', 'deny')"
           )

    create constraint(:attributions, :attributions_stated_precision_check,
             check: "stated_precision IS NULL OR stated_precision IN ('year', 'month', 'day')"
           )

    create constraint(:attributions, :attributions_stated_date_precision,
             check: """
             (stated_on IS NULL) = (stated_precision IS NULL)
             AND (stated_precision IS DISTINCT FROM 'month' OR EXTRACT(DAY FROM stated_on) = 1)
             AND (stated_precision IS DISTINCT FROM 'year'
                  OR (EXTRACT(MONTH FROM stated_on) = 1 AND EXTRACT(DAY FROM stated_on) = 1))
             """
           )

    Audit.track_table("attributions")

    create table(:attribution_evidence) do
      add :attribution_id, references(:attributions, on_delete: :delete_all), null: false
      # The stored document item quoted. Null for a quote from a Source with
      # no stored document.
      add :document_item_id, references(:document_items, on_delete: :restrict)
      add :quote, :text
      # Where the quote is in the item's text, in codepoints
      # (`Gallformers.Sources.QuoteLocator`); computed by Gallformers.
      add :span_start, :integer
      add :span_length, :integer
      # The page as printed in the Source (the PDF page is the item's).
      add :page, :text
      add :url, :text
      add :whole_item, :boolean, null: false, default: false
      # The work the Source cites for this statement, as written.
      add :cites_as_written, :text
    end

    create index(:attribution_evidence, [:attribution_id])
    create index(:attribution_evidence, [:document_item_id])

    create constraint(:attribution_evidence, :attribution_evidence_quote_or_whole_item,
             check: """
             (whole_item AND document_item_id IS NOT NULL AND quote IS NULL)
             OR (NOT whole_item AND quote IS NOT NULL AND quote <> '')
             """
           )

    create constraint(:attribution_evidence, :attribution_evidence_span,
             check: """
             (span_start IS NULL) = (span_length IS NULL)
             AND (span_start IS NOT NULL) = (document_item_id IS NOT NULL AND quote IS NOT NULL)
             AND (span_start IS NULL OR (span_start >= 0 AND span_length > 0))
             """
           )

    Audit.track_table("attribution_evidence")

    create table(:attribution_names) do
      add :attribution_id, references(:attributions, on_delete: :delete_all), null: false
      # The taxon the name resolved to. Task 5 (`9449`) adds the foreign key
      # to `taxa` when that table exists.
      add :taxon_id, :bigint, null: false
      add :name_as_written, :text, null: false
      # The evident printed name where the text of it is damaged (OCR).
      add :name_reading, :text
      # The part the taxon plays in the Fact, e.g. "subject", "object", "inducer".
      add :role, :text, null: false
    end

    create index(:attribution_names, [:attribution_id])
    create index(:attribution_names, [:taxon_id])

    Audit.track_table("attribution_names")

    create table(:attribution_observations) do
      add :attribution_id, references(:attributions, on_delete: :delete_all), null: false
      add :provider, :text, null: false
      add :external_id, :text, null: false
      add :url, :text
    end

    create unique_index(:attribution_observations, [:attribution_id, :provider, :external_id])

    create constraint(:attribution_observations, :attribution_observations_provider_check,
             check: "provider IN (#{list(@providers)})"
           )

    Audit.track_table("attribution_observations")
  end

  def down do
    for table <- ~w(attribution_observations attribution_names attribution_evidence attributions facts) do
      Audit.untrack_table(table)
      drop table(table)
    end
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
