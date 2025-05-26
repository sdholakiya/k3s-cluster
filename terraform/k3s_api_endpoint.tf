# K3s API Endpoint Access Configuration
# This file defines resources to access the K3s API endpoint from outside the private subnet

locals {
  instance_id = var.skip_ec2_creation ? data.aws_instance.existing[0].id : aws_instance.k3s_node[0].id
}

# SSM Port Forwarding Document for K3s API Access
resource "aws_ssm_document" "k3s_api_port_forward" {
  name            = "K3sApiPortForward"
  document_type   = "Session"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Port forwarding session to K3s API endpoint"
    sessionType   = "Port"
    parameters = {
      portNumber = {
        type = "String",
        description = "Port number of K3s API server",
        default = "6443"
      },
      localPortNumber = {
        type = "String",
        description = "Local port number",
        default = "6443"
      }
    },
    properties = {
      portNumber = "{{ portNumber }}",
      localPortNumber = "{{ localPortNumber }}",
      type = "LocalPortForwarding"
    }
  })

  tags = {
    Name        = "K3s API Port Forwarding"
    Environment = var.instance_tags["Environment"] != null ? var.instance_tags["Environment"] : "Development"
  }
}

# Create an IAM policy for K3s API access via SSM
resource "aws_iam_policy" "k3s_api_access" {
  name        = "K3sApiAccessPolicy"
  description = "Policy to allow K3s API access via SSM port forwarding"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = [
          "arn:${local.aws_partition}:ec2:${var.aws_region}:*:instance/${local.instance_id}",
          "arn:${local.aws_partition}:ssm:${var.aws_region}:*:document/K3sApiPortForward"
        ]
      }
    ]
  })
}

# Create a shell script to establish the port forwarding tunnel
resource "local_file" "k3s_api_access_script" {
  content = <<-EOT
    #!/bin/bash
    # Script to establish port forwarding to K3s API endpoint
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Set instance ID - this is the K3s server instance
    INSTANCE_ID="${local.instance_id}"
    
    # Start port forwarding session
    echo "Starting port forwarding session to K3s API endpoint..."
    echo "This will forward remote port 6443 to local port 6443"
    echo "Keep this terminal open while you need access to the K3s API"
    
    aws ssm start-session \
        --target $INSTANCE_ID \
        --document-name K3sApiPortForward \
        --parameters 'portNumber=6443,localPortNumber=6443'
    
    echo "Port forwarding session ended"
  EOT
  
  filename = "${path.module}/access_k3s_api.sh"
  file_permission = "0755"
}

# Output instructions for accessing K3s API
output "k3s_api_access_instructions" {
  value = <<-EOT
    To access the K3s API from outside the private subnet:
    
    1. Run the port forwarding script:
       ${path.module}/access_k3s_api.sh
    
    2. Keep the terminal with the port forwarding session open
    
    3. In a new terminal, configure kubectl to use the local endpoint:
       export KUBECONFIG=${path.module}/output/kubeconfig
       kubectl config set-cluster default --server=https://localhost:6443
       
    4. Test the connection:
       kubectl get nodes
       
    This establishes a secure tunnel to the K3s API endpoint through AWS Systems Manager,
    allowing you to access the K3s cluster running in the private subnet.
  EOT
  
  description = "Instructions for accessing the K3s API endpoint from outside the private subnet"
}