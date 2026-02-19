defmodule Gallformers.Repo.Migrations.AddRangePrecisionAndReclassifyTerritories do
  use Gallformers.Migration

  def up do
    # Add precision column to host_range
    execute "ALTER TABLE host_range ADD COLUMN precision TEXT NOT NULL DEFAULT 'exact'"

    # Add precision column to gall_range_exclusion
    execute "ALTER TABLE gall_range_exclusion ADD COLUMN precision TEXT NOT NULL DEFAULT 'exact'"

    # Reclassify Puerto Rico: update the original US-PR row in place.
    # The western hemisphere migration inserted a separate PR country row under
    # Caribbean. The original US-PR row has host_range records pointing to it;
    # the duplicate PR country row has none. We update the original and delete
    # the duplicate.
    execute "UPDATE place SET code = 'PR', type = 'country' WHERE code = 'US-PR'"

    # Rewire PR hierarchy from US to Caribbean (XB)
    execute """
    UPDATE place_hierarchy
    SET parent_id = (SELECT id FROM place WHERE code = 'XB')
    WHERE place_id = (SELECT id FROM place WHERE code = 'PR'
                      AND id IN (SELECT DISTINCT place_id FROM host_range))
    """

    # Delete the duplicate PR country entry (the one with zero host_range records).
    # After the UPDATE above, both rows have code='PR' and type='country'.
    # The duplicate is the one NOT referenced by host_range.
    execute """
    DELETE FROM place_hierarchy WHERE place_id IN (
      SELECT p.id FROM place p
      WHERE p.code = 'PR' AND p.type = 'country'
      AND p.id NOT IN (SELECT DISTINCT place_id FROM host_range)
    )
    """

    execute """
    DELETE FROM place WHERE id IN (
      SELECT p.id FROM place p
      WHERE p.code = 'PR' AND p.type = 'country'
      AND p.id NOT IN (SELECT DISTINCT place_id FROM host_range)
    )
    """
  end

  def down do
    # Restore PR as US-PR state under US
    execute """
    UPDATE place SET code = 'US-PR', type = 'state'
    WHERE code = 'PR' AND id IN (SELECT DISTINCT place_id FROM host_range)
    """

    # Rewire back to US
    execute """
    UPDATE place_hierarchy
    SET parent_id = (SELECT id FROM place WHERE code = 'US')
    WHERE place_id = (SELECT id FROM place WHERE code = 'US-PR')
    """

    # Re-insert the PR country entry under Caribbean
    execute "INSERT INTO place (name, code, type) VALUES ('Puerto Rico', 'PR', 'country')"

    execute """
    INSERT INTO place_hierarchy (place_id, parent_id)
    SELECT p.id, c.id FROM place p, place c
    WHERE p.code = 'PR' AND p.type = 'country' AND c.code = 'XB'
    """

    # Remove precision columns
    execute "ALTER TABLE gall_range_exclusion DROP COLUMN precision"
    execute "ALTER TABLE host_range DROP COLUMN precision"
  end
end
