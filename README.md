# AWS Config S3 Monitoring and Remediation Setup

This repository contains a Terraform configuration to set up an AWS Config stream for monitoring S3 buckets, enforcing the `S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED` rule, and automating remediation using SSM Automation. The setup uses a service-linked role for configuration recording and a custom IAM role for remediation, ensuring compliance with security best practices.

## Overview

- Purpose: Monitor S3 buckets for public access and automatically remediate noncompliant buckets by enabling Public Access Block settings.
- Components:
  - S3 bucket for Config delivery with SSE-S3 encryption.
  - AWS Config configuration recorder, delivery channel, and rule.
  - IAM roles for Config recording (service-linked) and remediation (custom).
  - SSM Automation for remediation.

## Prerequisites

- AWS Account: An active AWS account with permissions to create IAM roles, S3 buckets, and configure AWS Config.
- Terraform: Version 1.0 or later installed (terraform --version to check).
- AWS CLI: Configured with appropriate credentials (aws configure).
- Region: Set to us-east-1 (configurable in the provider block if needed).
- Permissions: Ensure your IAM user or role has:
  - iam:CreateRole, iam:AttachRolePolicy, s3:CreateBucket, config:*, and ssm:* actions.

## Setup Instructions

1. Clone the Repository
Clone the repository using the following commands:
- git clone https://github.com/aravind-tronix/Aws-DevSecOps
- cd Aws-DevSecOps

2. Configure AWS Credentials
Set up your AWS CLI with an IAM user or role that has the required permissions. Verify with:
aws sts get-caller-identity

3. Initialize Terraform
Run the following command to initialize the Terraform working directory:
```terraform init```

4. Review and Customize the Code
Open main.tf and review the configuration. Optional customizations include:
- Change the region in the provider "aws" block if needed.
- Adjust the tags in the aws_s3_bucket resource for your environment.
- Modify the Resource in aws_iam_role_policy.security_config_policy to limit S3 bucket scope (e.g., arn:aws:s3:::test-config-*) if desired.

5. Plan the Deployment
Run the following to see what resources will be created:
```terraform plan```
Review the output for any issues.

6. Apply the Configuration
Deploy the resources by running:
```terraform apply```
Type yes when prompted to confirm.

7. Verify the Setup
- S3 Bucket: Go to S3 in the AWS Console and locate aws-config-stream-<random-suffix>. Confirm SSE-S3 is enabled under Properties > Default encryption.
- AWS Config: Navigate to AWS Config > Settings. Verify the config-recorder is using AWSServiceRoleForConfig and is Recording. Check Rules > s3_rule and ensure it detects noncompliant S3 buckets (e.g., test-config-5555555 with public access).
- IAM: Go to IAM > Roles and confirm security_config has the security-config-policy attached. Verify AWSServiceRoleForConfig exists.
- SSM Automation: Go to Systems Manager > Automation. Trigger a remediation by making an S3 bucket noncompliant (e.g., disable Public Access Block) and re-evaluate the rule. Check for a successful execution using the security_config role.

8. Test Remediation
Create or modify an S3 bucket (e.g., test-config-5555555) with public access enabled. In AWS Config > Rules > s3_rule, click Re-evaluate. Monitor Systems Manager > Automation for the remediation execution. Verify the bucket’s Permissions > Block Public Access is enabled post-remediation.

# Configuration Details

## Resources Created
- S3 Bucket: aws-config-stream-<random-suffix> for Config delivery with AES256 encryption.
- IAM Roles:
  - AWSServiceRoleForConfig: Service-linked role for Config recording.
  - security_config: Custom role for SSM Automation remediation.
- AWS Config:
  - config-recorder: Records S3 bucket configurations.
  - s3-delivery: Delivery channel to the S3 bucket.
  - s3_rule: Enforces S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED.
- Remediation: Automates Public Access Block enablement via SSM.

## Policy Permissions
- security_config Policy:
  - s3:PutBucketPublicAccessBlock, s3:GetBucketPublicAccessBlock, s3:PutObject, s3:GetBucketAcl on arn:aws:s3::*.
  - ssm:StartAutomationExecution on *.
  - logs:CreateLogStream, logs:PutLogEvents on /aws/ssm/automation.

## Troubleshooting

- Rule Not Detecting Resources: Ensure the recorder is Recording in AWS Config > Settings. Check the S3 bucket policy and IAM role permissions.
- Remediation Fails with AccessDenied: Verify security_config has s3:GetBucketPublicAccessBlock and s3:PutBucketPublicAccessBlock. Check the bucket policy on the target bucket (e.g., test-config-5555555) for denies. Ensure the bucket is in the same account (288481966788).
- Terraform Apply Fails: Review the error output and ensure AWS credentials have sufficient permissions. Run terraform refresh to sync the state.
- SSM Execution Errors: Check Systems Manager > Automation for detailed logs. Share the failure message for further assistance.

## Cleanup
To destroy all resources and avoid charges:
```terraform destroy```
Type yes to confirm.

Contributing
Feel free to submit issues or pull requests to improve this setup.

License
[MIT License] - See LICENSE file for details.