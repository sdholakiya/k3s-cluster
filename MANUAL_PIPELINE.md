# Manual Pipeline Execution Steps

This document outlines the steps to manually execute the CI/CD pipeline with verification checkpoints.

## Step 1: Set up AWS SSO credentials
```bash
./aws_sso_credentials.sh
```
Verification: Confirm credentials with `aws sts get-caller-identity`

## Step 2: Initialize Terraform backend
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration
./init_backend.sh
```
Verification: Check that backend.tf is configured correctly

## Step 3: Deploy infrastructure
```bash
terraform apply
```
Verification: Confirm EC2 instance is running in AWS console, get instance ID

## Step 4: Build Docker images locally
```bash
cd ../docker
docker-compose build
```
Verification: Run `docker images` to verify images were created

## Step 5: Push Docker images
```bash
# For ECR:
./ecr-push.sh <region> <account-id> <repository-name> <tag>
# For Artifactory:
./artifactory-push.sh <artifactory-url> <repo-name> <username> <password> <image-name> <tag>
```
Verification: Check images in the container registry

## Step 6: Deploy with Helm
```bash
cd ../helm
# Get kubeconfig from EC2
../terraform/ssm_commands.sh <instance-id>
export KUBECONFIG=/path/to/kubeconfig
helm install multi-container-app multi-container-app/
```
Verification: Run `kubectl get pods` to check deployment status

## Step 7: Test application
```bash
kubectl port-forward svc/multi-container-app 8080:8080
```
Verification: Access application at http://localhost:8080

## Step 8: Cleanup (when finished)
```bash
terraform destroy
```

## Notes
- Each step should be verified before proceeding to the next
- For troubleshooting, check logs with `kubectl logs <pod-name>`
- For updates, use `helm upgrade` instead of `helm install`