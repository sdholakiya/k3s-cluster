provider "aws" {
  region = var.aws_region
  # Use appropriate endpoint for GovCloud
  endpoints {
    dynamodb = var.is_govcloud ? "https://dynamodb.${var.aws_region}.amazonaws.com" : null
    ec2      = var.is_govcloud ? "https://ec2.${var.aws_region}.amazonaws.com" : null
    iam      = var.is_govcloud ? "https://iam.${var.aws_region}.amazonaws.com" : null
    s3       = var.is_govcloud ? "https://s3.${var.aws_region}.amazonaws.com" : null
    ssm      = var.is_govcloud ? "https://ssm.${var.aws_region}.amazonaws.com" : null
  }
}

locals {
  aws_partition = var.is_govcloud ? "aws-us-gov" : "aws"
}

# ==========================================================
# EC2 Instance Creation Stage
# ==========================================================

# Skip this entire stage if skip_ec2_creation = true
resource "aws_iam_role" "ssm_role" {
  count = (!var.skip_ec2_creation && var.create_iam_role) ? 1 : 0
  name  = "${var.instance_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  count      = (!var.skip_ec2_creation && var.create_iam_role) ? 1 : 0
  role       = aws_iam_role.ssm_role[0].name
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  count = (!var.skip_ec2_creation && var.create_iam_role) ? 1 : 0
  name  = "${var.instance_name}-ssm-profile"
  role  = aws_iam_role.ssm_role[0].name
}

# Optionally use shared AMI with proper filters
data "aws_ami" "selected" {
  count       = (!var.skip_ec2_creation && var.ami_id == "") ? 1 : 0
  most_recent = true
  owners      = var.ami_owners

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# EC2 Instance Creation
resource "aws_instance" "k3s_node" {
  count                       = var.skip_ec2_creation ? 0 : 1
  ami                         = var.ami_id != "" ? var.ami_id : data.aws_ami.selected[0].id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = false
  iam_instance_profile        = var.create_iam_role ? aws_iam_instance_profile.ssm_profile[0].name : var.iam_instance_profile
  key_name                    = var.use_ssm ? null : var.key_name
  monitoring                  = var.enable_detailed_monitoring

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    iops                  = var.root_volume_iops
    throughput            = var.root_volume_throughput
    delete_on_termination = true
    encrypted             = true
  }

  dynamic "ebs_block_device" {
    for_each = var.additional_ebs_volumes
    content {
      device_name           = ebs_block_device.value.device_name
      volume_size           = ebs_block_device.value.volume_size
      volume_type           = ebs_block_device.value.volume_type
      iops                  = ebs_block_device.value.iops
      throughput            = ebs_block_device.value.throughput
      encrypted             = ebs_block_device.value.encrypted
      delete_on_termination = true
    }
  }

  tags = merge(
    {
      Name = var.instance_name
    },
    var.instance_tags
  )

  # Base user data script to install SSM agent
  user_data = <<-EOF
              #!/bin/bash
              # Install SSM agent (if not already installed in AMI)
              apt-get update
              apt-get install -y amazon-ssm-agent curl
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              ${var.skip_k3s_install ? "" : <<-K3S_SETUP
              # Install K3s
              curl -sfL https://get.k3s.io | sh -
              
              # Wait for K3s to start
              sleep 30
              
              # Get K3s token for later use
              K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
              
              # Output token to file for retrieval
              echo "K3S_TOKEN=$K3S_TOKEN" > /tmp/k3s-token
              
              # Ensure k3s is running
              systemctl status k3s
              
              # Copy kubeconfig to accessible location
              cp /etc/rancher/k3s/k3s.yaml /tmp/kubeconfig
              chmod 644 /tmp/kubeconfig
              K3S_SETUP
              }

              # Custom user data script provided by the user
              ${var.user_data_script}
              EOF
}

# ==========================================================
# K3S Configuration Stage
# ==========================================================

# This resource is only created if EC2 has been created (either in this run or a previous one)
resource "null_resource" "get_kubeconfig" {
  count      = var.skip_k3s_install ? 0 : 1
  depends_on = [aws_instance.k3s_node]

  # Use either the newly created instance or a data source to get an existing instance ID
  triggers = {
    instance_id = var.skip_ec2_creation ? data.aws_instance.existing[0].id : aws_instance.k3s_node[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for instance to be ready and SSM agent to start
      sleep 120
      
      # Create output directory
      mkdir -p ${path.module}/output
      
      # Use SSM to get kubeconfig
      aws ssm start-session \
        --target ${var.skip_ec2_creation ? data.aws_instance.existing[0].id : aws_instance.k3s_node[0].id} \
        --document-name AWS-RunShellScript \
        --parameters 'commands=["cat /tmp/kubeconfig"]' \
        --output text > ${path.module}/output/kubeconfig.tmp || echo "Failed to get kubeconfig via SSM"
      
      # Clean up the output file (remove SSM session output headers/footers)
      grep -v "Starting session with SessionId" ${path.module}/output/kubeconfig.tmp | grep -v "Waiting for connections" > ${path.module}/output/kubeconfig || echo "Failed to clean kubeconfig"
      
      # Make the helper script executable
      chmod +x ${path.module}/ssm_commands.sh
    EOT
  }
}

resource "null_resource" "kubeconfig_update" {
  count      = var.skip_k3s_install ? 0 : 1
  depends_on = [null_resource.get_kubeconfig]

  # Use either the newly created instance or a data source to get an existing instance
  provisioner "local-exec" {
    command = "sed -i.bak 's/127.0.0.1/${var.skip_ec2_creation ? data.aws_instance.existing[0].private_ip : aws_instance.k3s_node[0].private_ip}/g' ${path.module}/output/kubeconfig"
  }
}

# Data source to find existing instance if not creating a new one
data "aws_instance" "existing" {
  count = var.skip_ec2_creation ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [var.instance_name]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# ==========================================================
# Outputs
# ==========================================================

output "k3s_server_ip" {
  value       = var.skip_ec2_creation ? data.aws_instance.existing[0].private_ip : (length(aws_instance.k3s_node) > 0 ? aws_instance.k3s_node[0].private_ip : null)
  description = "Private IP address of the K3s server"
}

output "kubeconfig_path" {
  value       = var.skip_k3s_install ? null : "${path.module}/output/kubeconfig"
  description = "Path to kubeconfig file"
}

output "instance_id" {
  value       = var.skip_ec2_creation ? data.aws_instance.existing[0].id : (length(aws_instance.k3s_node) > 0 ? aws_instance.k3s_node[0].id : null)
  description = "EC2 instance ID for SSM connections"
}

output "ssm_connection_command" {
  value       = "aws ssm start-session --target ${var.skip_ec2_creation ? data.aws_instance.existing[0].id : (length(aws_instance.k3s_node) > 0 ? aws_instance.k3s_node[0].id : "INSTANCE_ID")}"
  description = "Command to start an SSM session with the instance"
}

output "ssm_helper_script" {
  value       = "Run: ${path.module}/ssm_commands.sh ${var.skip_ec2_creation ? data.aws_instance.existing[0].id : (length(aws_instance.k3s_node) > 0 ? aws_instance.k3s_node[0].id : "INSTANCE_ID")}"
  description = "Helper script to interact with the K3s cluster via SSM"
}