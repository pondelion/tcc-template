
### S3 bucket ###

resource "aws_s3_bucket" "deploy_bucket" {
  bucket = var.bucket_name
  force_destroy = true
  versioning {
    enabled = true
  }
}

### Code Pileline / Code Build ###

module "codepipeline" {
  source = "./modules/codepipeline"
  name = var.app_name
  s3_bucket = aws_s3_bucket.deploy_bucket
  github_token = var.GITHUB_TOKEN
  secret = var.secret
  github_owner_name = var.github_owner_name
  github_repository_name = var.github_repository_name
}

### Cloud Front ###

module "cloudfront" {
  source = "./modules/cloudfront/cloudfront_domain"
  s3_bucket = aws_s3_bucket.deploy_bucket
}

# module "cloudfront" {
#   source = "./modules/cloudfront/route53_domain"
#   s3_bucket = aws_s3_bucket.deploy_bucket
# }