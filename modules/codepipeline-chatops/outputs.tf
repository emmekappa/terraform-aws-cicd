output "handle_approval_apigw_url" {
  value = "${aws_api_gateway_deployment.default.invoke_url}"
}

output "lambda_request_approval_arn" {
  value = "${aws_lambda_function.request_approval.arn}"
}
