# Oban Operations

Operational guide for Gallformers background jobs.

## Dashboard

The Oban Web dashboard is mounted at `/admin/jobs`, behind the `:superadmin` pipeline (`router.ex`).

Use it to:
- Inspect queue health and worker throughput
- View failed, retryable, cancelled, and completed jobs
- Retry or cancel individual jobs
- Confirm cron-enqueued jobs are appearing on schedule

## Queues

Queues are set in `config/config.exs`. Production (`main`) runs:

| Queue | Concurrency | Purpose |
|-------|-------------|---------|
| `default` | 10 | General background work (no worker uses it) |
| `maintenance` | 5 | Scheduled maintenance such as analytics rollups (`Gallformers.Analytics.RollupWorker`) |

The new back-end (`taxogall`) adds:

| Queue | Concurrency | Purpose |
|-------|-------------|---------|
| `import` | 1 | Moves one import package a step on (`Gallformers.Import.Worker`, unique per package) |
| `catalog` | 5 | Refreshes one Gall's ID-tool row (`Gallformers.Catalog.ReadModels.GallIndexWorker`, unique per Gall) |

## Scheduled Jobs

Current cron jobs:

| Schedule (UTC) | Worker | Purpose |
|----------------|--------|---------|
| `0 7 * * *` | `Gallformers.Analytics.RollupWorker` | Roll up analytics through yesterday and prune old raw page views |

## First Checks During an Incident

1. Open `/admin/jobs` and filter by `retryable`, `discarded`, or the affected queue.
2. Check whether failures are isolated to one worker or all queues.
3. Inspect the latest job error and confirm whether it is application, database, or infrastructure related.
4. If jobs are stuck in `executing`, verify whether the machine restarted recently. Lifeline rescues jobs stuck executing for more than an hour.

## Common Operations

### Retry a failed job

1. Open the job in `/admin/jobs`
2. Confirm the underlying issue is fixed
3. Use the dashboard retry action

### Verify the analytics rollup

1. Open `/admin/jobs`
2. Filter for `Gallformers.Analytics.RollupWorker`
3. Confirm the daily cron job ran after 07:00 UTC
4. If it failed, inspect the job error before retrying

## Notes

- Oban shares the main Ecto pool. Sustained queue failures may reflect database saturation rather than a worker bug.
- Job retention is seven days via `Oban.Plugins.Pruner`.
- Reindexer and Lifeline are configured explicitly (`config/config.exs`) for routine maintenance and orphan recovery; Lifeline's `rescue_after` is one hour.
