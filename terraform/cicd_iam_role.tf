# CI/CD IAM Role for K3s Cluster Project using OIDC Federation
# This creates IAM roles for GitLab CI/CD without any IAM users or stored credentials

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Variables for GitLab OIDC configuration
variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_project_path" {
  description = "GitLab project path (e.g., username/project-name)"
  type        = string
}

# Get GitLab's OIDC thumbprint
data "tls_certificate" "gitlab" {
  url = var.gitlab_url
}

# OIDC Identity Provider for GitLab
resource "aws_iam_openid_connect_provider" "gitlab" {
  url = var.gitlab_url

  client_id_list = [
    var.gitlab_url
  ]

  thumbprint_list = [
    data.tls_certificate.gitlab.certificates[0].sha1_fingerprint
  ]

  tags = {
    Name        = "gitlab-oidc-provider"
    Purpose     = "CI/CD"
    Environment = "automation"
    Project     = "k3s-cluster"
  }
}

# IAM Policy for CI/CD operations with minimal permissions
resource "aws_iam_policy" "cicd_policy" {
  name        = "k3s-cicd-policy"
  description = "Minimal permissions policy for K3s CI/CD operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EC2 permissions for K3s cluster management
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeImages",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeAvailabilityZones",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeTags",
          "ec2:ModifyInstanceAttribute"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      },
      # ECR permissions for container registry
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchDeleteImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:CreateRepository"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/k3s-*"
      },
      # S3 permissions for Terraform state
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::${var.terraform_state_bucket}",
          "arn:aws:s3:::${var.terraform_state_bucket}/*"
        ]
      },
      # DynamoDB permissions for Terraform state locking
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/terraform-state-lock"
      },
      # SSM permissions for instance management
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      },
      # IAM permissions for role management (very limited scope)
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/k3s-*"
      }
    ]
  })

  tags = {
    Name        = "k3s-cicd-policy"
    Purpose     = "CI/CD"
    Environment = "automation"
    Project     = "k3s-cluster"
  }
}

# IAM Role for GitLab CI/CD (main branch)
resource "aws_iam_role" "gitlab_cicd_main" {
  name = "gitlab-k3s-cicd-main"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gitlab.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.gitlab_url}:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:main"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "gitlab-k3s-cicd-main"
    Purpose     = "CI/CD"
    Environment = "automation"
    Project     = "k3s-cluster"
    Branch      = "main"
  }
}

# IAM Role for GitLab CI/CD (feature branches - limited permissions)
resource "aws_iam_role" "gitlab_cicd_feature" {
  name = "gitlab-k3s-cicd-feature"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gitlab.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${var.gitlab_url}:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:*"
          }
          StringNotEquals = {
            "${var.gitlab_url}:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:main"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "gitlab-k3s-cicd-feature"
    Purpose     = "CI/CD"
    Environment = "automation"
    Project     = "k3s-cluster"
    Branch      = "feature"
  }
}

# Limited policy for feature branches (read-only + plan)
resource "aws_iam_policy" "cicd_feature_policy" {
  name        = "k3s-cicd-feature-policy"
  description = "Limited permissions for feature branch CI/CD operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read-only EC2 permissions
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*"
        ]
        Resource = "*"
      },
      # ECR read permissions
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = "*"
      },
      # S3 read permissions for Terraform state
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::${var.terraform_state_bucket}",
          "arn:aws:s3:::${var.terraform_state_bucket}/*"
        ]
      },
      # DynamoDB read permissions for state locking
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/terraform-state-lock"
      }
    ]
  })

  tags = {
    Name        = "k3s-cicd-feature-policy"
    Purpose     = "CI/CD"
    Environment = "automation"
    Project     = "k3s-cluster"
  }
}

# Attach full policy to main branch role
resource "aws_iam_role_policy_attachment" "gitlab_cicd_main_policy" {
  role       = aws_iam_role.gitlab_cicd_main.name
  policy_arn = aws_iam_policy.cicd_policy.arn
}

# Attach limited policy to feature branch role
resource "aws_iam_role_policy_attachment" "gitlab_cicd_feature_policy" {
  role       = aws_iam_role.gitlab_cicd_feature.name
  policy_arn = aws_iam_policy.cicd_feature_policy.arn
}

# Outputs
output "gitlab_oidc_provider_arn" {
  description = "ARN of the GitLab OIDC provider"
  value       = aws_iam_openid_connect_provider.gitlab.arn
}

output "gitlab_cicd_main_role_arn" {
  description = "ARN of the GitLab CI/CD role for main branch"
  value       = aws_iam_role.gitlab_cicd_main.arn
}

output "gitlab_cicd_feature_role_arn" {
  description = "ARN of the GitLab CI/CD role for feature branches"
  value       = aws_iam_role.gitlab_cicd_feature.arn
}

output "cicd_policy_arn" {
  description = "ARN of the CI/CD policy"
  value       = aws_iam_policy.cicd_policy.arn
}