# Terraform CI/CD

## Introduction

Terraform module that provisions a CodeBuild and CodePipeline that fetches sources from GitHub and run terraform plan and terraform apply (after a manual approval).

## Installation

You should copy those files on your GitHub repository root:

* `buildspec_terraform_apply.yml`
* `buildspec_terraform_plan.yml`
* `get_terraform_environment.sh`
 
