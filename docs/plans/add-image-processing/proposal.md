# Change: Add Image Processing System

## Prerequisites

- **adopt-phoenix-liveview**: V2 Phoenix/LiveView application must be in place
- **Oban**: Background job processing library must be configured

## Why

The current v1 image system has significant reliability issues:
- Fire-and-forget Jimp processing that can fail silently
- Hardcoded CDN wait loops (100 iterations x 100ms) for cache sync
- No status tracking - clients can't know if processing succeeded
- Quality 100 output creates unnecessarily large files
- Sharp library included but unused (technical debt)

V2 needs robust, reliable image handling with proper async processing, status tracking, and optimized output formats.

## What Changes

### New Capability: Image Processing System

- **Processing**: Elixir with Oban background jobs using Image library (Vix/libvips)
- **Storage**: Existing S3 bucket (relocated to `us-east-1`) with optimized CloudFront configuration
- **API**: Phoenix contexts and LiveView components for upload, import, status, and management
- **Web UI**: LiveView gallery component, admin upload interface, GLightbox viewer
- **Real-time Updates**: Phoenix PubSub for instant status notifications

### Key Features

1. **Two Upload Paths**: Direct upload via presigned S3 URL, or import from iNaturalist URL
2. **Multi-size Processing**: Generate small (300px), medium (800px), large (1200px), xlarge (2000px), preserve original
3. **Modern Formats**: WebP for served sizes + single JPEG fallback for old browser compatibility
4. **Format Support**: JPEG, PNG, WebP, and HEIC (auto-converted)
5. **Real-time Status**: pending, complete, failed - PubSub pushes updates to LiveView
6. **iNaturalist Integration**: Import images by pasting observation URL, auto-populate attribution
7. **Attribution Tracking**: Creator, license, source URL, license URL, source publication link, uploader audit trail
8. **Gallery UI**: Mobile-friendly carousel, GLightbox for full-size viewing, accessible
9. **Bulk Operations**: Multi-select for batch delete and metadata editing
10. **Article Images**: Same processing pipeline for article/reference image uploads

### Migration

Existing 6,531 images across 2,522 species will be migrated via Elixir Mix task to:
- Generate optimized WebP variants + JPEG fallback
- Create new UUID-based records with legacy_id traceability

## Impact

- **New specs**: `web-images` (gallery UI, upload interface, processing pipeline)
- **Affected code**:
  - `v2/lib/gallformers/images.ex` - Images context with S3 operations
  - `v2/lib/gallformers/images/` - Processing workers, schemas
  - `v2/lib/gallformers_web/live/` - Gallery and upload LiveView components
  - `v2/lib/mix/tasks/` - Migration Mix task
- **Infrastructure**:
  - S3 bucket CORS configuration
  - CloudFront cache headers (versioned URLs)
  - Fly.io machine sizing (1GB RAM minimum)
  - Oban job queue configuration

## Out of Scope

- Image categories/types (keep simple - species and article association only)
- AI-based image recognition
- Video support
- Image editing/cropping in-browser
- Manual image ordering (uses automatic source-based grouping)

## Dependencies

- Requires `adopt-phoenix-liveview` for Phoenix/LiveView foundation
- Requires Oban configured for background job processing
- Blocks: None (this is additive functionality)

## Success Criteria

1. Presigned URL upload succeeds; Oban processes; PubSub notifies; status becomes "complete"
2. iNat URL import creates image record, processes via Oban, auto-populates attribution
3. Gallery displays images sorted by: default first, same source, then grouped by source
4. Admin can upload (max 10 per batch), edit metadata, set default, bulk delete
5. Migration Mix task processes all 6,531 existing images with progress tracking
6. All served images are WebP format with JPEG fallback, significantly smaller than current JPG output
7. Processing errors show user-friendly message with expandable technical details
8. Stale pending records are automatically cleaned up by scheduled Oban job
