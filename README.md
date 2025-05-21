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
- Multi-container application deployments using Helm
- Communication visualization between containers
- Access to K3s API from outside private subnet
- GitLab CI/CD pipeline for automated deployment
- Monitoring setup for container communication

## Prerequisites

1. AWS account with appropriate permissions
2. GitLab repository with CI/CD capabilities
3. AWS CLI installed and configured for using SSM
4. For GovCloud: AWS GovCloud credentials configured
5. Helm installed (v3+) for local deployments

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
   - `TF_VAR_terraform_state_bucket`: S3 bucket name for Terraform state
   - `TF_VAR_vpc_id`: Your VPC ID
   - `TF_VAR_subnet_id`: Your subnet ID
   - `TF_VAR_security_group_id`: Your security group ID
   
   For container registry access (choose one option):
   
   **For AWS ECR:**
   - `USE_ECR`: Set to "true" to enable ECR image builds
   - AWS credentials from above are reused for ECR access
   
   **For Artifactory:**
   - `USE_ARTIFACTORY`: Set to "true" to enable Artifactory image builds
   - `ARTIFACTORY_URL`: Your Artifactory instance URL
   - `ARTIFACTORY_REPO`: Your Artifactory Docker repository name
   - `ARTIFACTORY_USERNAME`: Your Artifactory username
   - `ARTIFACTORY_PASSWORD`: Your Artifactory password/API key

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
4. **Build**: Builds and pushes container images to your selected registry (ECR or Artifactory)
5. **Deploy**: Deploys the Helm chart with the multi-container application using the custom images
6. **Test**: Tests the deployment and generates a test report
7. **Destroy**: Removes infrastructure (manual trigger)

### Running the Pipeline

1. The pipeline will automatically run the **Validate** and **Plan** stages on:
   - Pushes to the main branch
   - Merge/Pull Requests

2. The **Apply**, **Build**, **Deploy**, **Test**, and **Destroy** stages require manual approval in the GitLab UI:
   - Go to CI/CD → Pipelines in your GitLab project
   - Find your pipeline and click on it
   - Click the "Play" button next to the "apply" job to deploy infrastructure
   - After successful deployment, trigger the appropriate build job:
     - For ECR: Trigger "build_and_push_ecr" job
     - For Artifactory: Trigger "build_and_push_artifactory" job
     - Skip this step to use default images
   - Next, trigger the appropriate deploy job:
     - For ECR: Trigger "deploy_from_ecr" job
     - For Artifactory: Trigger "deploy_from_artifactory" job
     - For default images: Trigger "deploy_application" job
   - Test the application by triggering the "test_application" job
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

### Accessing the K3s API from Outside the Private Subnet

To access the K3s API from outside the private subnet:

1. Use the access script that creates an SSM port forwarding tunnel:
   ```bash
   ./terraform/access_k3s_api.sh
   ```

2. Keep the terminal with the port forwarding session open

3. In a new terminal, configure kubectl to use the local endpoint:
   ```bash
   export KUBECONFIG=/path/to/terraform/output/kubeconfig
   kubectl config set-cluster default --server=https://localhost:6443
   ```

4. Test the connection:
   ```bash
   kubectl get nodes
   ```

## Multi-Container Application

### Custom Container Images

The project includes Dockerfiles and configuration to build your own custom container images:

```
docker/
├── docker-compose.yml           # Defines all three containers
├── build-and-push.sh            # Script for generic registries
├── ecr-push.sh                  # Script for AWS ECR
├── artifactory-push.sh          # Script for Artifactory
├── frontend/                    # Frontend container (Nginx)
├── backend/                     # Backend container (Python Flask)
└── database/                    # Database container (PostgreSQL)
```

The project supports multiple container registry options:

#### Generic Container Registry

```bash
cd docker
./build-and-push.sh your-registry.example.com v1.0.0
```

#### AWS ECR (Elastic Container Registry)

```bash
cd docker
./ecr-push.sh us-west-2 123456789012 k3s-app v1.0.0
```

#### JFrog Artifactory

```bash
cd docker
./artifactory-push.sh https://artifactory.example.com docker-local myuser mypassword k3s-app v1.0.0
```

After pushing your images, update the Helm chart's `values.yaml` with your image references or use the automatically generated values files in the CI/CD pipeline.

For more details, see the [Docker README](docker/README.md).

### Helm Chart Structure

The project includes a Helm chart for deploying a multi-container application:

```
helm/multi-container-app/
├── Chart.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   ├── pvc.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   └── servicemonitor.yaml
└── values.yaml
```

### Container Configuration

The Helm chart deploys three containers in a single pod:

1. **Frontend** (Nginx): Serves the web interface and container communication dashboard
2. **Backend** (Python): Processes API requests
3. **Database** (PostgreSQL): Stores application data

All containers communicate with each other within the pod, demonstrating inter-container communication patterns.

### Monitoring Container Communication

The deployment includes a visual dashboard that shows the communication between containers:

1. Forward the application port to your local machine:
   ```bash
   kubectl port-forward svc/multi-container-app 8080:8080
   ```

2. Open a browser and navigate to:
   ```
   http://localhost:8080
   ```

3. The dashboard will show real-time visualization of container communication.

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

### Terraform State Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `terraform_state_bucket` | S3 bucket for Terraform state | Required |
| `terraform_state_key` | S3 key for Terraform state | `"k3s-cluster/terraform.tfstate"` |
| `terraform_state_region` | AWS region for Terraform state | `"us-west-2"` |
| `terraform_state_dynamodb_table` | DynamoDB table for state locking | `"terraform-state-lock"` |

## Notes for GovCloud Deployment

When using AWS GovCloud:

1. Set `is_govcloud = true` in your terraform.tfvars
2. Use a valid GovCloud AMI ID
3. Ensure your AWS CLI is configured with GovCloud credentials
4. Use the appropriate region name (`us-gov-west-1`)