# K3s Cluster on AWS with GitLab CI/CD

This project automatically deploys a K3s Kubernetes cluster on an AWS EC2 instance using GitLab CI/CD and Terraform. It uses AWS Systems Manager (SSM) for secure, SSH-less connection to the EC2 instance.

## Prerequisites

1. AWS account with appropriate permissions
2. GitLab repository with CI/CD capabilities
3. AWS CLI installed and configured for using SSM

## GitLab CI/CD Setup

1. Make sure the included `.gitlab-ci.yml` file is in your repository's root directory. This defines the CI/CD pipeline.

2. Configure the following GitLab CI/CD variables in your GitLab project:

   - `AWS_ACCESS_KEY_ID`: Your AWS access key ID
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key
   - `AWS_SESSION_TOKEN`: Your AWS session token (if using temporary credentials from SSO)
   - `AWS_DEFAULT_REGION`: Your preferred AWS region

3. You can use one of the included setup scripts to automatically set these variables:

   **Option 1: For standard AWS credentials:**
   ```bash
   # Make the script executable
   chmod +x setup_gitlab_ci.sh

   # Run the script and follow the prompts
   ./setup_gitlab_ci.sh
   ```

   **Option 2: For AWS SSO credentials:**
   ```bash
   # Make the script executable
   chmod +x aws_sso_credentials.sh

   # Run the script with parameters
   ./aws_sso_credentials.sh --sso-url https://my-sso-portal.awsapps.com/start --account-id 123456789012 --role-name MyRole

   # Or run without parameters and follow the prompts
   ./aws_sso_credentials.sh

   # You can also specify a custom profile name
   ./aws_sso_credentials.sh --profile my-temp-profile --aws-creds-name my-aws-profile
   ```

   The AWS SSO script provides additional features:
   - Updates your local `~/.aws/credentials` file with a named profile
   - Allows using the credentials with AWS CLI and Terraform
   - Works with AWS SSO authentication and web browser login
   - Provides usage examples for common AWS operations

4. Ensure your GitLab runner has Docker available (the pipeline uses Terraform Docker images)

> **Note**: If using AWS SSO, remember that temporary credentials will expire (typically after 1-12 hours). You'll need to refresh them periodically by running the SSO script again.

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
   - S3 bucket name for Terraform state storage
   - Other customization options

3. Initialize Terraform with S3 backend:
   ```
   cd terraform
   ./init_backend.sh
   ```

   This will configure Terraform to use the S3 bucket for state storage and DynamoDB for state locking.
   
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

1. **Validate**: Validates Terraform configuration and checks formatting
2. **Plan**: Creates a Terraform plan and stores it as an artifact
3. **Apply**: Deploys infrastructure (manual trigger) and retrieves kubeconfig
4. **Destroy**: Removes infrastructure (manual trigger)
5. **Test Connection**: Optional stage to verify Kubernetes connectivity

### Running the Pipeline

1. The pipeline will automatically run the **Validate** and **Plan** stages on:
   - Pushes to the main branch
   - Merge/Pull Requests

2. The **Apply** and **Destroy** stages require manual approval in the GitLab UI:
   - Go to CI/CD → Pipelines in your GitLab project
   - Find your pipeline and click on it
   - Click the "Play" button next to the "apply" job to deploy
   - Click the "Play" button next to the "destroy" job to tear down

3. After successful deployment, the kubeconfig and instance info will be available as pipeline artifacts

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