defmodule Gallformers.Repo.Migrations.AddSettledAsToPendingTraitTerms do
  @moduledoc """
  Why a Source's term was settled (matter `d213`, Jeff 2026-11-02): under a
  category, as text because the term fits no category (`no_fit`), or as text
  because a curator chose to keep it so for that Gall (`kept`). Placing a
  term that fit no category later turns its `no_fit` uses into Facts; a
  curator's `kept` choice stands.
  """
  use Ecto.Migration

  def up do
    alter table(:pending_trait_terms) do
      add :settled_as, :text
    end

    # Rows settled before this column: under a category, or as text whose
    # reason wasn't recorded (local rehearsal data only), taken as `no_fit`.
    execute """
    UPDATE pending_trait_terms
    SET settled_as = CASE WHEN settled_category IS NULL THEN 'no_fit' ELSE 'category' END
    WHERE settled_at IS NOT NULL
    """

    create constraint(:pending_trait_terms, :pending_trait_terms_settled_as_check,
             check: """
             (settled_at IS NULL AND settled_as IS NULL)
             OR (settled_at IS NOT NULL AND settled_category IS NOT NULL AND settled_as = 'category')
             OR (settled_at IS NOT NULL AND settled_category IS NULL AND settled_as IN ('no_fit', 'kept'))
             """
           )
  end

  def down do
    drop constraint(:pending_trait_terms, :pending_trait_terms_settled_as_check)

    alter table(:pending_trait_terms) do
      remove :settled_as
    end
  end
end
