output "plan_project_name" {
  value = "${aws_codebuild_project.plan.name}"
}

output "plan_project_id" {
  value = "${aws_codebuild_project.plan.id}"
}

output "apply_project_name" {
  value = "${aws_codebuild_project.apply.name}"
}

output "apply_project_id" {
  value = "${aws_codebuild_project.apply.id}"
}

output "role_arn" {
  value = "${aws_iam_role.default.id}"
}
