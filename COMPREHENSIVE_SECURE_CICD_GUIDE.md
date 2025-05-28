# Comprehensive Guide: Secure CI/CD for K3s Cluster

## Table of Contents
1. [Understanding the Security Problem](#understanding-the-security-problem)
2. [The OIDC Federation Solution](#the-oidc-federation-solution)
3. [Architecture Overview](#architecture-overview)
4. [Prerequisites and Setup](#prerequisites-and-setup)
5. [Detailed Implementation Steps](#detailed-implementation-steps)
6. [Configuration Deep Dive](#configuration-deep-dive)
7. [Security Analysis](#security-analysis)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Best Practices and Recommendations](#best-practices-and-recommendations)

---

## Understanding the Security Problem

### Traditional Approach Issues

When setting up CI/CD pipelines, developers traditionally store AWS credentials directly in GitLab CI/CD variables:

```yaml
# ❌ INSECURE: Traditional approach
variables:
  AWS_ACCESS_KEY_ID: "AKIA..." 
  AWS_SECRET_ACCESS_KEY: "abc123..."
```

**Problems with this approach:**

1. **Long-lived credentials**: Keys don't expire automatically
2. **Over-privileged access**: Often use admin-level permissions
3. **Credential sprawl**: Same keys used across multiple projects
4. **No audit trail**: Hard to track which pipeline used which permissions
5. **Rotation complexity**: Manual process to update keys
6. **Exposure risk**: Keys visible to all project maintainers

### Real-World Security Risks

```bash
# Example of exposed credentials in logs
echo "Deploying with AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
# This accidentally logs your access key!

# Or in error messages
aws s3 ls s3://my-bucket --profile my-profile
# Error: The AWS Access Key Id you provided does not exist in our records. (Key: AKIA...)
```

**Impact of credential compromise:**
- Unauthorized resource creation/deletion
- Data exfiltration from S3 buckets
- Cryptocurrency mining on EC2 instances
- Privilege escalation attacks
- Compliance violations (SOX, PCI, HIPAA)

---

## The OIDC Federation Solution

### What is OIDC Federation?

OpenID Connect (OIDC) federation allows external identity providers (like GitLab) to assume AWS IAM roles without storing long-lived credentials.

**How it works:**
1. GitLab generates a JWT (JSON Web Token) for each CI/CD job
2. AWS validates the JWT against a trusted identity provider
3. If valid, AWS issues temporary credentials (15 minutes - 12 hours)
4. Pipeline uses temporary credentials for AWS operations
5. Credentials automatically expire when job completes

### JWT Token Structure

```json
{
  "header": {
    "typ": "JWT",
    "alg": "RS256",
    "kid": "example-key-id"
  },
  "payload": {
    "iss": "https://gitlab.com",
    "sub": "project_path:username/project:ref_type:branch:ref:main",
    "aud": "https://gitlab.com",
    "iat": 1640995200,
    "exp": 1641001200,
    "namespace_path": "username",
    "project_path": "username/project",
    "ref": "main",
    "ref_type": "branch"
  }
}
```

**Key fields for AWS trust policy:**
- `iss`: Issuer (GitLab URL)
- `sub`: Subject (project and branch info)
- `aud`: Audience (GitLab URL)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitLab CI/CD  │    │   AWS IAM OIDC  │    │   AWS Resources │
│                 │    │    Federation   │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │CI Pipeline│──┼────┼──│OIDC Provider│──┼────┼──│EC2/ECR/S3 │  │
│  │           │  │    │  │           │  │    │  │           │  │
│  │JWT Token  │  │    │  │Trust Policy│  │    │  │K3s Cluster│  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Component Breakdown

1. **GitLab CI/CD Runner**
   - Generates JWT tokens per job
   - Executes pipeline steps
   - Assumes AWS IAM roles

2. **AWS IAM OIDC Identity Provider**
   - Validates GitLab JWT tokens
   - Maps tokens to IAM roles
   - Issues temporary credentials

3. **IAM Roles with Trust Policies**
   - Define which GitLab projects/branches can assume roles
   - Specify permission boundaries
   - Enable branch-based access control

4. **Target AWS Resources**
   - EC2 instances for K3s cluster
   - ECR for container images
   - S3 for Terraform state
   - DynamoDB for state locking

### Security Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Account Boundary                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                Region Boundary                      │   │
│  │  ┌─────────────────┐  ┌─────────────────────────┐   │   │
│  │  │  Main Branch    │  │    Feature Branch       │   │   │
│  │  │     Role        │  │        Role             │   │   │
│  │  │                 │  │                         │   │   │
│  │  │ Full Deploy     │  │   Read-Only +           │   │   │
│  │  │ Permissions     │  │   Planning Only         │   │   │
│  │  └─────────────────┘  └─────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites and Setup

### Required Tools and Permissions

#### 1. GitLab CLI (glab)
```bash
# macOS
brew install glab

# Linux
curl -s https://api.github.com/repos/cli/cli/releases/latest \
  | grep "browser_download_url.*linux_amd64.tar.gz" \
  | cut -d '"' -f 4 \
  | xargs curl -L | tar xz

# Authenticate
glab auth login
```

**Verify installation:**
```bash
glab --version
glab auth status
```

#### 2. AWS CLI v2
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Configure AWS CLI:**
```bash
# Option 1: Traditional credentials
aws configure

# Option 2: SSO (recommended)
aws configure sso
aws sso login

# Option 3: Use your existing SSO script
./aws_sso_credentials.sh
```

**Required AWS permissions for setup:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider",
        "iam:CreateRole",
        "iam:CreatePolicy",
        "iam:AttachRolePolicy",
        "iam:GetRole",
        "iam:GetPolicy",
        "iam:TagRole",
        "iam:TagPolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

#### 3. Terraform
```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

**Verify installation:**
```bash
terraform --version
```

### Environment Preparation

#### 1. AWS Account Information
```bash
# Get your AWS account ID
aws sts get-caller-identity --query "Account" --output text

# Get your current region
aws configure get region

# Verify permissions
aws iam list-roles --max-items 1
```

#### 2. GitLab Project Information
```bash
# List your GitLab projects
glab repo list

# Get project details
glab repo view username/project-name
```

#### 3. Network Requirements
Ensure your VPC has:
- Private subnet with internet access (NAT Gateway)
- VPC Endpoints for SSM (required for EC2 access)
- Security group allowing HTTPS outbound

---

## Detailed Implementation Steps

### Step 1: Understanding the Terraform Configuration

#### File: `terraform/cicd_iam_role.tf`

**OIDC Identity Provider:**
```hcl
# Creates trust relationship between AWS and GitLab
resource "aws_iam_openid_connect_provider" "gitlab" {
  url = var.gitlab_url  # https://gitlab.com

  client_id_list = [
    var.gitlab_url
  ]

  # GitLab's SSL certificate thumbprint
  # This validates that JWT tokens come from the real GitLab
  thumbprint_list = [
    data.tls_certificate.gitlab.certificates[0].sha1_fingerprint
  ]
}
```

**Main Branch Role Trust Policy:**
```hcl
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.gitlab.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Only allow main branch of specific project
          "${var.gitlab_url}:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:main"
        }
      }
    }
  ]
})
```

**Feature Branch Role Trust Policy:**
```hcl
Condition = {
  StringLike = {
    # Allow any branch from the project
    "${var.gitlab_url}:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:*"
  }
  StringNotEquals = {
    # Except main branch (handled by main role)
    "${var.gitlab_url}:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:main"
  }
}
```

#### Permission Policies Deep Dive

**EC2 Permissions (K3s Cluster Management):**
```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:DescribeInstances",
    "ec2:DescribeInstanceStatus",
    "ec2:RunInstances",
    "ec2:TerminateInstances",
    "ec2:StartInstances",
    "ec2:StopInstances",
    "ec2:CreateTags",
    "ec2:DeleteTags"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:RequestedRegion": "us-west-2"
    }
  }
}
```

**ECR Permissions (Container Registry):**
```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:PutImage"
  ],
  "Resource": "arn:aws:ecr:region:account:repository/k3s-*"
}
```

**S3 Permissions (Terraform State):**
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:ListBucket",
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::terraform-state-bucket",
    "arn:aws:s3:::terraform-state-bucket/*"
  ]
}
```

### Step 2: GitLab CI/CD Pipeline Configuration

#### File: `.gitlab-ci-oidc.yml`

**OIDC Authentication Setup:**
```yaml
before_script:
  - |
    # Determine role based on branch
    if [ "$CI_COMMIT_REF_NAME" = "main" ]; then
      export AWS_ROLE_ARN="${GITLAB_CICD_MAIN_ROLE_ARN}"
    else
      export AWS_ROLE_ARN="${GITLAB_CICD_FEATURE_ROLE_ARN}"
    fi
    
    # Set up OIDC token
    export AWS_WEB_IDENTITY_TOKEN_FILE="/tmp/web-identity-token"
    echo "$CI_JOB_JWT_V2" > "$AWS_WEB_IDENTITY_TOKEN_FILE"
    export AWS_ROLE_SESSION_NAME="gitlab-ci-${CI_JOB_ID}"
    
    # Configure AWS CLI for OIDC
    aws configure set region $AWS_DEFAULT_REGION
    aws configure set web_identity_token_file $AWS_WEB_IDENTITY_TOKEN_FILE
    aws configure set role_arn $AWS_ROLE_ARN
    aws configure set role_session_name $AWS_ROLE_SESSION_NAME
    
    # Verify authentication
    aws sts get-caller-identity
```

**Branch-Based Job Rules:**
```yaml
# Main branch: Full deployment
terraform:apply:
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual

# Feature branches: Plan only
terraform:plan:
  rules:
    - if: $CI_COMMIT_BRANCH =~ /^feature\/.*/
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

**Container Build with ECR:**
```yaml
build:containers:
  before_script:
    - apk add --no-cache aws-cli
    - !reference [default, before_script]
    - |
      # ECR authentication
      aws ecr get-login-password --region $AWS_DEFAULT_REGION | \
        docker login --username AWS --password-stdin \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
  script:
    - |
      if [ "$CI_COMMIT_REF_NAME" = "main" ]; then
        # Build and push on main branch
        docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPO_PREFIX}-backend:${CI_COMMIT_SHA} backend/
        docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REPO_PREFIX}-backend:${CI_COMMIT_SHA}
      else
        # Validate build on feature branches
        docker build backend/ --dry-run
      fi
```

### Step 3: Automated Setup Script

#### File: `setup_secure_gitlab_ci.sh`

**Prerequisites Check:**
```bash
check_prerequisites() {
    # GitLab CLI
    if ! command -v glab &> /dev/null; then
        echo "Error: GitLab CLI (glab) not found."
        exit 1
    fi
    
    # GitLab authentication
    if ! glab auth status &> /dev/null; then
        echo "Error: Not authenticated with GitLab."
        exit 1
    fi
    
    # AWS CLI and authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Error: AWS CLI not configured."
        exit 1
    fi
}
```

**Terraform Deployment:**
```bash
# Deploy only IAM-related resources
terraform plan -target=aws_iam_openid_connect_provider.gitlab \
               -target=aws_iam_policy.cicd_policy \
               -target=aws_iam_role.gitlab_cicd_main \
               -target=aws_iam_role.gitlab_cicd_feature \
               -out=iam-plan

terraform apply -auto-approve iam-plan
```

**GitLab Variable Configuration:**
```bash
# Set role ARNs
MAIN_ROLE_ARN=$(terraform output -raw gitlab_cicd_main_role_arn)
FEATURE_ROLE_ARN=$(terraform output -raw gitlab_cicd_feature_role_arn)

glab variable set GITLAB_CICD_MAIN_ROLE_ARN -p "$GITLAB_PROJECT" -v "$MAIN_ROLE_ARN"
glab variable set GITLAB_CICD_FEATURE_ROLE_ARN -p "$GITLAB_PROJECT" -v "$FEATURE_ROLE_ARN"
```

### Step 4: Manual Setup Process

#### Phase 1: Terraform Infrastructure

1. **Set project variables:**
```bash
cd terraform
export TF_VAR_gitlab_project_path="your-username/your-project"
export TF_VAR_gitlab_url="https://gitlab.com"
```

2. **Initialize Terraform:**
```bash
terraform init -backend=false
```

3. **Deploy IAM resources:**
```bash
terraform apply -target=aws_iam_openid_connect_provider.gitlab \
               -target=aws_iam_policy.cicd_policy \
               -target=aws_iam_policy.cicd_feature_policy \
               -target=aws_iam_role.gitlab_cicd_main \
               -target=aws_iam_role.gitlab_cicd_feature \
               -target=aws_iam_role_policy_attachment.gitlab_cicd_main_policy \
               -target=aws_iam_role_policy_attachment.gitlab_cicd_feature_policy
```

4. **Extract role ARNs:**
```bash
MAIN_ROLE_ARN=$(terraform output -raw gitlab_cicd_main_role_arn)
FEATURE_ROLE_ARN=$(terraform output -raw gitlab_cicd_feature_role_arn)
OIDC_PROVIDER_ARN=$(terraform output -raw gitlab_oidc_provider_arn)

echo "Main Role ARN: $MAIN_ROLE_ARN"
echo "Feature Role ARN: $FEATURE_ROLE_ARN"
echo "OIDC Provider ARN: $OIDC_PROVIDER_ARN"
```

#### Phase 2: GitLab Configuration

1. **Set AWS configuration variables:**
```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
AWS_REGION=$(aws configure get region || echo "us-west-2")

glab variable set AWS_DEFAULT_REGION -p "your-username/your-project" -v "$AWS_REGION"
glab variable set AWS_ACCOUNT_ID -p "your-username/your-project" -v "$AWS_ACCOUNT_ID"
```

2. **Set role ARNs:**
```bash
glab variable set GITLAB_CICD_MAIN_ROLE_ARN -p "your-username/your-project" -v "$MAIN_ROLE_ARN"
glab variable set GITLAB_CICD_FEATURE_ROLE_ARN -p "your-username/your-project" -v "$FEATURE_ROLE_ARN"
```

3. **Set infrastructure variables:**
```bash
glab variable set TF_VAR_terraform_state_bucket -p "your-username/your-project" -v "your-terraform-state-bucket"
glab variable set TF_VAR_vpc_id -p "your-username/your-project" -v "vpc-xxxxxxxx"
glab variable set TF_VAR_subnet_id -p "your-username/your-project" -v "subnet-xxxxxxxx"
glab variable set TF_VAR_security_group_id -p "your-username/your-project" -v "sg-xxxxxxxx"
```

4. **Set container registry variables:**
```bash
glab variable set USE_ECR -p "your-username/your-project" -v "true"
glab variable set ECR_REPO_PREFIX -p "your-username/your-project" -v "k3s-app"
```

#### Phase 3: Pipeline Activation

1. **Replace pipeline configuration:**
```bash
cp .gitlab-ci-oidc.yml .gitlab-ci.yml
```

2. **Commit and push changes:**
```bash
git add .
git commit -m "Implement secure OIDC-based CI/CD pipeline"
git push origin main
```

3. **Verify pipeline execution:**
- Go to GitLab → Your Project → CI/CD → Pipelines
- Check that jobs assume roles successfully
- Verify AWS operations work without stored credentials

---

## Configuration Deep Dive

### GitLab CI/CD Variables Explained

| Variable | Purpose | Example Value | Security Level |
|----------|---------|---------------|----------------|
| `AWS_DEFAULT_REGION` | AWS region for resources | `us-west-2` | Public |
| `AWS_ACCOUNT_ID` | Your AWS account ID | `123456789012` | Public |
| `GITLAB_CICD_MAIN_ROLE_ARN` | IAM role for main branch | `arn:aws:iam::123456789012:role/gitlab-k3s-cicd-main` | Public |
| `GITLAB_CICD_FEATURE_ROLE_ARN` | IAM role for feature branches | `arn:aws:iam::123456789012:role/gitlab-k3s-cicd-feature` | Public |
| `TF_VAR_terraform_state_bucket` | S3 bucket for Terraform state | `my-terraform-state-bucket` | Public |
| `TF_VAR_vpc_id` | VPC ID for infrastructure | `vpc-12345678` | Public |
| `TF_VAR_subnet_id` | Subnet ID for EC2 instances | `subnet-12345678` | Public |
| `TF_VAR_security_group_id` | Security group for EC2 | `sg-12345678` | Public |
| `ECR_REPO_PREFIX` | Prefix for ECR repositories | `k3s-app` | Public |

**Note:** None of these variables contain sensitive information like passwords or access keys!

### Role Permission Matrix

| Operation | Main Branch Role | Feature Branch Role | Justification |
|-----------|------------------|---------------------|---------------|
| EC2 Create/Delete | ✅ | ❌ | Production changes only from main |
| EC2 Describe | ✅ | ✅ | Planning requires read access |
| ECR Push | ✅ | ❌ | Only deploy from main branch |
| ECR Pull | ✅ | ✅ | Feature branches need base images |
| S3 State Write | ✅ | ❌ | State changes only from main |
| S3 State Read | ✅ | ✅ | Planning requires state access |
| DynamoDB Lock Write | ✅ | ❌ | State locking only from main |
| DynamoDB Lock Read | ✅ | ✅ | Planning checks locks |

### Pipeline Execution Flow

#### Main Branch Pipeline:
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Validate   │───▶│    Plan     │───▶│    Build    │───▶│   Deploy    │
│             │    │             │    │             │    │             │
│ Code checks │    │ Terraform   │    │ Container   │    │ Terraform   │
│ Lint/Format │    │ plan        │    │ images      │    │ apply +     │
│             │    │             │    │ ECR push    │    │ Helm deploy │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     Auto               Auto              Manual             Manual
```

#### Feature Branch Pipeline:
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Validate   │───▶│    Plan     │───▶│   Cleanup   │
│             │    │             │    │             │
│ Code checks │    │ Terraform   │    │ Resource    │
│ Lint/Format │    │ plan only   │    │ cleanup     │
│             │    │ (read-only) │    │ (manual)    │
└─────────────┘    └─────────────┘    └─────────────┘
     Auto               Auto              Manual
```

### Container Registry Integration

#### ECR Repository Structure:
```
AWS Account: 123456789012
Region: us-west-2
Repositories:
├── k3s-app-backend
├── k3s-app-frontend
└── k3s-app-database
```

#### Image Tagging Strategy:
```bash
# Main branch images
123456789012.dkr.ecr.us-west-2.amazonaws.com/k3s-app-backend:a1b2c3d4
123456789012.dkr.ecr.us-west-2.amazonaws.com/k3s-app-frontend:a1b2c3d4
123456789012.dkr.ecr.us-west-2.amazonaws.com/k3s-app-database:a1b2c3d4

# Where a1b2c3d4 is the Git commit SHA
```

#### ECR Authentication in Pipeline:
```yaml
before_script:
  - |
    # ECR login using temporary credentials
    aws ecr get-login-password --region $AWS_DEFAULT_REGION | \
      docker login --username AWS --password-stdin \
      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
```

---

## Security Analysis

### Threat Model

#### Traditional Approach Threats:
1. **Credential Theft**
   - Threat: Access keys exposed in logs/code
   - Impact: Full AWS account compromise
   - Likelihood: High (common misconfiguration)

2. **Privilege Escalation**
   - Threat: Over-privileged keys used for lateral movement
   - Impact: Access to unrelated resources
   - Likelihood: Medium (administrative laziness)

3. **Credential Sprawl**
   - Threat: Same keys used across multiple systems
   - Impact: Blast radius expansion
   - Likelihood: High (operational convenience)

#### OIDC Approach Mitigations:

1. **No Long-Lived Credentials**
   ```bash
   # Traditional approach
   AWS_ACCESS_KEY_ID=AKIA...  # Never expires
   AWS_SECRET_ACCESS_KEY=...  # Never expires
   
   # OIDC approach
   AWS_ACCESS_KEY_ID=ASIA...  # Expires in 1 hour
   AWS_SECRET_ACCESS_KEY=...  # Expires in 1 hour
   AWS_SESSION_TOKEN=...      # Required for temporary creds
   ```

2. **Branch-Based Access Control**
   ```json
   {
     "Condition": {
       "StringEquals": {
         "gitlab.com:sub": "project_path:username/project:ref_type:branch:ref:main"
       }
     }
   }
   ```

3. **Minimal Permission Sets**
   ```json
   {
     "Effect": "Allow",
     "Action": "ec2:RunInstances",
     "Resource": "*",
     "Condition": {
       "StringEquals": {
         "aws:RequestedRegion": "us-west-2"
       },
       "ForAllValues:StringEquals": {
         "ec2:InstanceType": ["t3.medium", "t3.large"]
       }
     }
   }
   ```

### Security Controls Implemented

#### 1. Identity and Access Management
- **OIDC Provider Validation**: JWT signature verification
- **Trust Policy Constraints**: Project and branch-specific access
- **Role Separation**: Different roles for different environments
- **Permission Boundaries**: Least privilege principle

#### 2. Network Security
- **Region Restrictions**: Operations limited to specific AWS regions
- **VPC Isolation**: Resources deployed in private subnets
- **Security Group Controls**: Restrictive ingress/egress rules

#### 3. Data Protection
- **Encryption in Transit**: TLS for all AWS API calls
- **Encryption at Rest**: Encrypted EBS volumes and S3 buckets
- **State File Security**: Terraform state in encrypted S3 bucket

#### 4. Monitoring and Auditing
- **CloudTrail Integration**: All API calls logged
- **GitLab Audit Logs**: Pipeline execution tracking
- **Resource Tagging**: Cost allocation and access tracking

### Compliance Considerations

#### SOC 2 Type II
- **Access Control**: Role-based access with branch restrictions
- **Change Management**: All infrastructure changes via GitLab pipeline
- **Monitoring**: Comprehensive logging and alerting

#### PCI DSS
- **Network Segmentation**: Isolated VPC with private subnets
- **Access Control**: Multi-factor authentication via GitLab SSO
- **Encryption**: Data encrypted in transit and at rest

#### HIPAA
- **Access Logs**: All access tracked in CloudTrail
- **Encryption**: PHI encrypted using AWS KMS
- **Access Control**: Role-based access with audit trail

---

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: "AssumeRoleWithWebIdentity failed"

**Error Message:**
```
An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: 
Invalid identity token
```

**Diagnosis Steps:**
```bash
# Check GitLab project path
echo "Project path in trust policy: ${TF_VAR_gitlab_project_path}"
echo "Actual GitLab project: ${CI_PROJECT_PATH}"

# Verify JWT token format
echo "$CI_JOB_JWT_V2" | cut -d. -f2 | base64 -d | jq .

# Check OIDC provider
aws iam list-open-id-connect-providers
```

**Common Causes:**
1. **Project path mismatch**
   ```hcl
   # Wrong
   "gitlab.com:sub" = "project_path:username/wrong-project:ref_type:branch:ref:main"
   
   # Correct
   "gitlab.com:sub" = "project_path:username/correct-project:ref_type:branch:ref:main"
   ```

2. **Branch name mismatch**
   ```bash
   # Check actual branch name
   echo "Branch: $CI_COMMIT_REF_NAME"
   
   # Trust policy expects exact match
   "ref:main" != "ref:master"
   ```

3. **OIDC provider thumbprint**
   ```bash
   # Get current GitLab thumbprint
   openssl s_client -servername gitlab.com -connect gitlab.com:443 -showcerts < /dev/null 2>/dev/null | \
     openssl x509 -fingerprint -sha1 -noout | cut -d= -f2 | tr -d ':'
   ```

**Solutions:**
```bash
# Update trust policy
terraform apply -target=aws_iam_role.gitlab_cicd_main

# Verify role can be assumed
aws sts assume-role-with-web-identity \
  --role-arn $GITLAB_CICD_MAIN_ROLE_ARN \
  --role-session-name test-session \
  --web-identity-token "$CI_JOB_JWT_V2"
```

#### Issue 2: "Access Denied" for AWS Operations

**Error Message:**
```
An error occurred (AccessDenied) when calling the RunInstances operation: 
User: arn:aws:sts::123456789012:assumed-role/gitlab-k3s-cicd-main/gitlab-ci-12345 
is not authorized to perform: ec2:RunInstances on resource: arn:aws:ec2:us-west-2:123456789012:instance/*
```

**Diagnosis Steps:**
```bash
# Check assumed role identity
aws sts get-caller-identity

# List attached policies
aws iam list-attached-role-policies --role-name gitlab-k3s-cicd-main

# Check policy permissions
aws iam get-policy-version --policy-arn arn:aws:iam::123456789012:policy/k3s-cicd-policy --version-id v1
```

**Common Causes:**
1. **Insufficient permissions in policy**
2. **Resource constraints not met**
3. **Condition constraints not satisfied**

**Solutions:**
```bash
# Add missing permissions
terraform apply -target=aws_iam_policy.cicd_policy

# Check resource constraints
aws ec2 describe-availability-zones --region us-west-2
aws ec2 describe-subnets --subnet-ids subnet-12345678
```

#### Issue 3: Container Build Failures

**Error Message:**
```
Error response from daemon: Get https://123456789012.dkr.ecr.us-west-2.amazonaws.com/v2/: 
no basic auth credentials
```

**Diagnosis Steps:**
```bash
# Check ECR authentication
aws ecr get-login-password --region us-west-2

# Verify ECR repositories exist
aws ecr describe-repositories --region us-west-2

# Check Docker login
docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-west-2.amazonaws.com < /dev/null
```

**Solutions:**
```bash
# Create ECR repositories
aws ecr create-repository --repository-name k3s-app-backend --region us-west-2
aws ecr create-repository --repository-name k3s-app-frontend --region us-west-2
aws ecr create-repository --repository-name k3s-app-database --region us-west-2

# Fix Docker authentication in pipeline
aws ecr get-login-password --region $AWS_DEFAULT_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
```

#### Issue 4: Terraform State Lock Issues

**Error Message:**
```
Error locking state: Error acquiring the state lock: ConditionalCheckFailedException: 
The conditional request failed
```

**Diagnosis Steps:**
```bash
# Check DynamoDB table
aws dynamodb describe-table --table-name terraform-state-lock

# List current locks
aws dynamodb scan --table-name terraform-state-lock

# Check S3 bucket access
aws s3 ls s3://your-terraform-state-bucket/
```

**Solutions:**
```bash
# Force unlock (use carefully!)
terraform force-unlock LOCK_ID

# Create DynamoDB table if missing
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### Debug Commands Reference

#### AWS CLI Debug Commands
```bash
# Enable debug logging
export AWS_DEBUG=1

# Check credentials
aws sts get-caller-identity --debug

# Test assume role
aws sts assume-role-with-web-identity \
  --role-arn $AWS_ROLE_ARN \
  --role-session-name debug-session \
  --web-identity-token "$CI_JOB_JWT_V2" \
  --debug

# List IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `gitlab`)]'

# Get role trust policy
aws iam get-role --role-name gitlab-k3s-cicd-main \
  --query 'Role.AssumeRolePolicyDocument'
```

#### GitLab CI Debug Commands
```bash
# In pipeline, add debug output
echo "Debug Information:"
echo "Project Path: $CI_PROJECT_PATH"
echo "Branch: $CI_COMMIT_REF_NAME"
echo "JWT Subject: $(echo $CI_JOB_JWT_V2 | cut -d. -f2 | base64 -d | jq -r .sub)"
echo "Role ARN: $AWS_ROLE_ARN"
```

#### Terraform Debug Commands
```bash
# Enable debug logging
export TF_LOG=DEBUG

# Check state
terraform show

# Validate configuration
terraform validate

# Plan with detailed output
terraform plan -detailed-exitcode
```

---

## Best Practices and Recommendations

### Security Best Practices

#### 1. Principle of Least Privilege
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-west-2"
        },
        "ForAllValues:StringEquals": {
          "ec2:InstanceType": [
            "t3.medium",
            "t3.large"
          ]
        },
        "StringLike": {
          "ec2:SecurityGroups": [
            "arn:aws:ec2:us-west-2:*:security-group/sg-k3s-*"
          ]
        }
      }
    }
  ]
}
```

#### 2. Environment Separation
```bash
# Use separate AWS accounts
Production:  123456789012
Staging:     234567890123
Development: 345678901234

# Or separate regions
Production:  us-west-2
Staging:     us-east-1
Development: us-east-2
```

#### 3. Resource Tagging Strategy
```hcl
resource "aws_instance" "k3s_server" {
  tags = {
    Name        = "k3s-server-${var.environment}"
    Environment = var.environment
    Project     = "k3s-cluster"
    Owner       = "devops-team"
    CostCenter  = "engineering"
    ManagedBy   = "terraform"
    GitLabProject = var.gitlab_project_path
  }
}
```

#### 4. Monitoring and Alerting
```yaml
# CloudWatch Alarms
UnauthorizedAPICallsAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: k3s-unauthorized-api-calls
    MetricName: ErrorCount
    Namespace: CloudTrailMetrics
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 1
    ComparisonOperator: GreaterThanOrEqualToThreshold
```

### Operational Best Practices

#### 1. Pipeline Organization
```yaml
# Use consistent naming
stages:
  - validate    # Code quality and security checks
  - plan       # Infrastructure planning
  - build      # Artifact creation
  - deploy     # Infrastructure and application deployment
  - test       # Integration and smoke tests
  - cleanup    # Resource cleanup for feature branches

# Use descriptive job names
terraform:validate:security-scan:
terraform:plan:infrastructure:
build:containers:multi-arch:
deploy:infrastructure:k3s-cluster:
```

#### 2. Artifact Management
```bash
# Container image lifecycle
Production:  Keep for 90 days
Staging:     Keep for 30 days
Development: Keep for 7 days

# Terraform plans
Keep for 1 week (GitLab artifacts)

# State backups
Keep for 30 days with versioning
```

#### 3. Emergency Procedures
```bash
# Break glass access
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/emergency-access \
  --role-session-name emergency-$(date +%s) \
  --external-id EMERGENCY_TOKEN

# Pipeline disable
glab variable set PIPELINE_DISABLED -p project -v "true"

# Rollback procedures
git revert HEAD
git push origin main
```

### Performance Optimization

#### 1. Pipeline Optimization
```yaml
# Parallel job execution
terraform:plan:
  parallel:
    matrix:
      - ENVIRONMENT: [staging, production]

# Cache optimization
cache:
  key: 
    files:
      - terraform/.terraform.lock.hcl
      - docker/*/Dockerfile
  paths:
    - terraform/.terraform/
    - docker/cache/
```

#### 2. Resource Optimization
```hcl
# Right-sizing instances
variable "instance_types" {
  default = {
    development = "t3.medium"
    staging     = "t3.large"
    production  = "t3.xlarge"
  }
}

# Spot instances for non-production
resource "aws_instance" "k3s_server" {
  instance_type = var.environment == "production" ? "t3.xlarge" : "t3.large"
  
  dynamic "instance_market_options" {
    for_each = var.environment != "production" ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price = "0.05"
      }
    }
  }
}
```

### Compliance and Governance

#### 1. Change Management
```yaml
# Require approvals for production
deploy:production:
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual
      allow_failure: false
  environment:
    name: production
    action: start
    deployment_tier: production
```

#### 2. Audit Trail
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::cloudtrail-logs-bucket",
      "Condition": {
        "StringEquals": {
          "AWS:SourceAccount": "123456789012"
        }
      }
    }
  ]
}
```

#### 3. Cost Management
```bash
# Budget alerts
aws budgets create-budget \
  --account-id 123456789012 \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json

# Cost allocation tags
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --group-by Type=TAG,Key=Project
```

### Future Enhancements

#### 1. Multi-Region Deployment
```hcl
# Provider configuration
provider "aws" {
  alias  = "primary"
  region = "us-west-2"
}

provider "aws" {
  alias  = "secondary"
  region = "us-east-1"
}

# Multi-region resources
module "k3s_primary" {
  source = "./modules/k3s"
  providers = {
    aws = aws.primary
  }
}

module "k3s_secondary" {
  source = "./modules/k3s"
  providers = {
    aws = aws.secondary
  }
}
```

#### 2. Advanced Security
```yaml
# Security scanning in pipeline
security:scan:
  stage: validate
  image: aquasec/trivy:latest
  script:
    - trivy fs --exit-code 1 --severity HIGH,CRITICAL .
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE_NAME
```

#### 3. GitOps Integration
```yaml
# ArgoCD deployment
deploy:gitops:
  stage: deploy
  script:
    - |
      # Update GitOps repo with new image tags
      git clone https://gitlab.com/username/k3s-gitops.git
      cd k3s-gitops
      yq eval ".spec.template.spec.containers[0].image = \"$NEW_IMAGE\"" -i k3s-app/deployment.yaml
      git add .
      git commit -m "Update image to $NEW_IMAGE"
      git push origin main
```

---

## Conclusion

This comprehensive guide provides a complete solution for implementing secure CI/CD pipelines for Kubernetes clusters using OIDC federation. The approach eliminates the security risks associated with storing long-lived AWS credentials while providing fine-grained access control and comprehensive audit capabilities.

### Key Benefits Achieved:

1. **Enhanced Security**: No stored credentials, temporary access tokens, branch-based permissions
2. **Operational Excellence**: Automated setup, comprehensive monitoring, disaster recovery procedures
3. **Compliance Ready**: Audit trails, change management, access controls
4. **Cost Effective**: Right-sized resources, automated cleanup, cost monitoring
5. **Developer Friendly**: Simple setup script, clear documentation, troubleshooting guides

### Next Steps:

1. Run the automated setup script
2. Test with a feature branch first
3. Deploy to production via main branch
4. Implement monitoring and alerting
5. Train team on new processes
6. Document any environment-specific customizations

This implementation serves as a production-ready foundation that can be extended and customized based on specific organizational requirements while maintaining security best practices.