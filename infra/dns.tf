# Route53 DNS for gallformers.org and gallformers.com.
#
# After applying, update nameservers at Namecheap to the values in the
# "nameservers_org" and "nameservers_com" outputs, then wait for propagation.

# -----------------------------------------------------------------------------
# Hosted Zones
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "org" {
  name = "gallformers.org"

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

resource "aws_route53_zone" "com" {
  name = "gallformers.com"

  tags = {
    Project   = var.project
    ManagedBy = "opentofu"
  }
}

# -----------------------------------------------------------------------------
# Apex domains → CloudFront (ALIAS records)
# -----------------------------------------------------------------------------
# Route53 ALIAS records work at the zone apex — no need for the old A record
# pointing at the DigitalOcean droplet (157.245.243.86).

resource "aws_route53_record" "org_apex" {
  zone_id = aws_route53_zone.org.zone_id
  name    = "gallformers.org"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.v2.domain_name
    zone_id                = aws_cloudfront_distribution.v2.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "com_apex" {
  zone_id = aws_route53_zone.com.zone_id
  name    = "gallformers.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.v2.domain_name
    zone_id                = aws_cloudfront_distribution.v2.hosted_zone_id
    evaluate_target_health = false
  }
}

# IPv6 ALIAS records for the apex domains.
resource "aws_route53_record" "org_apex_aaaa" {
  zone_id = aws_route53_zone.org.zone_id
  name    = "gallformers.org"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.v2.domain_name
    zone_id                = aws_cloudfront_distribution.v2.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "com_apex_aaaa" {
  zone_id = aws_route53_zone.com.zone_id
  name    = "gallformers.com"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.v2.domain_name
    zone_id                = aws_cloudfront_distribution.v2.hosted_zone_id
    evaluate_target_health = false
  }
}

# -----------------------------------------------------------------------------
# www → CloudFront
# -----------------------------------------------------------------------------

resource "aws_route53_record" "org_www" {
  zone_id = aws_route53_zone.org.zone_id
  name    = "www.gallformers.org"
  type    = "CNAME"
  ttl     = 600
  records = [aws_cloudfront_distribution.v2.domain_name]
}

resource "aws_route53_record" "com_www" {
  zone_id = aws_route53_zone.com.zone_id
  name    = "www.gallformers.com"
  type    = "CNAME"
  ttl     = 600
  records = [aws_cloudfront_distribution.v2.domain_name]
}

# -----------------------------------------------------------------------------
# ACM Certificate Validation
# -----------------------------------------------------------------------------
# Dynamically creates the CNAME records needed for ACM DNS validation.
# This replaces the manually-managed validation CNAMEs in DigitalOcean.

locals {
  # Build a map of validation options keyed by domain name.
  # Each ACM cert domain needs one CNAME record for validation.
  acm_validation_options = {
    for opt in aws_acm_certificate.v2.domain_validation_options :
    opt.domain_name => {
      name    = opt.resource_record_name
      type    = opt.resource_record_type
      value   = opt.resource_record_value
      zone_id = endswith(opt.domain_name, ".com") ? aws_route53_zone.com.zone_id : aws_route53_zone.org.zone_id
    }
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = local.acm_validation_options

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.value]
}
