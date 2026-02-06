# ID Tool N+1 Query Incident - February 5, 2026

## Summary

Production experienced severe performance degradation starting around 1-3AM ET. HTTP response times jumped from ~11ms to 1.5+ minutes, CPU pegged at 100%, and users saw connection pool exhaustion errors.

**Root cause**: N+1 query pattern in `get_default_gall_images()` running 3,662 database queries per ID tool request.

**Resolution**: Replaced with single query using correlated subquery. Deployed in commit `67146648`.

## Impact

- **Duration**: ~6+ hours (1-3AM to ~9:30AM ET)
- **Severity**: Site largely unusable, requests timing out
- **Affected**: All users, particularly ID tool

## Timeline

| Time (ET) | Event |
|-----------|-------|
| ~1-3AM | Performance degradation begins (per Grafana) |
| 9:29AM | Incident investigation started |
| 9:35AM | Root cause identified: N+1 query in `get_default_gall_images()` |
| 9:36AM | Fix implemented and tested |
| 9:37AM | Fix committed, deployment initiated |

## Root Cause

The `get_default_gall_images()` function in `lib/gallformers/species.ex` was running:

1. One query to get minimum `sort_order` for each gall species (returns 3,661 rows)
2. **One query per species** to fetch the actual image path (3,661 additional queries)

Total: **3,662 queries** every time the ID tool was used.

This pattern was introduced on January 22, 2026 in commit `22a3c3cb` when image ordering was changed from `default == true` to `sort_order`-based selection.

### Why It Surfaced Now

- V2 launched February 4
- Increased traffic post-launch
- Overnight load (crawlers, batch processes) pushed connection pool past capacity
- SQLite's single-writer model amplified contention

## Fix

Replaced N+1 pattern with single query using correlated subquery:

```elixir
from(i in Image,
  join: s in Species,
  on: i.species_id == s.id,
  where: s.taxoncode == "gall",
  where:
    fragment(
      "? = (SELECT MIN(i2.sort_order) FROM image i2 WHERE i2.species_id = ?)",
      i.sort_order,
      i.species_id
    ),
  select: %{species_id: i.species_id, path: i.path}
)
```

**Before**: 3,662 queries, connection pool exhaustion
**After**: 1 query, ~14ms

## Prevention

1. **Code review**: Watch for N+1 patterns, especially `Enum.map/flat_map` with queries inside
2. **Load testing**: Test ID tool with production data volume before releases
3. **Monitoring**: Add alerts for connection pool queue depth and query count per request
