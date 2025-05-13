#!/bin/bash

# Script to initialize terraform with S3 backend configuration

if [ ! -f terraform.tfvars ]; then
  echo "Error: terraform.tfvars file not found. Please create it from terraform.tfvars.example"
  exit 1
fi

# Extract variables from tfvars
BUCKET=$(grep terraform_state_bucket terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
KEY=$(grep terraform_state_key terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
REGION=$(grep terraform_state_region terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
DYNAMODB_TABLE=$(grep terraform_state_dynamodb_table terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

if [ -z "$BUCKET" ]; then
  echo "Error: terraform_state_bucket not found in terraform.tfvars"
  exit 1
fi

# Initialize terraform with backend config
terraform init \
  -backend-config="bucket=$BUCKET" \
  -backend-config="key=${KEY:-k3s-cluster/terraform.tfstate}" \
  -backend-config="region=${REGION:-us-west-2}" \
  -backend-config="dynamodb_table=${DYNAMODB_TABLE:-terraform-state-lock}"

echo "Terraform initialized with S3 backend in bucket: $BUCKET"