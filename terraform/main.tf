provider "aws" {
  region = var.aws_region
  # Use appropriate endpoint for GovCloud
  endpoints {
    ec2 = var.is_govcloud ? "https://ec2.${var.aws_region}.amazonaws.com" : null
    iam = var.is_govcloud ? "https://iam.${var.aws_region}.amazonaws.com" : null
    s3  = var.is_govcloud ? "https://s3.${var.aws_region}.amazonaws.com" : null
    ssm = var.is_govcloud ? "https://ssm.${var.aws_region}.amazonaws.com" : null
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
  iam_instance_profile        = var.create_iam_role ? aws_iam_instance_profile.ssm_profile[0].name : (var.iam_instance_profile != "" ? var.iam_instance_profile : null)
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
              # Install dependencies
              apt-get update
              apt-get install -y open-iscsi nfs-common
              systemctl enable iscsid && systemctl start iscsid
              
              # Configure custom K3s installation
              mkdir -p /etc/rancher/k3s
              cat > /etc/rancher/k3s/config.yaml << EOF
              # K3s server configuration
              token: "auto-generated-token"
              node-name: ${var.instance_name}
              tls-san:
                - ${var.instance_name}
              disable:
                - traefik # We'll use our own ingress
              kube-controller-manager-arg:
                - "bind-address=0.0.0.0" # Enable metrics access
              kube-scheduler-arg:
                - "bind-address=0.0.0.0" # Enable metrics access
              kube-proxy-arg:
                - "metrics-bind-address=0.0.0.0" # Enable metrics access
              flannel-backend: "vxlan"
              # Enable default StorageClass
              default-local-storage-path: /opt/local-path-provisioner
              # Write kubeconfig to accessible location
              write-kubeconfig-mode: "0644"
              write-kubeconfig: /tmp/kubeconfig
              EOF
              
              # Install K3s server
              curl -sfL https://get.k3s.io | sh -
              
              # Wait for K3s to start
              sleep 45
              
              # Get K3s token for later use
              K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
              
              # Output token to file for retrieval
              echo "K3S_TOKEN=$K3S_TOKEN" > /tmp/k3s-token
              
              # Ensure k3s is running
              systemctl status k3s
              
              # Install Helm
              curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
              
              # Make kubectl and kubeconfig accessible to standard users
              chmod 644 /etc/rancher/k3s/k3s.yaml
              cp /etc/rancher/k3s/k3s.yaml /tmp/kubeconfig
              chmod 644 /tmp/kubeconfig
              
              # Install Kubernetes metrics server
              kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
              
              # Set up persistent storage class using local-path-provisioner (already included in K3s)
              # This ensures our application deployments have persistent storage available
              
              # Set up ingress-nginx
              helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
              helm repo update
              helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace --namespace ingress-nginx
              
              # Export k3s API endpoint for external access
              PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
              echo "K3S_API_ENDPOINT=https://$PRIVATE_IP:6443" > /tmp/k3s-api-endpoint
              
              # Wait for ingress controller to be ready
              kubectl wait --namespace ingress-nginx \
                --for=condition=ready pod \
                --selector=app.kubernetes.io/component=controller \
                --timeout=180s
              K3S_SETUP
}

              # Custom user data script provided by the user
              ${var.user_data_script}
              EOF
}

# ==========================================================
# K3S Configuration Stage
# ==========================================================

# Install K3s on existing instance if needed
resource "null_resource" "install_k3s_existing" {
  count      = (var.skip_ec2_creation && !var.skip_k3s_install) ? 1 : 0
  depends_on = [data.aws_instance.existing]

  triggers = {
    instance_id      = data.aws_instance.existing[0].id
    skip_k3s_install = var.skip_k3s_install
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Installing K3s on existing instance"
      
      # Install dependencies and K3s
      cat > /tmp/k3s_install.sh << 'INSTALL_SCRIPT'
#!/bin/bash
# Install dependencies
apt-get update
apt-get install -y open-iscsi nfs-common curl
systemctl enable iscsid && systemctl start iscsid

# Configure custom K3s installation
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml << EOF
# K3s server configuration
token: "auto-generated-token"
node-name: ${var.instance_name}
tls-san:
  - ${var.instance_name}
disable:
  - traefik # We'll use our own ingress
kube-controller-manager-arg:
  - "bind-address=0.0.0.0"
kube-scheduler-arg:
  - "bind-address=0.0.0.0"
kube-proxy-arg:
  - "metrics-bind-address=0.0.0.0"
flannel-backend: "vxlan"
default-local-storage-path: /opt/local-path-provisioner
write-kubeconfig-mode: "0644"
write-kubeconfig: /tmp/kubeconfig
EOF

# Install K3s server
curl -sfL https://get.k3s.io | sh -

# Wait for K3s to start
sleep 45

# Get K3s token for later use
K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
echo "K3S_TOKEN=$K3S_TOKEN" > /tmp/k3s-token

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Make kubectl and kubeconfig accessible
chmod 644 /etc/rancher/k3s/k3s.yaml
cp /etc/rancher/k3s/k3s.yaml /tmp/kubeconfig
chmod 644 /tmp/kubeconfig

# Install Kubernetes metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Set up ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace --namespace ingress-nginx

# Export k3s API endpoint
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || hostname -I | awk '{print $1}')
echo "K3S_API_ENDPOINT=https://$PRIVATE_IP:6443" > /tmp/k3s-api-endpoint

# Wait for ingress controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
INSTALL_SCRIPT

      # Execute the installation script
      sudo bash /tmp/k3s_install.sh
      
      echo "K3s installation completed"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Only uninstall if K3s installation was not skipped
      if [ "${self.triggers.skip_k3s_install}" = "false" ]; then
        echo "Uninstalling K3s from existing instance"
      
      # Create K3s uninstall script
      cat > /tmp/k3s_uninstall.sh << 'UNINSTALL_SCRIPT'
#!/bin/bash
echo "Starting K3s uninstallation..."

# Stop K3s service
if systemctl is-active --quiet k3s; then
  echo "Stopping K3s service..."
  sudo systemctl stop k3s
fi

# Disable K3s service
if systemctl is-enabled --quiet k3s 2>/dev/null; then
  echo "Disabling K3s service..."
  sudo systemctl disable k3s
fi

# Run official K3s uninstall script if it exists
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
  echo "Running official K3s uninstall script..."
  sudo /usr/local/bin/k3s-uninstall.sh
else
  echo "Official uninstall script not found, performing manual cleanup..."
  
  # Remove K3s binary
  sudo rm -f /usr/local/bin/k3s
  
  # Remove K3s service file
  sudo rm -f /etc/systemd/system/k3s.service
  
  # Remove K3s data directory
  sudo rm -rf /var/lib/rancher/k3s
  
  # Remove K3s config directory
  sudo rm -rf /etc/rancher/k3s
  
  # Remove kubeconfig files
  sudo rm -f /tmp/kubeconfig
  sudo rm -f /tmp/k3s-token
  sudo rm -f /tmp/k3s-api-endpoint
  
  # Reload systemd
  sudo systemctl daemon-reload
fi

# Clean up any remaining containers
if command -v docker >/dev/null 2>&1; then
  echo "Cleaning up Docker containers..."
  sudo docker system prune -af 2>/dev/null || true
fi

# Clean up any remaining network interfaces
echo "Cleaning up network interfaces..."
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true

echo "K3s uninstallation completed"
UNINSTALL_SCRIPT

      # Execute the uninstall script
      sudo bash /tmp/k3s_uninstall.sh
      
      # Clean up the script
      rm -f /tmp/k3s_uninstall.sh
      
      echo "K3s cleanup completed"
      else
        echo "Skipping K3s uninstall (skip_k3s_install = true)"
      fi
    EOT
  }
}

# This resource is only created if EC2 has been created (either in this run or a previous one)
resource "null_resource" "get_kubeconfig" {
  count      = var.skip_k3s_install ? 0 : 1
  depends_on = [aws_instance.k3s_node, null_resource.install_k3s_existing]

  # Use either the newly created instance or a data source to get an existing instance ID
  triggers = {
    instance_id = var.skip_ec2_creation ? data.aws_instance.existing[0].id : (length(aws_instance.k3s_node) > 0 ? aws_instance.k3s_node[0].id : null)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for K3s to be ready
      sleep 120
      
      # Create output directory
      mkdir -p ${path.module}/output
      
      # Use local commands when skip_ec2_creation is true (means we're using existing instance)
      if [ "${var.skip_ec2_creation}" = "true" ]; then
        echo "Using existing instance, running local commands"
        sudo cat /tmp/kubeconfig > ${path.module}/output/kubeconfig 2>/dev/null || \
        sudo cat /etc/rancher/k3s/k3s.yaml > ${path.module}/output/kubeconfig || \
        echo "Failed to get kubeconfig locally"
      else
        echo "Creating new instance, using SSM"
        aws ssm start-session \
          --target ${length(aws_instance.k3s_node) > 0 ? aws_instance.k3s_node[0].id : "MISSING_INSTANCE"} \
          --document-name AWS-RunShellScript \
          --parameters 'commands=["cat /tmp/kubeconfig"]' \
          --output text > ${path.module}/output/kubeconfig.tmp || echo "Failed to get kubeconfig via SSM"
        
        grep -v "Starting session with SessionId" ${path.module}/output/kubeconfig.tmp | grep -v "Waiting for connections" > ${path.module}/output/kubeconfig || echo "Failed to clean kubeconfig"
      fi
      
      chmod +x ${path.module}/ssm_commands.sh
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up kubeconfig and output files..."
      
      # Remove output directory and files
      rm -rf ${path.module}/output/
      
      echo "Kubeconfig cleanup completed"
    EOT
  }
}

resource "null_resource" "kubeconfig_update" {
  count      = var.skip_k3s_install ? 0 : 1
  depends_on = [null_resource.get_kubeconfig]

  # Use either the newly created instance or a data source to get an existing instance
  provisioner "local-exec" {
    command = "sed -i.bak 's/127.0.0.1/${var.skip_ec2_creation ? data.aws_instance.existing[0].private_ip : (length(aws_instance.k3s_node) > 0 ? aws_instance.k3s_node[0].private_ip : "127.0.0.1")}/g' ${path.module}/output/kubeconfig"
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