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
  type = "zip"
  source_file = "${path.module}/request_approval_on_slack.py"
  output_path = "artifacts/request_approval_on_slack.zip"
}

resource "aws_lambda_function" "request_approval" {
  filename = "${data.archive_file.request_approval_on_slack_zip.output_path}"
  function_name = "${module.label.id}-request-approval"
  role = "${aws_iam_role.lambda.arn}"
  handler = "request_approval_on_slack.lambda_handler"
  source_code_hash = "${data.archive_file.request_approval_on_slack_zip.output_base64sha256}"
  runtime = "python3.6"

  environment {
    variables = {
      SLACK_WEBHOOK_URL = "${var.slack_webhook_url}"
      SLACK_CHANNEL = "${var.slack_channel}"
    }
  }
}

resource "aws_sns_topic" "approval_sns" {
  name = "${module.label.id}-approval-sns"
}

resource "aws_sns_topic_subscription" "approval_sns_subscription" {
  topic_arn = "${aws_sns_topic.approval_sns.arn}"
  protocol = "lambda"
  endpoint = "${aws_lambda_function.request_approval.arn}"
}

resource "aws_lambda_permission" "approval_lambda_sns_permission" {
  statement_id = "AllowExecutionFromSNS"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.request_approval.arn}"
  principal = "sns.amazonaws.com"
  source_arn = "${aws_sns_topic.approval_sns.arn}"
}

data "archive_file" "handle_approval_zip" {
  type = "zip"
  source_file = "${path.module}/handle_approval.py"
  output_path = "artifacts/handle_approval.zip"
}

resource "aws_lambda_function" "handle_approval" {
  filename = "${data.archive_file.handle_approval_zip.output_path}"
  function_name = "${module.label.id}-handle-approval"
  role = "${aws_iam_role.lambda.arn}"
  handler = "handle_approval.lambda_handler"
  source_code_hash = "${data.archive_file.handle_approval_zip.output_base64sha256}"
  runtime = "python3.6"

  environment {
    variables = {
      SLACK_VERIFICATION_TOKEN = "${var.slack_verification_token}"
    }
  }

  depends_on = ["aws_iam_role.lambda"]
}

resource "aws_api_gateway_rest_api" "default" {
  name = "${module.label.id}"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  parent_id = "${aws_api_gateway_rest_api.default.root_resource_id}"
  path_part = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  resource_id = "${aws_api_gateway_resource.proxy.id}"
  http_method = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = "${aws_lambda_function.handle_approval.invoke_arn}"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  resource_id = "${aws_api_gateway_rest_api.default.root_resource_id}"
  http_method = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = "${aws_lambda_function.handle_approval.invoke_arn}"
}

resource "aws_api_gateway_deployment" "default" {
  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.default.id}"
  stage_name = "live"
}

resource "aws_lambda_permission" "apigw" {
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.handle_approval.arn}"
  principal = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.default.execution_arn}/*/*"
}

# CodePipeline status to slack

data "archive_file" "notify_codepipeline_status" {
  type = "zip"
  source_dir = "${path.module}/notify_status_change"
  output_path = "artifacts/notify_codepipeline_status.zip"
}

resource "aws_lambda_function" "notify_codepipeline_status" {
  filename = "${data.archive_file.notify_codepipeline_status.output_path}"
  function_name = "${module.label.id}-notify-to-slack"
  handler = "notify_codepipeline_status.handler"
  role = "${aws_iam_role.lambda.arn}"
  source_code_hash = "${data.archive_file.notify_codepipeline_status.output_base64sha256}"
  runtime = "nodejs6.10"

  environment {
    variables = {
      SLACK_URL = "${var.slack_webhook_url}"
    }
  }
}

resource "aws_cloudwatch_event_rule" "codepipeline" {
  name = "capture-codepipeline-state-changes"
  description = "Capture each CodePipeline state changes"

  event_pattern = <<PATTERN
{
  "source": [ "aws.codepipeline" ],
  "detail-type": [
    "CodePipeline Pipeline Execution State Change"
  ]
}
PATTERN
}

resource "aws_cloudwatch_event_target" "sns" {
  rule       = "${aws_cloudwatch_event_rule.codepipeline.name}"
  target_id  = "SendToLambda"
  arn        = "${aws_lambda_function.notify_codepipeline_status.arn}"
  depends_on = ["aws_lambda_function.notify_codepipeline_status"]
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.notify_codepipeline_status.function_name}"
  principal     = "events.amazonaws.com"
}
