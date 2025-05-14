# K3s Cluster on AWS with GitLab CI/CD

This project automatically deploys a K3s Kubernetes cluster on an AWS EC2 instance using GitLab CI/CD and Terraform. It uses AWS Systems Manager (SSM) for secure, SSH-less connection to the EC2 instance, and now supports AWS GovCloud (US-West) region.

## Features

- Deploy in either commercial AWS regions or GovCloud
- Two-stage deployment: EC2 instance creation followed by K3s installation
- Skip EC2 creation stage when only updating K3s configuration
- Support for custom AMIs, including shared AMIs
- Advanced EC2 instance configuration options
- SSM-based management (no need for SSH)
- Remote state management with S3 and DynamoDB

## Prerequisites

1. AWS account with appropriate permissions
2. GitLab repository with CI/CD capabilities
3. AWS CLI installed and configured for using SSM
4. For GovCloud: AWS GovCloud credentials configured

## AWS Authentication

You can use the provided script for AWS SSO authentication:

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

## GitLab CI/CD Setup

1. Make sure the included `.gitlab-ci.yml` file is in your repository's root directory. This defines the CI/CD pipeline.

2. Configure the following GitLab CI/CD variables in your GitLab project:

   - `AWS_ACCESS_KEY_ID`: Your AWS access key ID
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key
   - `AWS_SESSION_TOKEN`: Your AWS session token (if using temporary credentials from SSO)
   - `AWS_DEFAULT_REGION`: Your preferred AWS region

3. You can use the included setup script to automatically set these variables:

   ```bash
   # Make the script executable
   chmod +x setup_gitlab_ci.sh

   # Run the script and follow the prompts
   ./setup_gitlab_ci.sh
   ```

## Deployment Configuration

### 1. Configure Terraform Variables

Create a `terraform.tfvars` file based on one of the provided examples:

```bash
# For commercial AWS regions:
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# For GovCloud:
cp terraform/terraform.tfvars.example.govcloud terraform/terraform.tfvars
```

Edit the file to customize your deployment configuration.

### 2. Initialize Terraform Backend

```bash
cd terraform
./init_backend.sh
```

### 3. Deploy the Infrastructure

#### Full Deployment (EC2 + K3s)

```bash
terraform apply
```

#### EC2 Only (Skip K3s Installation)

```bash
terraform apply -var="skip_k3s_install=true"
```

#### K3s Update Only (Skip EC2 Creation)

```bash
terraform apply -var="skip_ec2_creation=true"
```

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

## Connecting to Your Cluster

After successful deployment:
- Kubeconfig is automatically retrieved via SSM and saved to `terraform/output/kubeconfig`
- Instance ID and SSM connection commands are provided in the output

### Using kubectl

```bash
export KUBECONFIG=/path/to/terraform/output/kubeconfig
kubectl get nodes
```

### Using the SSM helper script

```bash
# Use the helper script
./terraform/ssm_commands.sh <instance-id>

# Or connect directly
aws ssm start-session --target <instance-id>
```

## Terraform Configuration Variables

### Core Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `"us-west-2"` |
| `is_govcloud` | Enable GovCloud support | `false` |
| `skip_ec2_creation` | Skip EC2 creation stage | `false` |
| `skip_k3s_install` | Skip K3s installation | `false` |

### Infrastructure Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_id` | VPC ID | Required |
| `subnet_id` | Subnet ID (private subnet) | Required |
| `security_group_id` | Security Group ID | Required |
| `create_iam_role` | Create IAM role for SSM | `false` |
| `iam_instance_profile` | Existing IAM profile (if not creating) | `""` |

### Instance Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `ami_id` | AMI ID | Required |
| `ami_owners` | AMI owner account IDs | `["self"]` |
| `instance_type` | EC2 instance type | `"t3.medium"` |
| `instance_name` | EC2 instance name | `"k3s-cluster"` |
| `enable_detailed_monitoring` | Enable detailed monitoring | `false` |
| `instance_tags` | Additional EC2 tags | `{}` |

### Storage Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `root_volume_size` | Root volume size (GB) | `50` |
| `root_volume_type` | Root volume type | `"gp3"` |
| `root_volume_iops` | Root volume IOPS | `null` |
| `root_volume_throughput` | Root volume throughput | `null` |
| `additional_ebs_volumes` | Additional EBS volumes | `[]` |

## Notes for GovCloud Deployment

When using AWS GovCloud:

1. Set `is_govcloud = true` in your terraform.tfvars
2. Use a valid GovCloud AMI ID
3. Ensure your AWS CLI is configured with GovCloud credentials
4. Use the appropriate region name (`us-gov-west-1`)