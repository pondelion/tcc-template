
resource "aws_cloudfront_origin_access_identity" "frontend" {
  comment = "terraform test"
}

resource "aws_cloudfront_distribution" "frontend" {

  origin {
    domain_name = var.s3_bucket.bucket_regional_domain_name
    origin_id   = var.s3_bucket.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "terraform test"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.s3_bucket.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_caching_min_ttl = 3000
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  custom_error_response {
    error_caching_min_ttl = 3000
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
  }

  price_class = "PriceClass_200"

  viewer_certificate {
    cloudfront_default_certificate = true
  }

#   aliases = [var.site_domain]

#   viewer_certificate {
#     acm_certificate_arn      = aws_acm_certificate_validation.acm_cert.certificate_arn
#     ssl_support_method       = "sni-only"
#     minimum_protocol_version = "TLSv1"
#   }
}

data "aws_iam_policy_document" "s3_deploy_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = [
        "${var.s3_bucket.arn}/*.json",
        "${var.s3_bucket.arn}/*.ico",
        "${var.s3_bucket.arn}/*.html",
        "${var.s3_bucket.arn}/*.png",
        "${var.s3_bucket.arn}/*.txt",
        "${var.s3_bucket.arn}/static/*",
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.frontend.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "deploy_bucket" {
  bucket = var.s3_bucket.id
  policy = data.aws_iam_policy_document.s3_deploy_bucket.json
}

##########

output "aws_cloudfront_distribution_url" {
  value = aws_cloudfront_distribution.frontend.domain_name
}
