# Docker CI/CD

## Introduction

Terraform module that provisions a CodeBuild and CodePipeline that fetches sources from GitHub, build the docker images and pushes the results on ECR.

## Installation

You should copy `get_image_tag.sh` and `buildspec.yml` on your GitHub repository root