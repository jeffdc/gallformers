defmodule Gallformers.Repo.Migrations.NormalizeGenusPlaceholders do
  @moduledoc """
  Data migration that normalizes `[Genus] sp` / `[Genus] spp` placeholder host
  records.

  Steps (in order, all idempotent):

  1. **Dedup known duplicate genera** — for `Cardamine`, `Lonicera`, `Solidago`,
     and `Symphoricarpos`, both a `[Genus] sp` and `[Genus] spp` placeholder
     exist. The `spp` variant is the survivor; the `sp` row is the loser.
     - Re-point `gallhost.host_species_id` from loser → survivor; skip rows
       that would collide on the `(gall_species_id, host_species_id)` unique
       index.
     - Move aliases not already present on the survivor.
     - Move other FK references (image, species_source, host_traits,
       host_range, species_taxonomy); on PK / unique conflicts, skip the
       loser's row.
     - Delete the loser species row.

  2. **Rename remaining `[Genus] sp` rows to `[Genus] spp`** — for each row
     whose name matches `^[A-Z][a-z]+ sp$`, check for a name collision against
     `species.name`, add a "scientific" alias for the old name, then update
     `species.name`.

  3. **Set `genus_placeholder = true`** on every species whose trimmed name
     matches `^[A-Z][a-z]+ spp$` AND is linked to a `taxonomy` row of type
     `genus`.

  `down/0` is a no-op: the merges in step 1 are destructive, and the test for
  whether a record was renamed in step 2 is not preserved separately from the
  scientific-synonym alias.
  """
  use Ecto.Migration

  require Logger

  @dedup_genera ~w(Cardamine Lonicera Solidago Symphoricarpos)

  # Canonical placeholder-name regexes. Both tolerate one-or-more internal
  # spaces between the genus token and the `sp`/`spp` suffix so that the
  # rename, mark, and count steps stay in lockstep — without this symmetry, a
  # row like `"Quercus  sp"` (double space) would be counted but never
  # renamed.
  @placeholder_sp_pattern ~S"^[A-Z][a-z]+ +sp$"
  @placeholder_spp_pattern ~S"^[A-Z][a-z]+ +spp$"

  def up, do: run!()

  def down, do: :ok

  @doc """
  Runs the data normalization. Public so tests can invoke it directly against
  a fixture in the sandboxed test DB.

  Returns `:ok`. Logs each rename, each merge, and final counts.
  """
  def run! do
    Logger.info("[normalize_genus_placeholders] starting")

    initial_total = count_placeholder_candidates()
    Logger.info("[normalize_genus_placeholders] initial candidates: #{initial_total}")

    Enum.each(@dedup_genera, &dedup_genus/1)
    rename_remaining_sp_records()
    flag_count = mark_genus_placeholders()

    final_total = count_placeholder_candidates()

    Logger.info(
      "[normalize_genus_placeholders] done. genus_placeholder=true rows: #{flag_count}; remaining placeholder candidates: #{final_total}"
    )

    :ok
  end

  # ====================================================================
  # Step 1: dedup known dup-genera
  # ====================================================================

  defp dedup_genus(genus_name) do
    loser_name = "#{genus_name} sp"
    survivor_name = "#{genus_name} spp"

    case {get_species(loser_name), get_species(survivor_name)} do
      {nil, _} ->
        Logger.info("[normalize] dedup: no `#{loser_name}` row; skipping #{genus_name}")
        :ok

      {%{id: loser_id}, nil} ->
        Logger.info(
          "[normalize] dedup: `#{loser_name}` exists but `#{survivor_name}` does not; will be handled by rename step"
        )

        _ = loser_id
        :ok

      {%{id: loser_id}, %{id: survivor_id}} ->
        Logger.info(
          "[normalize] dedup: merging `#{loser_name}` (#{loser_id}) into `#{survivor_name}` (#{survivor_id})"
        )

        merge_into_survivor(loser_id, survivor_id)
        :ok
    end
  end

  defp merge_gallhost(loser_id, survivor_id) do
    # Re-point host_species_id loser → survivor where it would NOT conflict
    sql = """
    UPDATE gallhost gh
    SET host_species_id = $2
    WHERE gh.host_species_id = $1
      AND NOT EXISTS (
        SELECT 1 FROM gallhost gh2
        WHERE gh2.gall_species_id = gh.gall_species_id
          AND gh2.host_species_id = $2
      )
    """

    {:ok, %{num_rows: moved}} = Gallformers.Repo.query(sql, [loser_id, survivor_id])

    {:ok, %{num_rows: del}} =
      Gallformers.Repo.query("DELETE FROM gallhost WHERE host_species_id = $1", [loser_id])

    Logger.info("[normalize] gallhost: moved=#{moved}, deleted_conflicts=#{del}")
  end

  defp merge_aliases(loser_id, survivor_id) do
    # Repoint alias_species rows that don't conflict on (survivor, alias_id)
    sql = """
    UPDATE alias_species ax
    SET species_id = $2
    WHERE ax.species_id = $1
      AND NOT EXISTS (
        SELECT 1 FROM alias_species ax2
        WHERE ax2.species_id = $2
          AND ax2.alias_id = ax.alias_id
      )
    """

    {:ok, %{num_rows: moved}} = Gallformers.Repo.query(sql, [loser_id, survivor_id])

    {:ok, %{num_rows: deleted}} =
      Gallformers.Repo.query("DELETE FROM alias_species WHERE species_id = $1", [loser_id])

    Logger.info("[normalize] alias_species: moved=#{moved}, deleted_conflicts=#{deleted}")
  end

  # Simple FK with no unique constraint on species_id (e.g. image, gallhost-like)
  defp merge_simple_fk(table, loser_id, survivor_id) do
    {:ok, %{num_rows: moved}} =
      Gallformers.Repo.query(
        "UPDATE #{table} SET species_id = $2 WHERE species_id = $1",
        [loser_id, survivor_id]
      )

    Logger.info("[normalize] #{table}: moved=#{moved}")
  end

  defp merge_species_source(loser_id, survivor_id) do
    # species_source has its own surrogate `id` PK and no (species_id, source_id)
    # unique constraint, so a simple repoint is safe.
    merge_simple_fk("species_source", loser_id, survivor_id)
  end

  # Tables whose PK is exactly species_id (host_traits). Skip the loser's row
  # if the survivor already has one; otherwise repoint.
  defp merge_unique_fk(table, :species_id, loser_id, survivor_id) do
    {:ok, %{num_rows: moved}} =
      Gallformers.Repo.query(
        """
        UPDATE #{table} SET species_id = $2
        WHERE species_id = $1
          AND NOT EXISTS (SELECT 1 FROM #{table} WHERE species_id = $2)
        """,
        [loser_id, survivor_id]
      )

    {:ok, %{num_rows: dropped}} =
      Gallformers.Repo.query("DELETE FROM #{table} WHERE species_id = $1", [loser_id])

    Logger.info("[normalize] #{table}: moved=#{moved}, dropped_conflicts=#{dropped}")
  end

  defp merge_host_range(loser_id, survivor_id) do
    # PK is (species_id, place_id). Repoint where survivor doesn't already
    # have a row for that place; delete the rest.
    sql = """
    UPDATE host_range hr SET species_id = $2
    WHERE hr.species_id = $1
      AND NOT EXISTS (
        SELECT 1 FROM host_range hr2
        WHERE hr2.species_id = $2 AND hr2.place_id = hr.place_id
      )
    """

    {:ok, %{num_rows: moved}} = Gallformers.Repo.query(sql, [loser_id, survivor_id])

    {:ok, %{num_rows: dropped}} =
      Gallformers.Repo.query("DELETE FROM host_range WHERE species_id = $1", [loser_id])

    Logger.info("[normalize] host_range: moved=#{moved}, dropped_conflicts=#{dropped}")
  end

  defp merge_species_taxonomy(loser_id, survivor_id) do
    sql = """
    UPDATE species_taxonomy st SET species_id = $2
    WHERE st.species_id = $1
      AND NOT EXISTS (
        SELECT 1 FROM species_taxonomy st2
        WHERE st2.species_id = $2 AND st2.taxonomy_id = st.taxonomy_id
      )
    """

    {:ok, %{num_rows: moved}} = Gallformers.Repo.query(sql, [loser_id, survivor_id])

    {:ok, %{num_rows: dropped}} =
      Gallformers.Repo.query("DELETE FROM species_taxonomy WHERE species_id = $1", [loser_id])

    Logger.info("[normalize] species_taxonomy: moved=#{moved}, dropped_conflicts=#{dropped}")
  end

  defp delete_species(loser_id) do
    {:ok, %{num_rows: n}} = Gallformers.Repo.query("DELETE FROM species WHERE id = $1", [loser_id])
    Logger.info("[normalize] deleted species id=#{loser_id} (rows=#{n})")
  end

  # ====================================================================
  # Step 2: rename remaining `[Genus] sp` → `[Genus] spp`
  # ====================================================================

  defp rename_remaining_sp_records do
    sql = """
    SELECT id, name FROM species
    WHERE taxoncode = 'plant'
      AND name ~ $1
    ORDER BY name
    """

    {:ok, %{rows: rows}} = Gallformers.Repo.query(sql, [@placeholder_sp_pattern])

    Logger.info("[normalize] rename step: #{length(rows)} candidates")

    Enum.each(rows, fn [id, old_name] ->
      # Normalize any extra internal whitespace so `"Foo  sp"` -> `"Foo spp"`,
      # keeping the post-rename name canonical and matchable by the spp regex.
      new_name = Regex.replace(~r/\s+/, old_name, " ") <> "p"

      case existing_id_for_name(new_name, id) do
        nil ->
          maybe_add_synonym(id, old_name)

          {:ok, _} =
            Gallformers.Repo.query("UPDATE species SET name = $1 WHERE id = $2", [new_name, id])

          Logger.info("[normalize] renamed species #{id}: `#{old_name}` -> `#{new_name}`")

        survivor_id ->
          # An unexpected duplicate — merge into the existing `spp` row. This
          # is the same path used by the hardcoded dedup step, so the
          # migration self-heals if new duplicates appear later.
          Logger.info(
            "[normalize] rename target `#{new_name}` already exists (#{survivor_id}); merging loser #{id} into survivor"
          )

          merge_into_survivor(id, survivor_id)
      end
    end)
  end

  defp existing_id_for_name(name, exclude_id) do
    case Gallformers.Repo.query!(
           "SELECT id FROM species WHERE name = $1 AND id <> $2 LIMIT 1",
           [name, exclude_id]
         ) do
      %{rows: [[id]]} -> id
      _ -> nil
    end
  end

  defp merge_into_survivor(loser_id, survivor_id) do
    merge_gallhost(loser_id, survivor_id)
    merge_aliases(loser_id, survivor_id)
    merge_simple_fk("image", loser_id, survivor_id)
    merge_species_source(loser_id, survivor_id)
    merge_unique_fk("host_traits", :species_id, loser_id, survivor_id)
    merge_host_range(loser_id, survivor_id)
    merge_species_taxonomy(loser_id, survivor_id)
    delete_species(loser_id)
  end

  defp maybe_add_synonym(species_id, old_name) do
    # Idempotency: if an alias of the same name+type is already linked to this
    # species, don't create a duplicate.
    sql = """
    SELECT 1 FROM alias a
    JOIN alias_species link ON link.alias_id = a.id
    WHERE link.species_id = $1 AND a.name = $2 AND a.type = 'scientific'
    LIMIT 1
    """

    case Gallformers.Repo.query!(sql, [species_id, old_name]) do
      %{num_rows: 0} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {:ok, %{rows: [[alias_id]]}} =
          Gallformers.Repo.query(
            """
            INSERT INTO alias (name, type, description, inserted_at, updated_at)
            VALUES ($1, 'scientific', 'Previous name', $2, $2)
            RETURNING id
            """,
            [old_name, now]
          )

        {:ok, _} =
          Gallformers.Repo.query(
            "INSERT INTO alias_species (alias_id, species_id) VALUES ($1, $2)",
            [alias_id, species_id]
          )

      _ ->
        :ok
    end
  end

  # ====================================================================
  # Step 3: set genus_placeholder = true for matching rows
  # ====================================================================

  defp mark_genus_placeholders do
    sql = """
    UPDATE species s
    SET genus_placeholder = true
    WHERE s.taxoncode = 'plant'
      AND s.name ~ $1
      AND s.genus_placeholder = false
      AND EXISTS (
        SELECT 1 FROM species_taxonomy st
        JOIN taxonomy t ON t.id = st.taxonomy_id
        WHERE st.species_id = s.id AND t.type = 'genus'
      )
    """

    {:ok, %{num_rows: n}} = Gallformers.Repo.query(sql, [@placeholder_spp_pattern])
    Logger.info("[normalize] flagged genus_placeholder=true on #{n} rows")

    {:ok, %{rows: [[total]]}} =
      Gallformers.Repo.query(
        "SELECT COUNT(*) FROM species WHERE genus_placeholder = true",
        []
      )

    total
  end

  # ====================================================================
  # Helpers
  # ====================================================================

  defp get_species(name) do
    case Gallformers.Repo.query!("SELECT id FROM species WHERE name = $1 LIMIT 1", [name]) do
      %{rows: [[id]]} -> %{id: id}
      _ -> nil
    end
  end

  defp count_placeholder_candidates do
    sql = """
    SELECT COUNT(*) FROM species
    WHERE taxoncode = 'plant'
      AND (name ~ $1 OR name ~ $2)
    """

    {:ok, %{rows: [[n]]}} =
      Gallformers.Repo.query(sql, [@placeholder_sp_pattern, @placeholder_spp_pattern])

    n
  end
end
