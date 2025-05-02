variable "aws_region" {
  description = "AWS region to deploy the infrastructure"
  type        = string
  default     = "us-west-2"
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
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0ee02ddf90e99f238" # Ubuntu 22.04 LTS in us-west-2
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