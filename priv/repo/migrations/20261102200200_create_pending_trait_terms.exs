defmodule Gallformers.Repo.Migrations.CreatePendingTraitTerms do
  @moduledoc """
  Terms waiting on a question (matter d213, Task A): `pending_trait_terms`
  holds a Source's Trait term on a Gall that has no Fact yet — an
  ambiguous term's use, a disagreement between the readers, or a new term
  they didn't agree on (`Gallformers.Catalog.PendingTraitTerm`). It is
  shown on the Gall's page, not in the ID tool, and holds nothing.

  Each keeps its origin (the Source, package, batch and statement, the
  quotes, and the queue item asking about it) and, once a curator's
  decision settles it, when, and the category it was settled under (none
  when kept as text). One per Gall, Source, Trait and normalized term.

  Audited: waiting terms are curated state.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @traits ~w(detachable plant_part form shape color texture alignment walls cells season)

  def up do
    create table(:pending_trait_terms) do
      add :gall_id, references(:galls, on_delete: :delete_all), null: false
      add :source_id, references(:source, on_delete: :restrict), null: false
      add :package_id, references(:import_packages, on_delete: :restrict), null: false
      add :batch_id, references(:import_batches, on_delete: :restrict), null: false
      add :queue_item_id, references(:queue_items, on_delete: :nilify_all)
      # The batch statement the term comes from (its ref), where it has one.
      add :statement_ref, :text
      add :trait, :text, null: false
      # The term as written, and as compared (lowercased, whitespace collapsed).
      add :term, :text, null: false
      add :normalized_term, :text, null: false
      # The quotes: `[%{"item", "quote", ...}]`, as the batch gives them.
      add :evidence, :jsonb, null: false, default: "[]"
      add :settled_at, :utc_datetime
      add :settled_category, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pending_trait_terms, [:gall_id, :source_id, :trait, :normalized_term])
    create index(:pending_trait_terms, [:trait, :normalized_term])
    create index(:pending_trait_terms, [:source_id])
    create index(:pending_trait_terms, [:batch_id])
    create index(:pending_trait_terms, [:queue_item_id])

    create constraint(:pending_trait_terms, :pending_trait_terms_trait_check,
             check: "trait IN (#{list(@traits)})"
           )

    create constraint(:pending_trait_terms, :pending_trait_terms_term_present,
             check: "btrim(term) <> '' AND normalized_term <> ''"
           )

    create constraint(:pending_trait_terms, :pending_trait_terms_settled_check,
             check: "settled_category IS NULL OR settled_at IS NOT NULL"
           )

    Audit.track_table("pending_trait_terms")
  end

  def down do
    Audit.untrack_table("pending_trait_terms")
    drop table(:pending_trait_terms)
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
