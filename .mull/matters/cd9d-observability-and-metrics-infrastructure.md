---
status: refined
effort: 2 days
created: 2026-02-18
updated: 2026-02-19
epic: platform
relates: [1edb, 5323, 4474]
---

# Observability and metrics infrastructure

## Context

No external services — not just cost but account sprawl, privacy, and attack surface. Self-hosted OSS on Fly.io, serving both gallformers and Oak Compendium (also Phoenix/LiveView on Fly). Potentially a self-hosted Postgres instance too if the Postgres migration (4474) happens.

## Current Baseline

The telemetry *plumbing* exists but has no sink:
- **Telemetry definitions**: Phoenix, Ecto, VM metrics defined in `telemetry.ex` — ConsoleReporter commented out, nothing consumes them
- **Request logging**: JSON Lines to disk, 30-day rotation, retrieved manually via SFTP + jq. Solid for post-incident but reactive
- **Health check**: `GET /health` does `SELECT 1` only — no memory, process count, ETS info
- **Analytics**: Privacy-respecting first-party page view tracking (separate concern, keep as-is)
- **LiveDashboard**: Dev-only at `/dev/dashboard`
- **Logger**: Standard Elixir text format, `[:request_id]` metadata only

Notably absent: error tracking, metrics export, structured logging, BEAM introspection, alerting. The OOM crash (1edb) was diagnosed from SFTP'd logs and guesswork.

## Proposed Architecture

Dedicated Fly.io machine (`obs.internal`) on the private WireGuard network:

```
┌─────────────────────────────────────┐
│  obs.internal (Fly machine, 1GB)    │
│                                     │
│  Prometheus or VictoriaMetrics      │
│    ← scrapes /metrics from:        │
│       gallformers.internal          │
│       oaks.internal                 │
│       postgres (if migrated)        │
│         (via postgres_exporter)     │
│                                     │
│  Grafana                            │
│    ← dashboards + alerting          │
│    → email/webhook alerts           │
└─────────────────────────────────────┘
```

Apps expose `/metrics` via `prom_ex` or `telemetry_metrics_prometheus`. Prometheus scrapes over Fly private network. Grafana reads from Prometheus and sends alerts.

## Why This Makes Sense at Our Scale

- **Workload is tiny**: 2-3 apps, ~50-100 metrics series each, 20k req/day total. A small machine would be bored.
- **OSS stack is mature**: Prometheus + Grafana is a decade-old standard, not bleeding edge.
- **Fly private networking**: Apps expose /metrics over WireGuard — no public endpoints, no auth for scrape path.
- **Shared cost**: One machine (~$3-5/mo) serves all apps. Adding another app is just another scrape target.
- **VictoriaMetrics**: Lighter Prometheus-compatible alternative if memory is the constraint — single binary, ~2-3x less RAM. Worth evaluating vs Prometheus.

## Honest Concerns

1. **Who monitors the monitor?** If obs machine goes down, lose visibility when you need it most. Mitigation: Fly auto-restarts + one cheap external ping (UptimeRobot free tier or 5323 synthetic monitoring) on actual app health endpoints.
2. **Ops burden**: Prometheus + Grafana are stable but still software to maintain. Bounded burden though — and less than diagnosing OOMs from SFTP'd logs.
3. **Memory sizing**: Grafana ~200-256MB, Prometheus ~50-100MB at our cardinality. 512MB tight, 1GB comfortable. VictoriaMetrics would ease this.
4. **Storage**: ~50-100MB/month TSDB data at 30-day retention. Trivially small.

## Action

Create an implementation plan covering:
1. Evaluate Prometheus vs VictoriaMetrics for our constraints (memory, single-binary simplicity)
2. Design the obs machine (Fly config, volume, Docker image or buildpack)
3. App-side plumbing: prom_ex vs telemetry_metrics_prometheus, /metrics endpoint, what metrics to expose
4. Grafana setup: dashboards for BEAM memory (1edb), request latency, error rates
5. Alerting: what to alert on, where alerts go (email, webhook)
6. Enrichments to existing infra: richer /health endpoint, structured logging (separate from metrics pipeline?)
7. Rollout order: gallformers first, then oaks, then postgres if applicable
