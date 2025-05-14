variable "aws_region" {
  description = "AWS region to deploy the infrastructure"
  type        = string
  default     = "us-west-2"
}

variable "is_govcloud" {
  description = "Set to true if using AWS GovCloud"
  type        = bool
  default     = false
}

variable "skip_ec2_creation" {
  description = "Set to true to skip EC2 instance creation (use when only updating K3s configuration)"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for the EC2 instance"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the EC2 instance - must be a private subnet with VPC endpoint for SSM"
  type        = string
}

variable "security_group_id" {
  description = "Security Group ID for the EC2 instance"
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name for the EC2 instance"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance (must be in the selected region)"
  type        = string
}

variable "ami_owners" {
  description = "List of AMI owner account IDs or aliases (e.g., 'self', 'amazon', or AWS account ID)"
  type        = list(string)
  default     = ["self"]
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH key name for the EC2 instance (optional when using SSM)"
  type        = string
  default     = null
}

variable "private_key_path" {
  description = "Path to private key for SSH access (optional when using SSM)"
  type        = string
  default     = null
}

variable "use_ssm" {
  description = "Whether to use SSM for connection instead of SSH"
  type        = bool
  default     = true
}

variable "create_iam_role" {
  description = "Whether to create a new IAM role with SSM permissions"
  type        = bool
  default     = false
}

variable "instance_name" {
  description = "Name for the EC2 instance"
  type        = string
  default     = "k3s-cluster"
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 50
}

variable "root_volume_type" {
  description = "Type of the root volume (gp2, gp3, io1, io2, etc.)"
  type        = string
  default     = "gp3"
}

variable "root_volume_iops" {
  description = "IOPS for the root volume (required for io1/io2, optional for gp3)"
  type        = number
  default     = null
}

variable "root_volume_throughput" {
  description = "Throughput for gp3 volumes in MiB/s"
  type        = number
  default     = null
}

variable "additional_ebs_volumes" {
  description = "List of additional EBS volumes to attach"
  type = list(object({
    device_name = string
    volume_size = number
    volume_type = string
    iops        = optional(number)
    throughput  = optional(number)
    encrypted   = optional(bool, true)
  }))
  default = []
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for EC2 instance"
  type        = bool
  default     = false
}

variable "user_data_script" {
  description = "Custom user data script to append to default setup"
  type        = string
  default     = ""
}

variable "instance_tags" {
  description = "Additional tags for EC2 instance"
  type        = map(string)
  default     = {}
}

variable "skip_k3s_install" {
  description = "Skip K3s installation during initial setup (if you want to install it manually later)"
  type        = bool
  default     = false
}

variable "terraform_state_bucket" {
  description = "S3 bucket name for terraform state storage"
  type        = string
}

variable "terraform_state_key" {
  description = "S3 key path for terraform state file"
  type        = string
  default     = "k3s-cluster/terraform.tfstate"
}

variable "terraform_state_region" {
  description = "AWS region for terraform state bucket"
  type        = string
  default     = "us-west-2"
}

variable "terraform_state_dynamodb_table" {
  description = "DynamoDB table name for terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}