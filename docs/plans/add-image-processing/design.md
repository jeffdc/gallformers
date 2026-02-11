# Design: Add Image Processing System

## Context

Gallformers needs a robust image processing system for the v2 rewrite. The v1 system has reliability issues with async Jimp processing that can fail silently. Images come from two sources:
1. Direct uploads (user's own photos)
2. iNaturalist observations (with proper attribution)

### Current State

- **S3 Bucket**: `gallformers-images-us-east-1` in `us-east-1`
- **CDN**: CloudFront at `https://dhz6u1p7t6okk.cloudfront.net`
- **Image Count**: 6,531 images across 2,522 species
- **Size Variants**: 5 sizes embedded in path names (`_original`, `_small`, `_medium`, `_large`, `_xlarge`)
- **Processing**: Server-side Jimp (async fire-and-forget)
- **Path Pattern**: `gall/{species_id}/{species_id}_{timestamp}_original.{ext}`

### V2 Current Implementation Analysis

The V2 Phoenix/LiveView implementation has a working image upload system. This section documents the current code flow for reference when implementing the improved system.

#### Upload Flow Overview

```
1. User selects files (JS Hook)
   assets/js/hooks/image_upload.js
   - Validates file types (jpeg/png only)
   - Enforces max file limit
   - Renders previews

2. User clicks Upload (JS Hook)
   - Disables button, shows "Preparing upload..."
   - Sends `request_presigned_urls` event to LiveView with file metadata

3. LiveView generates presigned URLs
   lib/gallformers_web/live/admin/images_live.ex
   - For each file, calls Images.generate_path/2 to create S3 path
   - Calls Images.presigned_upload_url/2 to get presigned URL from S3
   - Pushes `presigned_urls` event back to JS

4. JS uploads directly to S3
   - Uses XHR to PUT each file to its presigned URL
   - Tracks progress per file
   - Sends `uploads_completed` event with successful paths

5. LiveView creates DB records and queues processing
   - Creates image record with status "pending"
   - Queues Oban job for size variant generation
   - PubSub broadcasts status updates

6. Oban worker processes image
   - Downloads original from S3
   - Generates size variants using Image library (Vix)
   - Uploads variants to S3
   - Updates status to "complete"
   - PubSub broadcasts completion
```

#### What to Keep vs. Replace

**Keep:**
- JS hook UI patterns (drag-drop, previews, progress) - well implemented
- Presigned URL approach for bypassing server
- Database schema foundation (images table)
- Size variant dimensions

**Replace:**
- Fire-and-forget Task.start with Oban background jobs
- Silent error handling with proper error reporting and retry
- Polling with PubSub real-time updates
- Add HEIC support and JPEG fallback

### Stakeholders
- Primary user: Project owner (admin, only person uploading images)
- End users: Anyone browsing the site (public read access)

### Constraints
- Must handle ~10,000+ images at maturity
- Must preserve originals for future re-processing
- Mobile-friendly gallery experience required
- Migration must not disrupt current v1 operation during transition
- Fly.io machine: 1GB RAM minimum for image processing

## Goals / Non-Goals

### Goals
- Enable reliable async image processing with status tracking via Oban
- Optimize images for fast mobile loading (WebP, proper sizing, JPEG fallback)
- Track full attribution for licensing compliance
- Support iNaturalist import with auto-populated metadata
- Migrate existing images to new optimized format in `us-east-1`
- Support both species images and article images with same pipeline

### Non-Goals
- User-generated content moderation (admin-only uploads)
- Image editing/cropping in-browser
- Image categories/tagging (keep simple - just species/article association)
- AI-based image recognition
- Video support
- Manual image ordering (automatic source-based grouping)

## Decisions

### 1. Processing: Elixir + Oban (Not Lambda)

**Decision**: Process images in Elixir using Oban background jobs and the Image library (Vix/libvips).

**Rationale**:
- Single language/codebase (no Node.js Lambda to maintain)
- Phoenix PubSub for real-time status updates (no polling needed)
- Oban provides reliable job processing with retries
- Image library (Vix) is fast and supports all needed formats including HEIC
- Simpler deployment and debugging
- Same solution works for species images and article images

**Processing constraints**:
- Oban queue concurrency: 1 worker (protects modest Fly.io hardware)
- Upload batch limit: 10 files (UI enforced)
- Memory: 1GB minimum (20MB image decompresses to ~100-200MB)

**Flow**:
```
1. Client -> S3: Direct upload via presigned URL
2. Client -> LiveView: Report upload complete
3. LiveView: Create image record (status: pending), queue Oban job
4. Oban Worker: Download from S3, process, upload variants, update status
5. PubSub: Broadcast status change to subscribed LiveViews
6. LiveView: UI updates automatically
```

### 2. Storage: Existing S3 + Migrate to us-east-1

**Decision**: Keep existing S3 bucket `gallformers`, migrate contents to `us-east-1` during image migration.

**Rationale**:
- Match Fly.io `iad` datacenter for low latency
- Migration already re-processes all images, relocation is "free"
- CloudFront URLs stay the same (only paths change)

**S3 CORS Configuration** (for browser-based presigned URL uploads):
```json
{
  "CORSRules": [
    {
      "AllowedOrigins": [
        "https://gallformers.org",
        "https://gallformers.com",
        "https://gallformers.fly.dev",
        "http://localhost:4000"
      ],
      "AllowedMethods": ["PUT", "GET"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

### 3. Upload Size and Format Limits

**Decision**:
- Maximum file size: 20MB
- Accepted formats: JPEG, PNG, WebP, HEIC
- Minimum dimensions: Warn if < 300x300, but allow upload

**Enforcement**:
- Client-side validation provides fast feedback
- Presigned URL includes `Content-Length` condition (max 20MB)
- Server validates MIME type before processing
- Format detection via magic bytes (correct extension if mismatched)

### 4. Image Sizes and Formats

| Size | Longest Edge | Format | Use Case |
|------|--------------|--------|----------|
| small | 300px | WebP | Search results, grids, thumbnails |
| medium | 800px | WebP | Species page inline, admin preview |
| large | 1200px | WebP | Gallery browsing, lightbox |
| xlarge | 2000px | WebP | Full-size viewing, high-res displays |
| fallback | 800px | JPEG | Old browser compatibility (Safari < 14) |
| original | As uploaded | Original format | Archival, future reprocessing |

**HEIC Handling**: Accepted on upload, original preserved as HEIC, all variants converted to WebP/JPEG.

### 5. S3 Bucket Structure (Flat, UUID-based)

```
gallformers/
├── v2/                      # New v2 images (us-east-1)
│   ├── originals/{id}.{ext} # Original format (jpg, png, webp, heic)
│   ├── small/{id}.webp
│   ├── medium/{id}.webp
│   ├── large/{id}.webp
│   ├── xlarge/{id}.webp
│   └── fallback/{id}.jpg    # JPEG fallback for old browsers
└── gall/                    # Legacy v1 images
    └── {species_id}/...
```

**Path Derivation**: Only `original_format` stored in DB. All paths computed from ID:
- `v2/originals/{id}.{format_extension}`
- `v2/{size}/{id}.webp` for small/medium/large/xlarge
- `v2/fallback/{id}.jpg`

### 6. Database Schema

```sql
CREATE TABLE images (
    id TEXT PRIMARY KEY,           -- UUID
    species_id INTEGER,            -- FK to species.id (NULL for article images)
    article_id INTEGER,            -- FK to articles.id (NULL for species images)
    source_id INTEGER,             -- FK to source.id (publications)

    -- Display and attribution
    "default" INTEGER DEFAULT 0,   -- One default per species (quoted - reserved word)
    creator TEXT NOT NULL,         -- Photographer name
    caption TEXT NOT NULL,         -- Displayed publicly with the image
    attribution TEXT NOT NULL,     -- Internal notes about attribution details
    sourcelink TEXT NOT NULL,      -- URL to original image source
    license TEXT NOT NULL,         -- License type (cc-by, cc-by-nc, cc0, etc.)
    licenselink TEXT NOT NULL,     -- URL to license text
    uploader TEXT NOT NULL,        -- Who uploaded the image
    lastchangedby TEXT NOT NULL,   -- Audit: last editor

    -- Processing status
    status TEXT DEFAULT 'pending', -- pending, complete, failed
    error_message TEXT,            -- NULL unless status='failed'

    -- Image metadata
    original_format TEXT,          -- jpeg, png, webp, heic (detected via magic bytes)
    original_width INTEGER,
    original_height INTEGER,

    -- Migration traceability
    legacy_id INTEGER,             -- v1 image ID for migrated images
    legacy_path TEXT,              -- v1 path for reference

    -- iNaturalist import
    source_observation_id TEXT,    -- iNat observation ID if from iNat

    -- Timestamps
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),

    FOREIGN KEY (species_id) REFERENCES species(id) ON DELETE CASCADE,
    FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE,
    FOREIGN KEY (source_id) REFERENCES source(id) ON DELETE RESTRICT
);

CREATE INDEX idx_images_species ON images(species_id);
CREATE INDEX idx_images_article ON images(article_id);
CREATE INDEX idx_images_default ON images(species_id, "default");
CREATE INDEX idx_images_status ON images(status);
CREATE INDEX idx_images_source ON images(source_id);

-- Constraint: image must belong to either species OR article, not both
-- Enforced in application code
```

**Note on source_id**: Uses `ON DELETE RESTRICT` - cannot delete a source (publication) that has linked images. Admin must reassign or delete images first.

### 7. Image Ordering

Images are displayed in a specific order based on source grouping:

1. **Default image** first
2. **Other images from same source** as the default (newest first within group)
3. **Remaining images grouped by source_id** (newest first within each group)
4. **NULL sources** treated as their own group

Query pattern:
```sql
SELECT * FROM images
WHERE species_id = ?
ORDER BY
  "default" DESC,
  CASE WHEN source_id = (SELECT source_id FROM images WHERE species_id = ? AND "default" = 1) THEN 0 ELSE 1 END,
  source_id,
  created_at DESC
```

### 8. CDN Cache Strategy

**Decision**: Use versioned URLs for cache busting.

**Implementation**:
- Image URLs include version param: `?v={unix_timestamp}`
- Timestamp derived from `updated_at` field
- Example: `https://cdn.../v2/medium/abc123.webp?v=1705612800`

**Benefits**:
- No CloudFront invalidation API calls needed
- Immediate freshness on updates
- No additional cost
- 1-year cache TTL for immutable versioned URLs

### 9. Real-time Status Updates

**Decision**: Use Phoenix PubSub instead of polling.

**Implementation**:
```elixir
# When processing completes
Phoenix.PubSub.broadcast(Gallformers.PubSub, "image:#{image_id}", {:status_changed, status})

# LiveView subscribes
def mount(_params, _session, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(Gallformers.PubSub, "image:#{image_id}")
  {:ok, socket}
end

def handle_info({:status_changed, status}, socket) do
  {:noreply, assign(socket, :image_status, status)}
end
```

### 10. Cleanup and Maintenance

**Scheduled Oban Job** runs periodically (e.g., daily) to:

1. **Abandoned uploads**: Find `pending` records older than 24 hours where S3 original doesn't exist → delete DB record

2. **Failed processing retry**: Find `pending` records older than 24 hours where S3 original exists → re-queue for processing

3. **Orphan S3 detection** (deferred): Compare S3 objects against DB records, report orphans

### 11. iNaturalist Integration

**Decision**: Client-side iNat API integration.

**Workflow**:
1. User pastes observation URL (e.g., `https://www.inaturalist.org/observations/123456`)
2. LiveView JS hook extracts observation ID, calls iNat API directly from browser
3. Displays metadata (thumbnail, photographer, license, date, location)
4. For multi-photo observations, user can select which photos to import
5. User confirms, LiveView sends image URL(s) + metadata to server
6. Server creates image record, queues Oban job to download and process

**Rate Limits**: iNat allows ~1 req/sec, 10k/day. At our upload volume, no concern. Handle 429 responses gracefully with user-friendly error.

### 12. Error Handling

**Processing errors** displayed as:
- User-friendly message: "Processing failed: [reason]"
- Expandable section: "Technical details: [error_message]"
- Retry button to re-queue for processing

**Presigned URL expiry** (1 hour):
- If upload attempted after expiry, S3 returns 403
- UI shows: "Upload session expired. Please try again."
- Refreshing gets a new presigned URL

**Small image warning**:
- If dimensions < 300x300, show warning in UI
- Allow upload anyway (admin discretion)

### 13. Bulk Operations

Admin can select multiple images for:
- **Bulk delete**: Confirmation dialog, deletes all S3 objects + DB records
- **Bulk metadata edit**: Edit license or other fields for multiple images at once

Note: "Set default" is inherently single-image (only one default per species).

### 14. Article Images

Same processing pipeline as species images with:
- `article_id` instead of `species_id`
- No "default" concept (articles may have different display logic)
- Same size variants and formats

**Open Question**: Specific article image requirements (hero images, inline sizes, thumbnails) need definition before implementation.

### 15. Lightbox Library: GLightbox

**Decision**: Use GLightbox (vanilla JS, ~10KB) for full-size image viewing.

**Rationale**: Lightweight, framework-agnostic (works with LiveView), well-maintained.

### 16. Upload Limits

| Constraint | Value | Enforcement |
|------------|-------|-------------|
| Max file size | 20MB | Client + presigned URL condition |
| Max files per batch | 10 | Client-side validation |
| Concurrent processing | 1 | Oban queue configuration |
| Presigned URL expiry | 1 hour | S3 configuration |

## Migration Plan

### Phase 1: Preparation
1. Create new S3 bucket structure in `us-east-1` (or configure existing bucket)
2. Deploy Oban and new image processing code
3. Disable v1 image uploads (maintenance flag)
4. Create inventory snapshot of v1 images with timestamps

### Phase 2: Migration Execution
Elixir Mix task (`mix images.migrate`) that:
1. Reads existing image records from v1 database
2. Generates new UUID for each image (v1 integer ID stored in legacy_id)
3. Downloads best available source (original → xlarge → large → medium → small)
4. Logs warning if falling back from original
5. Uploads to v2 S3 structure in `us-east-1` with UUID-based keys
6. Queues Oban job for processing (generates WebP variants + JPEG fallback)
7. Creates new image record in v2 schema with UUID
8. Maps v1 fields to v2 schema (preserves all metadata)
9. Tracks progress (6,531 images)

**Concurrency**: Oban processes 1 image at a time; migration queues in batches of 100.

**Estimated duration**: 2-4 hours with Oban workers.

### Phase 3: Verification and Cutover
1. Verify all images display correctly
2. Run delta migration if any images were added during migration
3. Re-enable image uploads (now routes to v2)
4. Update any hardcoded v1 image paths
5. Archive v1 image data (don't delete immediately)

### Rollback
- Keep v1 images in S3 until fully verified
- Migration is additive - can roll back by pointing to v1 paths
- Database migration uses separate records, doesn't affect v1

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Oban processing load | Single worker, 1GB+ RAM requirement documented |
| Large image memory usage | Sequential processing, memory monitored |
| S3 region migration | Transparent via CloudFront; done during re-processing |
| iNat API changes | Only use stable v1 endpoints. Store all metadata locally. |
| Migration disruption | Parallel operation ensures v1 continues working |

## Known Limitations

| Limitation | Rationale |
|------------|-----------|
| No manual image ordering | Automatic source-based grouping is sufficient |
| Single concurrent processing | Protects modest hardware; acceptable for low volume |
| No image editing | Out of scope; use external tools before upload |
| HEIC originals preserved | Can re-process later if needed |

## Open Questions

1. **Article image requirements**: What sizes are needed? Hero images? Inline? Same attribution requirements?
