# Define composite variables for resources
module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.14.1"
  namespace  = var.namespace
  name       = var.name
  stage      = var.stage
  delimiter  = var.delimiter
  attributes = var.attributes
  tags       = var.tags
}

resource "aws_s3_bucket" "default" {
  bucket = module.label.id
  acl    = "private"
  tags   = module.label.tags
}

resource "aws_iam_role" "default" {
  name               = module.label.id
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "assume" {
  statement {
    sid = ""

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = aws_iam_role.default.id
  policy_arn = aws_iam_policy.default.arn
}

resource "aws_iam_policy" "default" {
  name   = module.label.id
  policy = data.aws_iam_policy_document.default.json
}

data "aws_iam_policy_document" "default" {
  statement {
    sid = ""

    actions = [
      "elasticbeanstalk:*",
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "cloudwatch:*",
      "s3:*",
      "sns:*",
      "cloudformation:*",
      "rds:*",
      "sqs:*",
      "ecs:*",
      "iam:PassRole",
    ]

    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.default.id
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_iam_policy" "s3" {
  name   = "${module.label.id}-s3"
  policy = data.aws_iam_policy_document.s3.json
}

data "aws_iam_policy_document" "s3" {
  statement {
    sid = ""

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
      "s3:ListObjects",
    ]

    resources = [
      aws_s3_bucket.default.arn,
      "${aws_s3_bucket.default.arn}/*",
      "arn:aws:s3:::elasticbeanstalk*",
      "arn:aws:s3:::${var.terraform_state_bucket}",
      "arn:aws:s3:::${var.terraform_state_bucket}/*",
    ]

    effect = "Allow"
  }

  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.default.id
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_iam_policy" "codebuild" {
  name   = "${module.label.id}-codebuild"
  policy = data.aws_iam_policy_document.codebuild.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid = ""

    actions = [
      "codebuild:*",
    ]

    resources = [
      var.codebuild_apply_project_id,
      var.codebuild_plan_project_id,
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role_policy_attachment" "codebuild_s3" {
  role       = var.codebuild_role_arn
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_codepipeline" "source_build" {
  count    = length(var.branches)
  name     = "${module.label.id}-${element(var.branches, count.index)}"
  role_arn = aws_iam_role.default.arn

  artifact_store {
    location = aws_s3_bucket.default.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["code"]

      configuration = {
        OAuthToken           = var.github_oauth_token
        Owner                = var.repo_owner
        Repo                 = var.repo_name
        Branch               = element(var.branches, count.index)
        PollForSourceChanges = var.poll_source_changes
      }
    }
  }

  stage {
    name = "Plan"

    action {
      name     = "Plan"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["code"]
      output_artifacts = ["terraform_plan"]

      configuration = {
        ProjectName = var.codebuild_plan_project_name
      }
    }
  }

  stage {
    name = "Approval"

    action {
      name     = "ApprovalOrDeny"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = var.request_approval_sns_topic_arn
      }
      #CustomData         = "${var.approve_comment}"
      #ExternalEntityLink = "${var.approve_url}"
    }
  }

  stage {
    name = "Apply"

    action {
      name     = "Apply"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["terraform_plan"]
      output_artifacts = [""]

      configuration = {
        ProjectName = var.codebuild_apply_project_name
      }
    }
  }
}

