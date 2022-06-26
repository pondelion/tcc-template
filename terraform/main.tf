
#### S3 bucket ####

resource "aws_s3_bucket" "deploy_bucket" {
  bucket = var.bucket_name
  force_destroy = true
  versioning {
    enabled = true
  }
}


### Code Pileline / Code Build ###

data "aws_iam_policy_document" "codebuild" {
  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

module "codebuild_role" {
  source = "./modules/iam_role"
  name = "terraform-test-codebuild"
  identifier = "codebuild.amazonaws.com"
  policy = data.aws_iam_policy_document.codebuild.json
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
      "iam:PassRole",
    ]
  }
}

module "codepipeline_role" {
  source = "./modules/iam_role"
  name = "terraform-test-codepipeline"
  identifier = "codepipeline.amazonaws.com"
  policy = data.aws_iam_policy_document.codepipeline.json
}


resource "aws_codebuild_project" "frontend" {
  name          = "terraform-codepipeline-cloudfront-test"
  description   = "terraform-codepipeline-cloudfront-test"
#   build_timeout = "60"
  service_role  = module.codebuild_role.iam_role_arn

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  source {
    type                        = "CODEPIPELINE"
  }

  artifacts {
    type                        = "CODEPIPELINE"
  }
}


resource "aws_codepipeline" "frontend" {
  name = "terraform-codepipeline-cloudfront-test"
  role_arn = module.codepipeline_role.iam_role_arn

  artifact_store {
    location = aws_s3_bucket.deploy_bucket.bucket
    type = "S3"
  }

  stage {
    name = "Source"

    action {
      name = "Source"
      category = "Source"
      owner = "ThirdParty"
      provider = "GitHub"
      version = 1
      output_artifacts = [ "Source" ]
      configuration = {
        OAuthToken = var.GITHUB_TOKEN
        Owner = "pondelion"
        Repo = "terraform-codepipeline-cloudfront-test"
        Branch = "deploy"
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["Source"]
      output_artifacts = ["Build"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.frontend.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      input_artifacts = ["Build"]

      configuration = {
        BucketName    = var.bucket_name
        Extract = true
      }
    }
  }
}

resource "aws_codepipeline_webhook" "frontend" {
  name = "frontend"
  target_pipeline = aws_codepipeline.frontend.name
  target_action = "Source"
  authentication = "GITHUB_HMAC"

  authentication_configuration {
    secret_token = var.secret
  }

  filter {
    json_path = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

provider "github" {
  owner      = "pondelion"
  token      = var.GITHUB_TOKEN
}

resource "github_repository_webhook" "frontend" {
  repository = "terraform-codepipeline-cloudfront-test"

  configuration {
    url = aws_codepipeline_webhook.frontend.url
    secret = var.secret
    content_type = "json"
    insecure_ssl = false
  }

  events = ["push"]
}

output "codepipeline_webhook_url" {
  value = aws_codepipeline_webhook.frontend.url
}

output "github_repository_webhook_url" {
  value = github_repository_webhook.frontend.url
}


### Cloud Front ###

# locals {
#   site_url = "${var.domain}"
# }

resource "aws_cloudfront_origin_access_identity" "frontend" {
  comment = "terraform test"
}

resource "aws_cloudfront_distribution" "frontend" {

  origin {

    domain_name = aws_s3_bucket.deploy_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.deploy_bucket.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "terraform test"
  default_root_object = "app/build/index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.deploy_bucket.id

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

  # CloudFrontドメインの証明書を利用
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
    resources = ["${aws_s3_bucket.deploy_bucket.arn}/app/build/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.frontend.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "deploy_bucket" {
  bucket = aws_s3_bucket.deploy_bucket.id
  policy = data.aws_iam_policy_document.s3_deploy_bucket.json
}

output "aws_cloudfront_distribution_url" {
  value = aws_cloudfront_distribution.frontend.domain_name
}