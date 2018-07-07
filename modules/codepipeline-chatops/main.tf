provider "archive" {
  version = "~> 1.0"
}

module "label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.0"
  namespace  = "${var.namespace}"
  name       = "${var.name}"
  stage      = "${var.stage}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
}

resource "aws_iam_role" "lambda" {
  name = "${module.label.id}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_logging" {
  name = "lambda_logging"
  role = "${aws_iam_role.lambda.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "put_approval" {
  name = "codepipeline_put_approval"
  role = "${aws_iam_role.lambda.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "codepipeline:PutApprovalResult"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "archive_file" "request_approval_on_slack_zip" {
  type        = "zip"
  source_file = "${path.module}/request_approval_on_slack.py"
  output_path = "artifacts/request_approval_on_slack.zip"
}

resource "aws_lambda_function" "request_approval" {
  count            = "${var.enable_request_approval == "true" ? 1 : 0}"
  filename         = "${data.archive_file.request_approval_on_slack_zip.output_path}"
  function_name    = "${module.label.id}-request-approval"
  role             = "${aws_iam_role.lambda.arn}"
  handler          = "request_approval_on_slack.lambda_handler"
  source_code_hash = "${data.archive_file.request_approval_on_slack_zip.output_base64sha256}"
  runtime          = "python3.6"

  environment {
    variables = {
      SLACK_WEBHOOK_URL = "${var.slack_webhook_url}"
      SLACK_CHANNEL     = "${var.slack_channel}"
    }
  }
}

data "archive_file" "handle_approval_zip" {
  type        = "zip"
  source_file = "${path.module}/handle_approval.py"
  output_path = "artifacts/handle_approval.zip"
}

resource "aws_lambda_function" "handle_approval" {
  count            = "${var.enable_handle_approval == "true" ? 1 : 0}"
  filename         = "${data.archive_file.handle_approval_zip.output_path}"
  function_name    = "${module.label.id}-handle-approval"
  role             = "${aws_iam_role.lambda.arn}"
  handler          = "handle_approval.lambda_handler"
  source_code_hash = "${data.archive_file.handle_approval_zip.output_base64sha256}"
  runtime          = "python3.6"

  environment {
    variables = {
      SLACK_VERIFICATION_TOKEN = "${var.slack_verification_token}"
    }
  }

  depends_on = ["${aws_iam_role.lambda}"]
}

resource "aws_api_gateway_rest_api" "default" {
  count = "${var.enable_handle_approval == "true" ? 1 : 0}"
  name  = "${module.label.id}"
}

resource "aws_api_gateway_resource" "proxy" {
  count       = "${var.enable_handle_approval == "true" ? 1 : 0}"
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  parent_id   = "${aws_api_gateway_rest_api.default.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  count         = "${var.enable_handle_approval == "true" ? 1 : 0}"
  rest_api_id   = "${aws_api_gateway_rest_api.default.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  count       = "${var.enable_handle_approval == "true" ? 1 : 0}"
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.handle_approval.invoke_arn}"
}

resource "aws_api_gateway_method" "proxy_root" {
  count         = "${var.enable_handle_approval == "true" ? 1 : 0}"
  rest_api_id   = "${aws_api_gateway_rest_api.default.id}"
  resource_id   = "${aws_api_gateway_rest_api.default.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  count       = "${var.enable_handle_approval == "true" ? 1 : 0}"
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.handle_approval.invoke_arn}"
}

resource "aws_api_gateway_deployment" "default" {
  count = "${var.enable_handle_approval == "true" ? 1 : 0}"

  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  stage_name  = "live"
}

resource "aws_lambda_permission" "apigw" {
  count         = "${var.enable_handle_approval == "true" ? 1 : 0}"
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.handle_approval.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.default.execution_arn}/*/*"
}
