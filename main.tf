# Specify the AWS region to deploy resources in
provider "aws" {
  region = "us-east-1"
}

# Create an S3 bucket to store static website files
resource "aws_s3_bucket" "static_site" {
  bucket = "smart-static-site-s3-bucket-009"

  tags = {
    Name = "StaticSiteBucket"
  }
}

# Configure the S3 bucket to host a static website with index and error pages
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.static_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Request a public SSL certificate for your domain using DNS validation
resource "aws_acm_certificate" "cert" {
  domain_name       = "www.devrisi.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "devrisi-cert-smart-site-009"
  }
}

# Fetch existing public hosted zone for your domain from Route 53
data "aws_route53_zone" "primary" {
  name         = "devrisi.com."
  private_zone = false
}

# Create DNS records in Route 53 to validate the ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.primary.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

# Complete the certificate validation process using the DNS records
resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Create a CloudFront distribution as a CDN for the static website
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for smart static site 009"
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.waf_acl.arn
  aliases             = ["www.devrisi.com"]

  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "StaticSmartSiteS3Origin009"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    target_origin_id       = "StaticSmartSiteS3Origin009"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "CDN-smart-site-009"
  }
}

# Create an Origin Access Identity (OAI) to restrict direct S3 access
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "Access identity for smart static site 009"
}

# Attach a bucket policy allowing only CloudFront OAI to access the S3 bucket
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.static_site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_site.arn}/*"
      }
    ]
  })
}

# Create a DNS 'A' record in Route 53 to point your domain to CloudFront
resource "aws_route53_record" "site" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "www.devrisi.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# Define a Web ACL (WAF) to secure CloudFront with managed AWS rules
resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "Smart-static-site-waf-009"
  description = "WAF ACL for www.devrisi.com"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "smart-site-waf"
    sampled_requests_enabled   = true
  }

  # Rule: Common attack protection (e.g. SQL injection, XSS)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule: Blocks traffic from known bad IPs
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AmazonIpReputation"
      sampled_requests_enabled   = true
    }
  }

  # Rule: Blocks anonymous sources (Tor nodes, proxies)
  rule {
    name     = "AWS-AWSManagedRulesAnonymousIpList"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AnonymousIpList"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Name = "WAF for smart static site"
  }
}

