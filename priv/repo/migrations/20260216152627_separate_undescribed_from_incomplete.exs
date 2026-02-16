defmodule Gallformers.Repo.Migrations.SeparateUndescribedFromIncomplete do
  @moduledoc """
  Data migration: separates undescribed status from data completeness.

  1. Populates gallformers_code from species name epithets (dashed codes only)
  2. Populates gallformers_code from any former_undescribed aliases (defensive)
  3. Fixes mislabeled undescribed flags
  4. Enforces datacomplete rules (requires sources, prohibits undescribed)
  5. Converts former_undescribed aliases to scientific
  """
  use Gallformers.Migration

  import Ecto.Query

  alias Gallformers.Taxonomy.TaxonName

  # Legitimate described species whose epithets contain dashes — do NOT assign codes.
  # 2747/5443 share an epithet and are handled in step 1b (disambiguation) — they are
  # undescribed and must NOT appear here, since step 3b uses this list to clear undescribed.
  @exclusions MapSet.new([
    633, 778, 1005, 1339, 1340, 1373, 1906, 1996, 2255, 2688,
    3167, 3346, 3979, 3981, 3992, 4089, 4092, 4603, 4614, 4792,
    5027, 5578, 5645
  ])

  # Species that need code disambiguation — skipped by step 1, handled by step 1b
  @disambiguated MapSet.new([2747, 5443])

  def up do
    # ---------------------------------------------------------------
    # 1. Populate gallformers_code from species name epithets
    # ---------------------------------------------------------------
    gall_species =
      repo().all(
        from(s in "species",
          where: s.taxoncode == "gall",
          select: %{id: s.id, name: s.name}
        )
      )

    for %{id: id, name: name} <- gall_species,
        id not in @exclusions and id not in @disambiguated,
        parsed = TaxonName.parse(name),
        epithet = parsed.epithet,
        epithet != nil,
        String.contains?(epithet, "-") do
      repo().update_all(
        from(gt in "gall_traits", where: gt.species_id == ^id),
        set: [gallformers_code: epithet]
      )
    end

    # 1b. Disambiguate duplicate epithet pair: 2747/5443 share "c-americana-enlarged-bud-gall"
    repo().update_all(
      from(gt in "gall_traits", where: gt.species_id == 2747),
      set: [gallformers_code: "c-americana-enlarged-bud-gall-contarinia"]
    )

    repo().update_all(
      from(gt in "gall_traits", where: gt.species_id == 5443),
      set: [gallformers_code: "c-americana-enlarged-bud-gall-dasineura"]
    )

    # ---------------------------------------------------------------
    # 2. Populate gallformers_code from former_undescribed aliases
    #    (defensive — handles any created between audit and migration)
    # ---------------------------------------------------------------
    former_aliases =
      repo().all(
        from(a in "alias",
          join: als in "alias_species",
          on: als.alias_id == a.id,
          where: a.type == "former_undescribed",
          select: %{species_id: als.species_id, alias_name: a.name}
        )
      )

    for %{species_id: sid, alias_name: alias_name} <- former_aliases do
      # Only set if not already populated by step 1
      existing =
        repo().one(
          from(gt in "gall_traits",
            where: gt.species_id == ^sid,
            select: gt.gallformers_code
          )
        )

      if existing in [nil, ""] do
        parsed = TaxonName.parse(alias_name)
        code = parsed.epithet

        if code do
          repo().update_all(
            from(gt in "gall_traits", where: gt.species_id == ^sid),
            set: [gallformers_code: code]
          )
        end
      end
    end

    # ---------------------------------------------------------------
    # 3. Fix undescribed flags
    # ---------------------------------------------------------------

    # 3a. ID 2235 → set undescribed = true
    repo().update_all(
      from(gt in "gall_traits", where: gt.species_id == 2235),
      set: [undescribed: 1]
    )

    # 3b. Undescribed galls with real genus and no dashes → set undescribed = false
    undescribed_with_real_genus =
      repo().all(
        from(s in "species",
          join: gt in "gall_traits",
          on: gt.species_id == s.id,
          join: st in "species_taxonomy",
          on: st.species_id == s.id,
          join: t in "taxonomy",
          on: t.id == st.taxonomy_id and t.type == "genus",
          where: s.taxoncode == "gall",
          where: gt.undescribed == 1,
          where: not like(t.name, "Unknown%"),
          select: %{id: s.id, name: s.name}
        )
      )

    for %{id: id, name: name} <- undescribed_with_real_genus do
      parsed = TaxonName.parse(name)
      epithet = parsed.epithet

      # Clear undescribed if epithet has no dashes (not a gallformers code)
      # OR if the species is in the exclusion list (known described with legitimate hyphens)
      if (epithet && not String.contains?(epithet, "-")) || id in @exclusions do
        repo().update_all(
          from(gt in "gall_traits", where: gt.species_id == ^id),
          set: [undescribed: 0]
        )
      end
    end

    # 3c. All galls under Unknown genera → ensure undescribed = true
    repo().update_all(
      from(gt in "gall_traits",
        join: st in "species_taxonomy",
        on: st.species_id == gt.species_id,
        join: t in "taxonomy",
        on: t.id == st.taxonomy_id and t.type == "genus",
        where: like(t.name, "Unknown%")
      ),
      set: [undescribed: 1]
    )

    # ---------------------------------------------------------------
    # 4. Fix datacomplete
    # ---------------------------------------------------------------

    # 4a. All galls without sources → set datacomplete = false
    repo().update_all(
      from(s in "species",
        where: s.taxoncode == "gall",
        where: s.datacomplete == 1,
        where:
          s.id not in subquery(
            from(ss in "species_source", distinct: true, select: ss.species_id)
          )
      ),
      set: [datacomplete: 0]
    )

    # 4b. All undescribed galls → set datacomplete = false
    repo().update_all(
      from(s in "species",
        join: gt in "gall_traits",
        on: gt.species_id == s.id,
        where: s.taxoncode == "gall",
        where: gt.undescribed == 1,
        where: s.datacomplete == 1
      ),
      set: [datacomplete: 0]
    )

    # ---------------------------------------------------------------
    # 5. Convert former_undescribed aliases to scientific
    # ---------------------------------------------------------------
    repo().update_all(
      from(a in "alias", where: a.type == "former_undescribed"),
      set: [type: "scientific"]
    )
  end

  def down do
    # Data migration — not reversible. The old state can be restored from backup.
    :ok
  end
end
