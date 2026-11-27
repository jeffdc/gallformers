# Map Tiles (boundaries.pmtiles) Operations

## Overview

Range maps use a PMTiles vector tile file (`boundaries.pmtiles`, ~370MB) containing country and subdivision boundaries from Natural Earth. The file is built locally and uploaded to S3. In production, it's served directly via CloudFront — no local file on the Fly volume.

For build pipeline internals, layer structure, diagnostic scripts, and gotchas, see `services/boundaries/README.md`.

## Architecture

```
Natural Earth shapefiles
    │
    ↓  services/boundaries/build_boundaries.sh
    │
    priv/static/data/boundaries.pmtiles (local dev)
    │
    ↓  aws s3 cp → images bucket
    │
    s3://gallformers-images-us-east-1/tiles/boundaries.pmtiles
    │
    ↓  CloudFront edge cache (/tiles/* → s3-tiles origin)
    │
    https://gallformers.org/tiles/boundaries.pmtiles
    │
    ↓  Browser fetches via HTTP Range Requests
    │
    assets/js/hooks/range_map.js (MapLibre GL JS)
```

PMTiles uses HTTP Range Requests — the browser fetches only the bytes needed for the current map view, not the entire 370MB file. CloudFront's CachingOptimized policy caches the full object and serves partial responses from the edge cache.

## Environment-Specific Flow

### Local Development

| Item | Details |
|------|---------|
| **File** | `priv/static/data/boundaries.pmtiles` |
| **Built by** | `services/boundaries/build_boundaries.sh` |
| **Served by** | Phoenix `Plug.Static` at `/data/boundaries.pmtiles` |
| **Config** | `config :gallformers, tiles_url: "/data/boundaries.pmtiles"` (dev.exs) |

```bash
# Build tiles (~2 minutes, requires gdal, tippecanoe, jq)
cd services/boundaries
./build_boundaries.sh ../../priv/static/data/boundaries.pmtiles

# Hard refresh browser (Cmd+Shift+R) to pick up new tiles
```

Prerequisites: `brew install gdal tippecanoe curl unzip jq`

**Using CloudFront tiles in dev** (skip local build):
```bash
TILES_URL=https://gallformers.org/tiles/boundaries.pmtiles mix phx.server
```

### Preview (gallformers-preview.fly.dev)

| Item | Details |
|------|---------|
| **Source** | Same S3/CloudFront tiles as production |
| **Config** | `TILES_URL` env var → `https://gallformers.org/tiles/boundaries.pmtiles` |
| **CORS** | CloudFront tiles CORS policy allows cross-origin Range requests |

Preview uses the same tiles as production. No local file is baked into the Docker image. Set the `TILES_URL` env var to point at the production CloudFront URL. `fly.preview.toml` doesn't set it in `[env]`, so check `fly secrets list -a gallformers-preview`; without it, preview requests `/tiles/boundaries.pmtiles` from its own app, which has no such file.

If preview ever needs different tiles than production, upload a separate copy to a different S3 path and update `TILES_URL` accordingly.

### Production (gallformers.org)

| Item | Details |
|------|---------|
| **File** | `s3://gallformers-images-us-east-1/tiles/boundaries.pmtiles` |
| **Served by** | The site's CloudFront distribution (`aws_cloudfront_distribution.v2`, `/tiles/*` → `s3-tiles` origin) |
| **Config** | Default `/tiles/boundaries.pmtiles` (relative URL, same domain) |
| **Access** | Public read by bucket policy; CloudFront reaches it through OAC |

The browser requests `/tiles/boundaries.pmtiles` from `gallformers.org`. CloudFront matches the `/tiles/*` path pattern and serves from the S3 images bucket edge cache.

## Updating Map Tiles

When boundaries need to change (new territories, updated geometry, etc.):

```bash
# 1. Rebuild tiles locally
cd services/boundaries
./build_boundaries.sh ../../priv/static/data/boundaries.pmtiles

# 2. Verify coverage against the database
python3 verify_tiles.py

# 3. Upload to S3 images bucket
aws s3 cp priv/static/data/boundaries.pmtiles \
  s3://gallformers-images-us-east-1/tiles/boundaries.pmtiles

# 4. Invalidate CloudFront cache (optional — only needed for immediate effect)
#    The distribution ID is the `id` in: cd infra && tofu state show aws_cloudfront_distribution.v2
aws cloudfront create-invalidation \
  --distribution-id <SITE_DISTRIBUTION_ID> \
  --paths "/tiles/boundaries.pmtiles"
```

No restart needed — CloudFront serves the new file after cache expiration or invalidation.

## Infrastructure

### CloudFront Configuration (infra/cloudfront_v2.tf)

- **Origin**: `s3-tiles` with OAC and no `origin_path`: the `/tiles/` prefix in the URL is the S3 key prefix
- **Cache behavior**: `/tiles/*`, CachingOptimized policy, CORS response headers
- **CORS policy**: `GallformersTilesCORS` — allows Range/If-Range headers from any origin, exposes Content-Range/Content-Length/Accept-Ranges

### S3 Configuration (infra/s3.tf)

- **Bucket**: `gallformers-images-us-east-1`
- **Path**: `tiles/boundaries.pmtiles`
- **Access**: public `s3:GetObject` on every object (bucket policy `images_public_read`); CloudFront uses OAC
- **CORS**: Configured for PUT/GET from production and dev origins

## Git and Docker Status

- `.gitignore`: `priv/static/data/boundaries.pmtiles` — not committed (build artifact)
- `.dockerignore`: `priv/static/data/` — entire directory excluded from build context

## Troubleshooting

### Maps are empty

1. Check that the file exists in S3:
   ```bash
   aws s3 ls s3://gallformers-images-us-east-1/tiles/boundaries.pmtiles
   ```

2. Test the CloudFront URL directly:
   ```bash
   curl -I "https://gallformers.org/tiles/boundaries.pmtiles"
   ```
   Expected: `200 OK` with `Content-Type`, `Accept-Ranges: bytes`

3. Test a Range request:
   ```bash
   curl -H "Range: bytes=0-511" -I "https://gallformers.org/tiles/boundaries.pmtiles"
   ```
   Expected: `206 Partial Content` with `Content-Range` header

4. Check browser console for fetch errors (CORS, 404, etc.)

### Tiles don't match database places

Run the verification script after any tile rebuild:
```bash
cd services/boundaries
python3 verify_tiles.py
```

See `services/boundaries/README.md` for detailed diagnostic scripts.

### Browser shows stale tiles

Hard refresh (Cmd+Shift+R / Ctrl+Shift+R). If tiles still wrong, clear browser cache entirely. PMTiles are aggressively cached by browsers.

To force all users to get new tiles, create a CloudFront cache invalidation (see "Updating Map Tiles" above).
