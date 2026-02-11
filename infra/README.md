# Gallformers Infrastructure (OpenTofu)

Infrastructure as Code for Gallformers AWS resources using OpenTofu.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ AWS (us-east-1)                                                             │
│                                                                             │
│  ┌─────────────────────┐     ┌─────────────────────┐     ┌───────────────┐ │
│  │ S3: images          │────►│ CloudFront          │────►│ Users (CDN)   │ │
│  │ (gallformers-       │     │ Origin Access       │     │               │ │
│  │  images-us-east-1)  │     │ Control             │     │               │ │
│  │ PUBLIC READ         │     │                     │     │               │ │
│  └─────────────────────┘     └─────────────────────┘     └───────────────┘ │
│          ▲                                                                  │
│          │ (s3:Put*)                                                        │
│          │                                                                  │
│  ┌───────┴──────────────┐                                                   │
│  │ IAM: s3-upload       │                                                   │
│  │ Policy: GallformersImageUpload                                           │
│  └──────────────────────┘                                                   │
│                                                                             │
│  ┌──────────────────────┐     ┌──────────────────────┐                     │
│  │ S3: gallformers-     │     │ S3: gallformers-     │                     │
│  │     backups          │     │     full-backups     │                     │
│  │ (sanitized snapshots)│     │ (private, has PII)   │                     │
│  │ + Litestream backups │     │                      │                     │
│  └──────────┬───────────┘     └──────────┬───────────┘                     │
│             │                            │                                  │
│             └────────────┬────────────────┘                                 │
│                          │                                                  │
│                          ▼                                                  │
│          ┌──────────────────────────────┐                                   │
│          │ IAM: litestream-gallformers  │◄──── Fly.io (Litestream)         │
│          │ Policy: LitestreamGallforms  │◄──── GitHub Actions (snapshots)  │
│          │         Backup               │                                   │
│          └──────────────────────────────┘                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Region Strategy

All AWS resources are deployed to **`us-east-1`** (N. Virginia) to match Fly.io's `iad` datacenter for low latency.

## Resources

### S3 Buckets

#### gallformers-images-us-east-1
- **Purpose:** Production images (original, small, medium, large, xlarge)
- **Access:** Public read via CloudFront CDN only (Origin Access Control)
- **Versioning:** Enabled
- **Upload:** `s3-upload` IAM user (Fly.io/V2 app secrets)

#### gallformers-backups
- **Purpose:** Database backups with mixed access patterns
  - `litestream/*` - Continuous DB backups (private, used by Litestream for replication)
  - `public/*` - Daily sanitized snapshots (public read, no PII)
- **Access:**
  - Private for Litestream backups (Fly.io via `litestream-gallformers` IAM user)
  - Public read for `public/*` prefix only
- **Versioning:** Enabled
- **Public URL:** https://gallformers-backups.s3.amazonaws.com/public/gallformers.sqlite

#### gallformers-full-backups
- **Purpose:** Full database backups containing PII
- **Access:** Fully private (no public access)
- **Versioning:** Enabled
- **Used by:** `litestream-gallformers` IAM user (Fly.io + GitHub Actions)

### CDN

- **CloudFront distribution** - Serves images via Origin Access Control (OAC), no public S3 access needed

### IAM

- **`s3-upload`** - Image uploads to S3 (credentials in Fly.io/V2 app secrets)
- **`litestream-gallformers`** - Database backups (credentials in Fly.io secrets + GitHub Actions secrets)

## Deployment

```bash
# Plan changes
tofu plan

# Apply changes
tofu apply

# Import existing resources
tofu import aws_s3_bucket.images gallformers-images-us-east-1
```

## Next Steps

See [Beads](../.beads/) for tracked infrastructure work (issues tagged with `infra`).

Key runbooks:
- [backup-setup.md](../docs/backup-setup.md) - S3/IAM configuration details
