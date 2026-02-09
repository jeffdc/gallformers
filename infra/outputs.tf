output "v2_distribution_domain" {
  description = "CloudFront domain name for the V2 app distribution"
  value       = aws_cloudfront_distribution.v2.domain_name
}

output "v2_acm_certificate_arn" {
  description = "ARN of the ACM certificate for the V2 distribution"
  value       = aws_acm_certificate.v2.arn
}

output "v2_acm_validation_records" {
  description = "DNS records needed to validate the ACM certificate"
  value       = aws_acm_certificate.v2.domain_validation_options
}

output "nameservers_org" {
  description = "Route53 nameservers for gallformers.org — set these at Namecheap"
  value       = aws_route53_zone.org.name_servers
}

output "nameservers_com" {
  description = "Route53 nameservers for gallformers.com — set these at Namecheap"
  value       = aws_route53_zone.com.name_servers
}
