
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
  source = "../iam_role"
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
  source = "../iam_role"
  name = "terraform-test-codepipeline"
  identifier = "codepipeline.amazonaws.com"
  policy = data.aws_iam_policy_document.codepipeline.json
}


resource "aws_codebuild_project" "frontend" {
  name          = var.name
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
  name = var.name
  role_arn = module.codepipeline_role.iam_role_arn

  artifact_store {
    location = var.s3_bucket.bucket
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
        OAuthToken = var.github_token
        Owner = var.github_owner_name
        Repo = var.github_repository_name
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
        BucketName    = var.s3_bucket.bucket
        Extract = true
      }
    }
  }
}

resource "aws_codepipeline_webhook" "frontend" {
  name = var.name
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
  owner      = var.github_owner_name
  token      = var.github_token
}

resource "github_repository_webhook" "frontend" {
  repository = var.name

  configuration {
    url = aws_codepipeline_webhook.frontend.url
    secret = var.secret
    content_type = "json"
    insecure_ssl = false
  }

  events = ["push"]
}

###############

output "codepipeline_webhook_url" {
  value = aws_codepipeline_webhook.frontend.url
}

output "github_repository_webhook_url" {
  value = github_repository_webhook.frontend.url
}
