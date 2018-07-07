variable "namespace" {
  default     = "global"
  description = "Namespace, which could be your organization name, e.g. 'cp' or 'cloudposse'"
}

variable "stage" {
  default     = "default"
  description = "Stage, e.g. 'prod', 'staging', 'dev', or 'test'"
}

variable "name" {
  default     = "app"
  description = "Solution name, e.g. 'app' or 'jenkins'"
}

variable "tags" {
  type        = "map"
  default     = {}
  description = "Additional tags (e.g. `map('BusinessUnit', 'XYZ')`"
}

variable "attributes" {
  type        = "list"
  default     = []
  description = "Additional attributes (e.g. `policy` or `role`)"
}

variable "delimiter" {
  type    = "string"
  default = "-"
}

variable "slack_webhook_url" {
  description = "Incoming webhook for your slack application"
}

variable "slack_channel" {}

variable "slack_verification_token" {}
