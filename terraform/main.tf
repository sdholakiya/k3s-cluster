provider "aws" {
  region = var.aws_region
}

# Optionally create an IAM role and instance profile for SSM access
resource "aws_iam_role" "ssm_role" {
  count = var.create_iam_role ? 1 : 0
  name  = "k3s-ssm-role"

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
  count      = var.create_iam_role ? 1 : 0
  role       = aws_iam_role.ssm_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  count = var.create_iam_role ? 1 : 0
  name  = "k3s-ssm-profile"
  role  = aws_iam_role.ssm_role[0].name
}

resource "aws_instance" "k3s_node" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.create_iam_role ? aws_iam_instance_profile.ssm_profile[0].name : var.iam_instance_profile
  key_name               = var.use_ssm ? null : var.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = var.instance_name
  }

  user_data = <<-EOF
              #!/bin/bash
              # Install SSM agent (if not already installed in AMI)
              apt-get update
              apt-get install -y amazon-ssm-agent curl
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

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
              EOF
}

# SSM connection to retrieve kubeconfig
resource "null_resource" "get_kubeconfig" {
  depends_on = [aws_instance.k3s_node]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for instance to be ready and SSM agent to start
      sleep 120
      
      # Create output directory
      mkdir -p ${path.module}/output
      
      # Use SSM to get kubeconfig
      aws ssm start-session \
        --target ${aws_instance.k3s_node.id} \
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
  depends_on = [null_resource.get_kubeconfig]

  provisioner "local-exec" {
    command = "sed -i.bak 's/127.0.0.1/${aws_instance.k3s_node.public_ip}/g' ${path.module}/output/kubeconfig"
  }
}

output "k3s_server_ip" {
  value = aws_instance.k3s_node.public_ip
}

output "k3s_server_private_ip" {
  value = aws_instance.k3s_node.private_ip
}

output "kubeconfig_path" {
  value = "${path.module}/output/kubeconfig"
}

output "instance_id" {
  value = aws_instance.k3s_node.id
  description = "EC2 instance ID for SSM connections"
}

output "ssm_connection_command" {
  value = "aws ssm start-session --target ${aws_instance.k3s_node.id}"
  description = "Command to start an SSM session with the instance"
}

output "ssm_helper_script" {
  value = "Run: ${path.module}/ssm_commands.sh ${aws_instance.k3s_node.id}"
  description = "Helper script to interact with the K3s cluster via SSM"
}