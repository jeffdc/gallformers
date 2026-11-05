defmodule Gallformers.Repo.Migrations.CreateTraitTermCandidates do
  @moduledoc """
  Seeding the term table (matter d213, Task F): `trait_term_candidates`
  holds the Sources' Trait terms gathered from producer packages
  (`mix gallformers.import.term_candidates`) for a superadmin to rule on
  before go-live (`Gallformers.Import.TermCandidate`).

  One row per Trait and normalized term: the term as most often written,
  how many uses it has, each package's count of uses per suggested
  category (`counts_by_source`, so gathering a package again replaces its
  counts), the categories suggested with their counts, a few example uses
  (Source, Gall, category, quote), and, once decided, the decision, who
  and when. The decision itself is a term edit, recorded for replay; this
  table only says which candidates are done.

  Audited: candidates' decisions are curated state.
  """
  use Ecto.Migration

  alias Gallformers.Audit.Migration, as: Audit

  @traits ~w(detachable plant_part form shape color texture alignment walls cells season)

  def up do
    create table(:trait_term_candidates) do
      add :trait, :text, null: false
      # The term as most often written, and as compared (lowercased, whitespace collapsed).
      add :term, :text, null: false
      add :normalized_term, :text, null: false
      # `%{package => %{"uses", "suggestions" => [%{"category", "count"}]}}`;
      # a category of null is a term set aside, or none suggested.
      add :counts_by_source, :jsonb, null: false, default: "{}"
      # `[%{"category", "count"}]`, most first: the packages' counts summed.
      add :suggestions, :jsonb, null: false, default: "[]"
      # `[%{"source", "gall", "category", "quote"}]`: a few example uses.
      add :uses, :jsonb, null: false, default: "[]"
      add :total, :integer, null: false, default: 0
      # `%{"place" => c}`, `%{"ambiguous" => [c]}` or `%{"no_fit" => true}`.
      add :decision, :jsonb
      add :decided_at, :utc_datetime
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :decided_by_name, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:trait_term_candidates, [:trait, :normalized_term])

    create constraint(:trait_term_candidates, :trait_term_candidates_trait_check,
             check: "trait IN (#{list(@traits)})"
           )

    create constraint(:trait_term_candidates, :trait_term_candidates_term_present,
             check: "btrim(term) <> '' AND normalized_term <> ''"
           )

    create constraint(:trait_term_candidates, :trait_term_candidates_decided_check,
             check:
               "(decision IS NULL AND decided_at IS NULL) OR " <>
                 "(decision IS NOT NULL AND decided_at IS NOT NULL AND decided_by_name IS NOT NULL)"
           )

    Audit.track_table("trait_term_candidates")
  end

  def down do
    Audit.untrack_table("trait_term_candidates")
    drop table(:trait_term_candidates)
  end

  defp list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
