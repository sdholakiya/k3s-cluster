# K3s Cluster on AWS with GitLab CI/CD

This project automatically deploys a K3s Kubernetes cluster on an AWS EC2 instance using GitLab CI/CD and Terraform. It uses AWS Systems Manager (SSM) for secure, SSH-less connection to the EC2 instance.

## Prerequisites

1. AWS account with appropriate permissions
2. GitLab repository with CI/CD capabilities
3. AWS CLI installed and configured for using SSM

## GitLab CI/CD Setup

Configure the following GitLab CI/CD variables:

- `AWS_ACCESS_KEY_ID`: Your AWS access key ID
- `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key
- `AWS_DEFAULT_REGION`: Your preferred AWS region

## Terraform Configuration

1. Copy the example tfvars file:
   ```
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```

2. Update `terraform.tfvars` with your specific values:
   - VPC ID
   - Private Subnet ID (must be a private subnet)
   - Security Group ID
   - Choose whether to create a new IAM role (`create_iam_role=true`) or use existing one
   - Other customization options
   
## Private Subnet Requirements

This deployment uses only private subnets for enhanced security. The following VPC requirements must be met:

1. A VPC with private subnets configured
2. Required VPC endpoints for SSM connectivity:
   - com.amazonaws.[region].ssm
   - com.amazonaws.[region].ec2messages
   - com.amazonaws.[region].ssmmessages
3. A route from the private subnet to these endpoints

## Security Group Requirements

Ensure your security group allows:
- HTTPS (port 443) inbound for K3s API
- Port 6443 inbound for Kubernetes API
- **Allow HTTPS outbound to AWS SSM endpoints**
- SSH (port 22) inbound (optional, only if not using SSM exclusively)

## IAM Role Requirements

The IAM role needs these permissions (automatically created if `create_iam_role=true`):
- AmazonSSMManagedInstanceCore policy
- EC2 connectivity permissions
- CloudWatch logs permissions

A sample policy is provided in `terraform/ssm_policy.json`.

## Pipeline Usage

The GitLab CI/CD pipeline includes these stages:

1. **Validate**: Validates Terraform configuration
2. **Plan**: Creates a Terraform plan
3. **Apply**: Deploys infrastructure (manual trigger)
4. **Destroy**: Removes infrastructure (manual trigger)

## Connecting via SSM

After deployment, you can connect to the instance using SSM:

```
# Use the helper script
./terraform/ssm_commands.sh <instance-id>

# Or connect directly
aws ssm start-session --target <instance-id>
```

The instance ID will be displayed in the Terraform output.

## Post-Deployment

After successful deployment:
- Kubeconfig is automatically retrieved via SSM and saved to `terraform/output/kubeconfig`
- Instance ID and SSM connection commands are provided in the output
- Use the kubeconfig to connect to your new K3s cluster:
  ```
  export KUBECONFIG=/path/to/terraform/output/kubeconfig
  kubectl get nodes
  ```