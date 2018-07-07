output "handle_approval_apigw_url" {
  value = "${aws_api_gateway_deployment.default.invoke_url}"
}

output "request_approval_sns_topic_arn" {
  value = "${aws_sns_topic.approval_sns.arn}"
}
