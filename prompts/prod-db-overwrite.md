# Database Update

**IMPORTANT**: Use the Mix task, not manual operations. See "Fly.io Operations - CRITICAL RULES" in CLADE.md.

To update the production database (this is destructive and should be used only in the direst of circumstances):

```bash
mix gallformers.update_prod_db path/to/gallformers.sqlite
```

This task:
1. Validates local database (integrity + species count ≥ 5000)
2. Creates clean single-file copy (VACUUM + WAL checkpoint)
3. Stops production machine
4. Updates to sleep mode (releases DB lock)
5. Backs up existing database (timestamped, can rollback)
6. Uploads new database
7. Verifies remote database
8. Clears Litestream backups (forces fresh generation)
9. Restarts app normally

**Prerequisites**: flyctl, sqlite3, jq, aws CLI

**See**: `lib/mix/tasks/gallformers/update_prod_db.ex` for implementation
