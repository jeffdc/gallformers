---
status: raw
created: 2026-02-15
updated: 2026-02-25
epic: images
blocks: [e7bb]
needs: [60e6]
---

# Image processing pipeline

> **Old design (2026-02-15) — needs full reassessment before any work begins.** Architecture decisions below were made early in the V2 rewrite and may not reflect current codebase state.

## Architecture Decisions (from original design)

- **Processing**: Elixir + Oban background jobs + Image library (Vix/libvips). Not Lambda.
- **Storage**: Existing S3 bucket, flat UUID-based paths under v2/ prefix. CDN via CloudFront.
- **Upload**: Presigned URL direct-to-S3, then Oban worker downloads and processes variants.
- **Formats**: WebP for all variants + JPEG fallback. Accept JPEG, PNG, WebP, HEIC.
- **Sizes**: small (300px), medium (800px), large (1200px), xlarge (2000px), fallback (800px JPEG), original.
- **Status tracking**: Phoenix PubSub for real-time UI updates.
- **Cache busting**: Versioned URLs (?v=unix_timestamp), 1-year cache TTL.
- **Concurrency**: 1 Oban worker (protects modest Fly.io hardware), 10 files per batch.
- **Lightbox**: GLightbox (~10KB vanilla JS).

## S3 Structure

```
gallformers/
├── v2/originals/{id}.{ext}
├── v2/small/{id}.webp
├── v2/medium/{id}.webp
├── v2/large/{id}.webp
├── v2/xlarge/{id}.webp
├── v2/fallback/{id}.jpg
└── gall/ (legacy v1)
```

## Database Schema

New images table: UUID PK, species_id/article_id FKs, source_id (RESTRICT delete), status (pending/complete/failed), original format/dimensions, legacy_id/path for migration traceability, iNat observation ID.

Image ordering: default first, then grouped by source_id, newest first within groups.

## iNaturalist Integration

Client-side API integration. Paste observation URL → fetch metadata → select photos → server downloads and processes. Rate limits (~1 req/sec, 10k/day) not a concern at our volume.

## Migration Plan

Mix task downloads v1 images (6,531 across 2,522 species), generates UUIDs, re-processes through Oban pipeline. Estimated 2-4 hours. V1 images preserved for rollback.

## What to Keep from Current Implementation

JS hook UI patterns (drag-drop, previews, progress), presigned URL approach, database schema foundation, size variant dimensions.

## What to Replace

Fire-and-forget Task.start → Oban. Silent errors → proper reporting + retry. Polling → PubSub. Add HEIC support.

## Open Questions

- Article image requirements (hero images, inline sizes, thumbnails)
- Whether to support manual image ordering (currently automatic source-based grouping)
- Bulk operation UI details

