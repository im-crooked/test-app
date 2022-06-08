#
# Creates CodeBuild project to build React app and output artifacts to S3
# used for the web app.
#
# Author: Sanjay M <sanjay@alvyl.com>



# Variables

variable "allowed_accounts_by_workspace" {
  default = {
    "mumbai-global"      = "818373935168",
    "mumbai-sandbox"     = "757184591234",
    "mumbai-development" = "351496573246",
    "mumbai-staging"     = "079128785150",
    "mumbai-production"  = "259039760994"
  }
}

variable "region_by_workspace" {
  default = {
    "mumbai-global"      = "ap-south-1",
    "mumbai-sandbox"     = "ap-south-1",
    "mumbai-development" = "ap-south-1",
    "mumbai-staging"     = "ap-south-1",
    "mumbai-production"  = "ap-south-1"
  }
}

variable "environment_by_workspace" {
  default = {
    "mumbai-global"      = "mum-glb",
    "mumbai-sandbox"     = "mum-snd",
    "mumbai-development" = "mum-dev",
    "mumbai-staging"     = "mum-stg",
    "mumbai-production"  = "mum-prd"
  }
}


locals {
  namespace              = "avcp-silkworm"
  environment_account_id = var.allowed_accounts_by_workspace[terraform.workspace]
  region                 = var.region_by_workspace[terraform.workspace]

  environment      = var.environment_by_workspace[terraform.workspace]
  environment_safe = replace(local.environment, "-", "_")

  profile = "${local.namespace}-${local.environment}"
}

terraform {

  required_version = "~> 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    profile        = "avcp-silkworm-mum-glb"
    region         = "ap-south-1"
    bucket         = "avcp-silkworm-mum-glb-global-store-infra-state"
    key            = "web-pipeline-build/terraform.tfstate"
    dynamodb_table = "avcp-silkworm-mum-glb-global-store-infra-state-lock"
    encrypt        = "true"
  }
}

# Provider configurations

provider "aws" {
  profile = local.profile
  region  = local.region

  allowed_account_ids = [
    local.environment_account_id
  ]
}


# Data Sources

# data "aws_ssm_parameter" "web_app_s3_bucket" {
#   name  = foo
#   value = deploy-web-app-test
# }

# data "aws_s3_bucket" "web_app_s3_bucket" {
#   bucket = data.aws_ssm_parameter.web_app_s3_bucket.value
# }

##
# Resources
##

# Creating IAM Role for codebuild project
resource "aws_iam_role" "test-app-iam" {
  name = "test-app-iam-web-app"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "test-app-iam-policy" {
  role = aws_iam_role.test-app-iam.name

  policy = <<POLICY
{ 
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ssm:GetParameters"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
POLICY
}


# Creating CodeBuild project with github source
resource "aws_codebuild_project" "test-app-codebuild" {
  name          = "test-app-codebuild-web-app"
  description   = "CodeBuild Project for test-app"
  build_timeout = "10"
  service_role  = aws_iam_role.test-app-iam.arn

  # TODO: Caching

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:2.0"
    type         = "LINUX_CONTAINER"


    environment_variable {
      name  = "GENERATE_SOURCEMAP"
      value = "false"
    }

    environment_variable {
      name  = "WEB_APP_S3_BUCKET"
      type  = "PARAMETER_STORE"
      value = "deploy-web-app-test"
    }

    environment_variable {
      name  = "REACT_APP_USERPOOL_ID"
      type  = "PARAMETER_STORE"
      value = "ap-south-1_DiBaUHrNq"
    }

    environment_variable {
      name  = "REACT_APP_CLIENT_ID"
      type  = "PARAMETER_STORE"
      value = "3cjv6p2sf0djn6g6r5rggl06h6"
    }

    environment_variable {
      name  = "REACT_APP_BACKEND_URL"
      type  = "PARAMETER_STORE"
      value = "https://api.snd.silkworm.alvyl.io"
    }

    # TODO: Add API URL as environment variable
  }

  logs_config {
    cloudwatch_logs {
      group_name = "test-app"
    }
  }

  #   source {
  #     type     = "BITBUCKET"
  #     location = "https://hari-alvyl@bitbucket.org/alvyl-cloud/avcp-silkworm.git"
  #     # git clone depth needs to be 3 to prevent "no branch" state of repo.
  #     git_clone_depth = 3 # Clone depth has to be > 3 for HEAD~1 to work
  #     buildspec       = "web-pipeline-build/buildspec.yml"
  #   }

  source {
    type            = "GITHUB"
    location        = "https://github.com/im-crooked/test-app.git"
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  tags = {
    Environment = "dev"
  }
}

# Creating web hook on CodeBuild Project
resource "aws_codebuild_webhook" "test-app-webhook" {
  project_name = aws_codebuild_project.test-app-codebuild.name

  filter_group {

    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_MERGED"
    }

    filter {
      type    = "BASE_REF"
      pattern = "^refs/heads/master$"
    }
  }
}

resource "aws_codebuild_source_credential" "test-app-webhook" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = "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"
}

# Creating web hook with pull-request:merged webhook enabled on Github
resource "github_repository_webhook" "test-app-webhook" {

  active = true
  events = ["push"]
  #   name       = "test-app-webhook"
  repository = "https://github.com/im-crooked/test-app.git"

  configuration {
    url          = aws_codebuild_webhook.test-app-webhook.payload_url
    secret       = aws_codebuild_webhook.test-app-webhook.secret
    content_type = "json"
    insecure_ssl = false
  }
}

