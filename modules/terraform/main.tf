provider "aws" {
  region  = var.aws_region
  version = "~> 2.12"
}

data "aws_region" "default" {
}

data "aws_caller_identity" "default" {
}

module "codebuild_terraform" {
  source             = "./codebuild"
  namespace          = var.namespace
  name               = var.name
  stage              = var.stage
  build_image        = var.build_image
  build_compute_type = var.build_compute_type
  buildspec          = var.buildspec
  delimiter          = var.delimiter
  attributes         = concat(var.attributes, ["build"])
  tags               = var.tags
  privileged_mode    = var.privileged_mode
  aws_region         = signum(length(var.aws_region)) == 1 ? var.aws_region : data.aws_region.default.name
  aws_account_id     = signum(length(var.aws_account_id)) == 1 ? var.aws_account_id : data.aws_caller_identity.default.account_id
  github_token       = var.github_token
  repo_owner         = var.repo_owner
  repo_name          = var.repo_name
  slack_token        = var.slack_token
  slack_channel      = var.slack_channel
}

module "codepipeline_terraform" {
  source    = "./codepipeline"
  namespace = var.namespace
  name      = var.name
  stage     = var.stage

  # Application repository on GitHub
  github_oauth_token = var.github_token
  repo_owner         = var.repo_owner
  repo_name          = var.repo_name
  branches           = var.branches

  # http://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref.html
  # http://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html
  build_image = var.build_image

  build_compute_type = var.build_compute_type

  # These attributes are optional, used as ENV variables when building Docker images and pushing them to ECR
  # For more info:
  # http://docs.aws.amazon.com/codebuild/latest/userguide/sample-docker.html
  # https://www.terraform.io/docs/providers/aws/r/codebuild_project.html
  privileged_mode = var.privileged_mode

  aws_region                     = var.aws_region
  aws_account_id                 = var.aws_account_id
  codebuild_plan_project_name    = module.codebuild_terraform.plan_project_name
  codebuild_plan_project_id      = module.codebuild_terraform.plan_project_id
  codebuild_apply_project_name   = module.codebuild_terraform.apply_project_name
  codebuild_apply_project_id     = module.codebuild_terraform.apply_project_id
  codebuild_role_arn             = module.codebuild_terraform.role_arn
  terraform_state_bucket         = var.terraform_state_bucket
  request_approval_sns_topic_arn = var.request_approval_sns_topic_arn
}

