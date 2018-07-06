output "handle_approval_apigw_url" {
  value = "${var.enable_handle_approval == "true" ? aws_api_gateway_deployment.default.0.invoke_url : "UNSET"}"
}

output "lambda_request_approval_arn" {
  value = "${var.enable_request_approval == "true" ? aws_lambda_function.request_approval.0.arn : "UNSET"}"
}
