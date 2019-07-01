module "label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.0"
  namespace  = "${var.namespace}"
  name       = "${var.name}"
  stage      = "${var.stage}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
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
      type = "Service"

      identifiers = [
        "codebuild.amazonaws.com",
      ]
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
      "logs:*",
      "ecr:*",
      "s3:*",
      "dynamodb:*",
      "elasticbeanstalk:*",
      "iam:*",
      "codebuild:*",
      "codepipeline:*",
      "apigateway:*",
      "lambda:*",
      "sns:*",
      "sqs:*",
      "application-autoscaling:*",
      "cloudwatch:*",
      "events:*",
      "ec2:*",
      "elasticache:*",
      "route53:*",
      "eks:*",
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

resource "aws_codebuild_project" "plan" {
  name         = "${module.label.id}-plan"
  service_role = "${aws_iam_role.default.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "${var.build_compute_type}"
    image           = "${var.build_image}"
    type            = "LINUX_CONTAINER"
    privileged_mode = "${var.privileged_mode}"

    environment_variable = [
      {
        name  = "TF_IN_AUTOMATION"
        value = "true"
      },
      {
        "name"  = "SLACK_CLI_TOKEN"
        "value" = "${signum(length(var.slack_token)) == 1 ? var.slack_token : "UNSET"}"
      },
      {
        "name" = "SLACK_CHANNEL"

        "value" = "${signum(length(var.slack_channel)) == 1 ? var.slack_channel : "UNSET"}"
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

resource "aws_codebuild_project" "apply" {
  name         = "${module.label.id}-apply"
  service_role = "${aws_iam_role.default.arn}"
  tags         = "${module.label.tags}"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "${var.build_compute_type}"
    image           = "${var.build_image}"
    type            = "LINUX_CONTAINER"
    privileged_mode = "${var.privileged_mode}"

    environment_variable = [
      {
        name  = "TF_IN_AUTOMATION"
        value = "true"
      },
      {
        "name"  = "SLACK_CLI_TOKEN"
        "value" = "${signum(length(var.slack_token)) == 1 ? var.slack_token : "UNSET"}"
      },
      {
        "name" = "SLACK_CHANNEL"

        "value" = "${signum(length(var.slack_channel)) == 1 ? var.slack_channel : "UNSET"}"
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
    buildspec = "buildspec_terraform_apply.yml"
  }
}
