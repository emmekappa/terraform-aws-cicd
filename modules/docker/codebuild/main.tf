data "aws_caller_identity" "default" {}

data "aws_region" "default" {}

# Define composite variables for resources
module "label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.0"
  namespace  = "${var.namespace}"
  name       = "${var.name}"
  stage      = "${var.stage}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
}

locals {
  ## This is the magic where a map of a list of maps is generated
  ## and used to conditionally add the cache bucket option to the
  ## aws_codebuild_project
  cache_def = {
    "true" = [{
      type     = "local"
      modes    = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
    }]

    "false" = []
  }

  # Final Map Selected from above
  cache = "${local.cache_def[var.local_cache_enabled]}"
}

resource "aws_iam_role" "default" {
  name               = "${module.label.id}"
  assume_role_policy = "${data.aws_iam_policy_document.role.json}"
}

data "aws_iam_policy_document" "role" {
  statement {
    sid = ""

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_policy" "default" {
  name   = "${module.label.id}"
  path   = "/service-role/"
  policy = "${data.aws_iam_policy_document.permissions.json}"
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid = ""

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetAuthorizationToken",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ssm:GetParameters",
    ]

    effect = "Allow"

    resources = [
      "*",
    ]
  }
}

resource "aws_iam_role_policy_attachment" "default" {
  policy_arn = "${aws_iam_policy.default.arn}"
  role       = "${aws_iam_role.default.id}"
}

resource "aws_codebuild_project" "default" {
  name          = "${module.label.id}"
  service_role  = "${aws_iam_role.default.arn}"
  cache         = ["${local.cache}"]
  tags          = "${module.label.tags}"
  badge_enabled = true

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "${var.build_compute_type}"
    image           = "${var.build_image}"
    type            = "LINUX_CONTAINER"
    privileged_mode = "${var.privileged_mode}"

    environment_variable = [
      {
        "name"  = "AWS_REGION"
        "value" = "${signum(length(var.aws_region)) == 1 ? var.aws_region : data.aws_region.default.name}"
      },
      {
        "name"  = "AWS_ACCOUNT_ID"
        "value" = "${signum(length(var.aws_account_id)) == 1 ? var.aws_account_id : data.aws_caller_identity.default.account_id}"
      },
      {
        "name"  = "IMAGE_REPO_NAME"
        "value" = "${signum(length(var.image_repo_name)) == 1 ? var.image_repo_name : "UNSET"}"
      },
      {
        "name"  = "GITHUB_TOKEN"
        "value" = "${signum(length(var.github_token)) == 1 ? var.github_token : "UNSET"}"
      },
      "${var.environment_variables}",
    ]
  }

  source {
    type                = "GITHUB"
    location            = "https://github.com/${var.repo_owner}/${var.repo_name}.git"
    git_clone_depth     = 1
    report_build_status = true
  }
}

resource "aws_codebuild_webhook" "default" {
  project_name = "${aws_codebuild_project.default.name}"
  depends_on   = ["aws_codebuild_project.default"]
}
