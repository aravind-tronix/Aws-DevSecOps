terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Fetch the current AWS account ID dynamically
data "aws_caller_identity" "current" {}

# Generate a random suffix for the S3 bucket name to ensure uniqueness
resource "random_id" "s3_suffix" {
  byte_length = 8
}

# Define the S3 bucket for AWS Config delivery channel
resource "aws_s3_bucket" "aws-config-stream" {
  bucket        = "aws-config-stream-${random_id.s3_suffix.hex}"
  force_destroy = true

  tags = {
    Name        = "awsConfig"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket_encryption" {
  bucket = aws_s3_bucket.aws-config-stream.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Define the S3 bucket policy dynamically
data "aws_iam_policy_document" "aws_config_bucket_policy" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.aws-config-stream.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["s3:ListBucket"]
    resources = [aws_s3_bucket.aws-config-stream.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.aws-config-stream.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Attach the policy to the S3 bucket
resource "aws_s3_bucket_policy" "aws_config_bucket_policy" {
  bucket = aws_s3_bucket.aws-config-stream.id
  policy = data.aws_iam_policy_document.aws_config_bucket_policy.json
  depends_on = [aws_s3_bucket.aws-config-stream]
}

# Fetch the existing AWS Config service-linked role
data "aws_iam_role" "config_service_role" {
  name = "AWSServiceRoleForConfig"
}

resource "aws_config_configuration_recorder" "config-recorder" {
  name     = "config-recorder"
  role_arn = data.aws_iam_role.config_service_role.arn
  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = ["AWS::S3::Bucket"]
  }
}

resource "aws_config_delivery_channel" "s3-delivery" {
  name           = "example"
  s3_bucket_name = aws_s3_bucket.aws-config-stream.id
  depends_on     = [aws_config_configuration_recorder.config-recorder]
}

resource "aws_config_configuration_recorder_status" "s3-delivery-status" {
  name       = aws_config_configuration_recorder.config-recorder.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.s3-delivery]
}

resource "aws_config_config_rule" "r" {
  name = "s3_rule"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
  }
  scope {
    compliance_resource_types = ["AWS::S3::Bucket"]
  }
  depends_on = [aws_config_configuration_recorder.config-recorder]
}

resource "aws_iam_role" "security_config" {
  name               = "security_config"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json
}

data "aws_iam_policy_document" "ssm_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "security_config_policy" {
  name   = "security-config-policy"
  role   = aws_iam_role.security_config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock",  # Added to allow verification
          "s3:PutObject",
          "s3:GetBucketAcl"
        ]
        Resource = [
          "arn:aws:s3::*",  # Broad scope to cover all buckets
          "${aws_s3_bucket.aws-config-stream.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:StartAutomationExecution"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/ssm/automation:*"
      }
    ]
  })
  depends_on = [aws_iam_role.security_config]
}

resource "aws_config_remediation_configuration" "this" {
  config_rule_name = aws_config_config_rule.r.name
  resource_type    = "AWS::S3::Bucket"
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWSConfigRemediation-ConfigureS3BucketPublicAccessBlock"
  target_version   = "1"
  parameter {
    name           = "BucketName"
    resource_value = "RESOURCE_ID"
  }
  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.security_config.arn
  }
  automatic                  = true
  maximum_automatic_attempts = 2
  retry_attempt_seconds      = 600
  execution_controls {
    ssm_controls {
      concurrent_execution_rate_percentage = 2
      error_percentage                     = 20
    }
  }
}