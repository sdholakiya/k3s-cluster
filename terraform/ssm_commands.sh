#!/bin/bash
# Helper script to connect to EC2 instance via SSM and interact with K3s cluster

EC2_INSTANCE_ID="$1"

if [ -z "$EC2_INSTANCE_ID" ]; then
  echo "Usage: $0 <instance-id>"
  echo "Example: $0 i-0123456789abcdef0"
  exit 1
fi

# Check if kubeconfig exists
mkdir -p $(dirname $0)/output

echo "Getting K3s cluster info via SSM..."
aws ssm start-session \
  --target $EC2_INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["kubectl get nodes -o wide"]' \
  --output text

echo "Retrieving kubeconfig from instance..."
aws ssm start-session \
  --target $EC2_INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cat /tmp/kubeconfig"]' \
  --output text > $(dirname $0)/output/kubeconfig.tmp

# Clean the output
grep -v "Starting session" $(dirname $0)/output/kubeconfig.tmp | grep -v "Waiting for connections" > $(dirname $0)/output/kubeconfig

# Get public IP to update kubeconfig
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# Update the kubeconfig with the public IP
sed -i.bak "s/127.0.0.1/$PUBLIC_IP/g" $(dirname $0)/output/kubeconfig

echo "Kubeconfig has been saved to $(dirname $0)/output/kubeconfig"
echo "To use this kubeconfig:"
echo "export KUBECONFIG=$(dirname $0)/output/kubeconfig"
echo "kubectl get nodes"