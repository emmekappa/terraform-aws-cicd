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

resource "aws_s3_bucket" "cache_bucket" {
  count         = "${var.cache_enabled == "true" ? 1 : 0}"
  bucket        = "${local.cache_bucket_name_normalised}"
  acl           = "private"
  force_destroy = true
  tags          = "${module.label.tags}"

  lifecycle_rule {
    id      = "codebuildcache"
    enabled = true

    prefix = "/"
    tags   = "${module.label.tags}"

    expiration {
      days = "${var.cache_expiration_days}"
    }
  }
}

resource "random_string" "bucket_prefix" {
  length  = 12
  number  = false
  upper   = false
  special = false
  lower   = true
}

locals {
  cache_bucket_name = "${module.label.id}${var.cache_bucket_suffix_enabled == "true" ? "-${random_string.bucket_prefix.result}" : "" }"

  ## Clean up the bucket name to use only hyphens, and trim its length to 63 characters.
  ## As per https://docs.aws.amazon.com/AmazonS3/latest/dev/BucketRestrictions.html
  cache_bucket_name_normalised = "${substr(join("-", split("_", lower(local.cache_bucket_name))), 0, min(length(local.cache_bucket_name),63))}"

  ## This is the magic where a map of a list of maps is generated
  ## and used to conditionally add the cache bucket option to the
  ## aws_codebuild_project
  cache_def = {
    "true" = [{
      type     = "S3"
      location = "${var.cache_enabled == "true" ? aws_s3_bucket.cache_bucket.0.bucket : "none" }"
    }]

    "false" = []
  }

  # Final Map Selected from above
  cache = "${local.cache_def[var.cache_enabled]}"
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

resource "aws_iam_policy" "default_cache_bucket" {
  count  = "${var.cache_enabled == "true" ? 1 : 0}"
  name   = "${module.label.id}-cache-bucket"
  path   = "/service-role/"
  policy = "${data.aws_iam_policy_document.permissions_cache_bucket.json}"
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
    ]

    effect = "Allow"

    resources = [
      "*",
    ]
  }
}

data "aws_iam_policy_document" "permissions_cache_bucket" {
  statement {
    sid = ""

    actions = [
      "s3:*",
    ]

    effect = "Allow"

    resources = [
      "${aws_s3_bucket.cache_bucket.arn}",
      "${aws_s3_bucket.cache_bucket.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy_attachment" "default" {
  policy_arn = "${aws_iam_policy.default.arn}"
  role       = "${aws_iam_role.default.id}"
}

resource "aws_iam_role_policy_attachment" "default_cache_bucket" {
  count      = "${var.cache_enabled == "true" ? 1 : 0}"
  policy_arn = "${element(aws_iam_policy.default_cache_bucket.*.arn, count.index)}"
  role       = "${aws_iam_role.default.id}"
}

resource "aws_codebuild_project" "default" {
  name         = "${module.label.id}"
  service_role = "${aws_iam_role.default.arn}"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  # The cache as a list with a map object inside.
  cache = ["${local.cache}"]

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
    type            = "GITHUB"
    location        = "https://github.com/${var.repo_owner}/${var.repo_name}.git"
    git_clone_depth = 1
  }

  tags = "${module.label.tags}"
}

resource "aws_codebuild_project" "terraform" {
  name         = "${module.label.id}-terraform"
  service_role = "${aws_iam_role.default.arn}"

  artifacts {
    type = "CODEPIPELINE"

    #location = "${aws_s3_bucket.cache_bucket.bucket}"
  }

  # The cache as a list with a map object inside.
  cache = ["${local.cache}"]

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
        "name"  = "SLACK_WEBHOOK_URL"
        "value" = "${signum(length(var.slack_webhook_url)) == 1 ? var.slack_webhook_url : "UNSET"}"
      },
      {
        "name"  = "GITHUB_TOKEN"
        "value" = "${signum(length(var.github_token)) == 1 ? var.github_token : "UNSET"}"
      },
      "${var.environment_variables}",
    ]
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_terraform_plan.yml"
  }

  tags = "${module.label.tags}"
}

resource "aws_codebuild_webhook" "default" {
  project_name = "${aws_codebuild_project.default.name}"
  depends_on   = ["aws_codebuild_project.default"]
}