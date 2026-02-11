# S3 bucket for gallformers images (us-east-1)

resource "aws_s3_bucket" "images" {
  bucket = "gallformers-images-us-east-1"

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "images_public_read" {
  bucket = aws_s3_bucket.images.id

  # Ensure public access block is applied first so the policy isn't rejected
  depends_on = [aws_s3_bucket_public_access_block.images]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.images.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_origins = [
      "https://gallformers.org",
      "https://www.gallformers.org",
      "https://gallformers.com",
      "https://www.gallformers.com",
      "https://gallformers.fly.dev",
      "http://localhost:4000"
    ]
    allowed_methods = ["PUT", "GET"]
    allowed_headers = ["Content-Type", "Content-Length"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# -----------------------------------------------------------------------------
# Backup Buckets
# -----------------------------------------------------------------------------

# S3 bucket for Litestream continuous backups and daily sanitized snapshots
#
# Access patterns:
#   - litestream/* - Private, continuous DB backups via Litestream
#   - public/* - Public read, daily sanitized snapshots (no PII)
#
# Public URL: https://gallformers-backups.s3.amazonaws.com/public/gallformers.sqlite

resource "aws_s3_bucket" "backups" {
  bucket = "gallformers-backups"

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "backups_public_snapshots" {
  bucket = aws_s3_bucket.backups.id

  # Ensure public access block is applied first so the policy isn't rejected
  depends_on = [aws_s3_bucket_public_access_block.backups]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadSnapshots"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backups.arn}/public/*"
      }
    ]
  })
}

# S3 bucket for full database backups (contains PII)
#
# Fully private - no public access allowed.
# Used for complete database snapshots including user data.

resource "aws_s3_bucket" "full_backups" {
  bucket = "gallformers-full-backups"

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

resource "aws_s3_bucket_versioning" "full_backups" {
  bucket = aws_s3_bucket.full_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "full_backups" {
  bucket = aws_s3_bucket.full_backups.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
