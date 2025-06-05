# Resources for Terraform backend infrastructure
# Creates the S3 bucket for state management

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.terraform_state_bucket

  tags = {
    Name        = "Terraform State Bucket"
    Environment = "Management"
    Managed_by  = "Terraform"
  }
}

# Enable versioning on the S3 bucket
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Outputs
output "terraform_state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket name for Terraform state"
}

