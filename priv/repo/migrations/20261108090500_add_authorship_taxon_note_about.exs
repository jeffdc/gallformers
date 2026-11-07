defmodule Gallformers.Repo.Migrations.AddAuthorshipTaxonNoteAbout do
  @moduledoc """
  A plant's authorship is an editorial field of its own (matter `f14c`,
  "Other decisions": plants get their authorship from WCVP, a curator may
  still change it), so a "based on" note may be about it
  (`Gallformers.Taxa.TaxonNote`).
  """
  use Ecto.Migration

  def up do
    drop constraint(:taxon_notes, :taxon_notes_about_check)

    create constraint(:taxon_notes, :taxon_notes_about_check,
             check: "about IN ('name', 'authorship', 'synonyms', 'range')"
           )
  end

  def down do
    drop constraint(:taxon_notes, :taxon_notes_about_check)

    create constraint(:taxon_notes, :taxon_notes_about_check,
             check: "about IN ('name', 'synonyms', 'range')"
           )
  end
end
