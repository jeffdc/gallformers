defmodule Gallformers.Repo.Migrations.AddKindToAliasFacts do
  @moduledoc """
  Adds `alias_facts.kind` (`9449` §4; `803b` decision 4, Jeff 2026-10-26):
  what a gall alias is — `common_name`, `former_label` (a Gallformers label
  the Gall had before) or `code` (an informal code). Existing rows are
  common names. A property of the Fact, not part of its natural key (Gall +
  name).
  """
  use Ecto.Migration

  def up do
    alter table(:alias_facts) do
      add :kind, :text, null: false, default: "common_name"
    end

    create constraint(:alias_facts, :alias_facts_kind_check,
             check: "kind IN ('common_name', 'former_label', 'code')"
           )
  end

  def down do
    drop constraint(:alias_facts, :alias_facts_kind_check)

    alter table(:alias_facts) do
      remove :kind
    end
  end
end
