# Deleted Gall Recovery: Gall 1855

## Incident

- **Gall ID:** 1855
- **Status:** Complete
- **Operator:** Jeff
- **Application read-only enabled:** 2026-09-02 02:05 UTC
- **Non-Op admin inaccessible:** Confirmed
- **Public pages readable:** Confirmed
- **Recovery workspace:** `/tmp/gall-recovery-1855-20260902T113058`
- **Recovery completed:** 2026-09-02 16:44 UTC
- **Application read-only disabled:** Confirmed after production verification

## Recovery Log

### Step 0: Enable Application Read-Only Mode

Completed. Application read-only mode is enabled. Non-Op admin access is blocked while public pages remain readable.

### Step 1: Fetch and Preserve the Full Backup

Completed. The full production backup was downloaded and restored into `gallformers_dev` before this session.

- **Selected backup:** `s3://gallformers-full-backups/2026-09-01/gallformers.dump`
- **Preserved copy:** `/tmp/gall-recovery-1855-20260902T113058/backup-full.dump`
- **SHA-256:** `054350a3b344793c762c30d1bfdaa5fe32f7b92b9be687aa41635429ac38a01e`

### Step 2: Verify the Backup Through the Local UI

Completed by Jeff before this session. Gall 1855 and its taxonomy, hosts, aliases, sources/excerpts, range, morphology, image metadata, attribution, source links, and image ordering were reviewed in the local UI.

### Step 3: Generate the Restore SQL

Completed. The committed generator produced a 63-line transactional restore containing the expected gall data:

- 1 species and 1 gall-traits row
- 5 aliases and 5 alias links
- 1 taxonomy link and 2 host links
- 4 range rows and 17 morphology rows
- 7 species-source rows
- 4 image rows

Review found one `BEGIN`, one `COMMIT`, and no `UPDATE`, `DELETE`, `TRUNCATE`, schema-change, or upsert statement.

- **Generated SQL:** `/tmp/gall-recovery-1855-20260902T113058/restore-gall.sql`
- **SHA-256:** `58c259240e3bf43253a964c6c676d6361ee16b28e15d05039d12471776d913cb`

### Step 4: Dump Current Production Separately

Completed. The first two proxy attempts did not connect: Fly CLI upgraded from 0.4.52 to 0.4.97 and then reported an expired authentication session. Jeff reauthenticated the CLI. The next proxy connected successfully and the PostgreSQL connectivity check returned `1`.

The optional `.env` load reported that the file was absent, but the required production variables were already present in the environment. The runbook was corrected to load `.env` only when present.

- **Current-production dump:** `/tmp/gall-recovery-1855-20260902T113058/production-current.dump`
- **SHA-256:** `8ecb0236b61a13204329bb71184952da6c19adf56af1172adc4138efbdd3eb3d`
- **Archive validation:** Nonempty and successfully read by `pg_restore --list`
- **Production writes:** None

### Step 5: Rehearse Against Current Production Locally

Completed. The current-production dump was restored into `gallformers_recovery_current`, and the checksummed recovery SQL committed all 47 expected inserts. A development-only `PGDATABASE` override was added so the local application could connect to the isolated database.

Jeff reviewed `http://localhost:4000/gall/1855`. The restored taxonomy, hosts, aliases, sources/excerpts, range, morphology, and image metadata matched the backup review. Image URLs returned the expected 404 responses because S3 objects remain deleted.

### Step 6: Restore Images and Verify Locally

Completed. All 20 reviewed S3 deletion markers were removed, exposing the retained prior object versions. `head-object` confirmed all 20 keys with nonzero sizes and expected JPEG or PNG content types.

- **Expected keys:** 20
- **Current deletion markers:** 20
- **Retained prior object versions:** 20
- **Missing keys:** 0
- **Unexpected keys:** 0
- **Recovery script:** `/tmp/gall-recovery-1855-20260902T113058/restore-image-markers.sh`

Jeff reloaded `http://localhost:4000/gall/1855` and confirmed all four images display correctly in the recovery-backed local environment.

### Step 7: Restore the Production Database

Completed after Jeff approved production execution. The restore SQL checksum matched the reviewed value. Production connectivity succeeded, all 47 expected inserts completed, all five sequence synchronizations completed, and the transaction committed. The Fly database proxy was then stopped cleanly.

### Step 8: Verify Production

Completed. Jeff reviewed `https://gallformers.org/gall/1855` and confirmed that the gall data and images look correct in production.

### Step 9: Close Out

Completed. Jeff disabled application read-only mode and confirmed normal admin and public behavior. The local recovery server was stopped. The reviewed transaction contained only the expected inserts and sequence synchronization; production and public UI verification found no unexpected changes.

`mix precommit` passed: formatting, warnings-as-errors compilation, Credo, 2,069 tests with 0 failures, and test-exclusion validation.

Recovery artifacts remain under `/tmp/gall-recovery-1855-20260902T113058`.
