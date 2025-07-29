# Secure AWS Static Website Setup with Terraform

This project uses Terraform to deploy a secure and scalable static website architecture on AWS. It includes components like S3, CloudFront, Route53, ACM (SSL), and AWS WAF for layered security and performance.

---

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Configuration Details](#configuration-details)
- [Security Best Practices](#security-best-practices)
- [Conclusion](#conclusion)

---

## Overview

The Terraform configuration creates a complete static website infrastructure with the following features:

- S3 Bucket for hosting static files
- CloudFront CDN for performance and HTTPS access
- AWS ACM for SSL certificate
- Route 53 for DNS management
- WAFv2 for protection against common attacks

---

## Prerequisites

- Terraform v1.0 or newer
- AWS account with access to S3, CloudFront, Route 53, ACM, and WAF
- A registered domain (e.g., `devrisi.com`)
- Hosted Zone in Route 53

---

## Project Structure

```text
/aws-secure-smart-static-site
├── main.tf        # Terraform configuration
├── README.md      # This file
```


## Configuration Details

### 1. AWS Provider
Defines the AWS region where resources will be created.

```
provider "aws" {
  region = "us-east-1"
}
```

### 2. S3 Bucket
Creates the S3 bucket to store the website content.

```
resource "aws_s3_bucket" "static_site" {
  bucket = "smart-static-site-s3-bucket-009"
}
```
### 3. S3 Website Hosting Configuration
Enables the S3 bucket to serve static websites with default index and error pages.

```
resource "aws_s3_bucket_website_configuration" "website" {
  index_document { suffix = "index.html" }
  error_document { key = "error.html" }
}
```
### 4. ACM SSL Certificate
Requests a public SSL certificate for your domain via DNS validation.

```
resource "aws_acm_certificate" "cert" {
  domain_name       = "www.devrisi.com"
  validation_method = "DNS"
}
```
### 5. Route 53 Hosted Zone & DNS Validation
Automatically creates the DNS validation records for ACM using Route 53.

```
resource "aws_route53_record" "cert_validation" { ... }
```
### 6. CloudFront Distribution
Connects CloudFront with your S3 bucket, enforces HTTPS, and improves global delivery.

```
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "StaticSmartSiteS3Origin009"
  }
}
```
### 7. CloudFront Origin Access Identity
Restricts direct access to S3 by using a signed CloudFront identity.

```
resource "aws_cloudfront_origin_access_identity" "oai" { ... }
```
### 8. S3 Bucket Policy
Grants CloudFront's OAI permission to read content from the S3 bucket.

```
resource "aws_s3_bucket_policy" "bucket_policy" { ... }
```
### 9. Route 53 DNS Record for Website
Creates an "A" record that points www.devrisi.com to the CloudFront distribution.

```
resource "aws_route53_record" "site" { ... }
```
### 10. AWS WAFv2 Web ACL
Protects the CloudFront distribution using AWS-managed rules such as:
- CommonRuleSet
- Amazon IP Reputation List
- Anonymous IP List

```
resource "aws_wafv2_web_acl" "waf_acl" { ... }
```


## Security Best Practices

- HTTPS Only: Enforced via CloudFront viewer protocol policy

- Origin Protection: Uses CloudFront OAI to block direct S3 access

- WAF Rules: Protects against common web attacks and bots

- Least Privilege: Policies only grant minimum required access

## Conclusion

This Terraform project securely deploys a static website architecture using S3 and CloudFront, backed with SSL (ACM), custom DNS (Route 53), and robust protection via WAF. It’s suitable for hosting personal websites, landing pages, and documentation portals securely and cost-effectively.

## Finished Configuration (main.tf)

```
provider "aws" {
  region = "us-east-1"
}

## Creation of S3 bucket
resource "aws_s3_bucket" "static_site" {
  bucket = "smart-static-site-s3-bucket-009"

  tags = {
    Name = "StaticSiteBucket"
  }
}

## Makinf the S3 bucket a statck website
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.static_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

## Creation of AWS ACM certificate
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


data "aws_route53_zone" "primary" {
  name         = "devrisi.com."
  private_zone = false
}


## Create the ACM records in Route53
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


resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for smart static site 009"
  default_root_object = "index.html"
  web_acl_id = aws_wafv2_web_acl.waf_acl.arn

  aliases = ["www.devrisi.com"]

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


resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "Access identity for smart static site 009"
}

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
```


