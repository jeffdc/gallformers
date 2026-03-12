# Private S3 Bucket for Full Database Backups

This document describes the private S3 bucket used for storing full (unsanitized) database backups.

## Overview

| Property | Value |
|----------|-------|
| Bucket name | `gallformers-full-backups` |
| Region | `us-east-1` |
| Access | Private (IAM only) |
| Versioning | Enabled |
| Created | 2026-01-18 |

## Purpose

This bucket stores **full database backups containing PII** (user emails, etc.). These backups are NOT sanitized and should never be made public.

Use cases:
- Disaster recovery requiring user data
- Legal/compliance data retention
- Point-in-time recovery with full user context

## Access Control

**IAM Policy**: `LitestreamGallformersBackup` (shared with `gallformers-backups` bucket; name is historical from the SQLite/Litestream era)

**IAM User**: `litestream-gallformers` (name is historical)

The same credentials used for database backups have access to this bucket. No additional secrets are needed.

## Comparison with Other Buckets

| Bucket | Access | Contains PII | Use |
|--------|--------|--------------|-----|
| `gallformers-images-us-east-1` | Public | No | Production images |
| `gallformers-backups` | Mixed | No | Database backups (private) + sanitized snapshots (public) |
| `gallformers-full-backups` | Private | **Yes** | Full unsanitized backups |

## GitHub Actions Usage

The daily backup workflow can optionally upload a full backup here before sanitization:

```yaml
- name: Upload full backup (private)
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.LITESTREAM_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.LITESTREAM_SECRET_ACCESS_KEY }}
    AWS_DEFAULT_REGION: us-east-1
  run: |
    aws s3 cp gallformers.dump s3://gallformers-full-backups/$(date +%Y-%m-%d)/gallformers.dump
```

## Lifecycle Policy (Optional)

To control costs, consider adding a lifecycle rule to expire old backups:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket gallformers-full-backups \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "ExpireOldBackups",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "Expiration": {"Days": 90},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 30}
    }]
  }'
```

## Security Notes

- Never make this bucket public
- Never add a bucket policy allowing public access
- Audit access periodically via CloudTrail
- Consider enabling S3 Object Lock for compliance requirements
