---
status: raw
created: 2026-03-13
updated: 2026-03-13
epic: platform
relates: [4474]
---

# Investigate WCVP data update mechanism

## Problem

The mechanism for updating the WCVP SQLite database on production is half-assed. `Wcvp.Refresh.refresh/0` exists but:

1. **Disk space**: The refresh downloads a .tmp copy alongside the existing file. The new WCVP DB is ~700MB. With boundaries.pmtiles (370MB), the main SQLite DB (~180MB), and the old WCVP copy, the 2GB default volume was 100% full. The download failed with `:enospc`. Volume has been extended to 5GB but the refresh mechanism has no space check before downloading.
2. **No admin UI trigger**: The only way to call `refresh/0` is via `fly ssh console` → `remote` → IEx. There's no admin page button for a bulk DB swap (the existing "Refresh from POWO-WCVP" button on host edit pages does per-host data diffing, not a DB file swap).
3. **Previous agents failed**: The build-and-upload workflow (`mix gallformers.wcvp.build_db --upload`) was supposed to be paired with a clean way to trigger the download on prod. That second half was never properly built or tested.

> "Previous agents totally failed to do it correctly (thanks Anthropic and your fucked up idea to change the default thinking to medium and cause so many headaches for me)." — Jeff

## Investigation needed

- What should the update workflow actually look like end-to-end?
- Should there be an admin page for WCVP DB management (upload status, trigger refresh, see current version)?
- Should the refresh do a space check before downloading?
- Should the entrypoint re-download if the S3 copy is newer than the local copy (ETag/Last-Modified check)?
- Clean up orphaned files on the volume (old .bak, stale .shm/.wal from gallformers_new.sqlite)

## Cache-bust ARG for Dockerfile WCVP downloads

Docker caches the `RUN curl ... wcvp.sqlite` layer by its command string — it has no idea if the remote S3 file changed. Add a build ARG before the download step:

```dockerfile
ARG WCVP_VERSION=1
RUN mkdir -p /app/data && \
    curl -fSL -o /app/data/wcvp.sqlite ...
```

When WCVP is updated on S3, pass `--build-arg WCVP_VERSION=<new>` to bust the cache. Without it, the default value matches and Docker reuses the cached layer. Applies to both Dockerfile and Dockerfile.preview.

