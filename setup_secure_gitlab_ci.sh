#!/bin/bash
# Secure GitLab CI/CD Setup Script for K3s Cluster
# This script sets up GitLab CI/CD using OIDC federation with AWS IAM roles (no stored credentials)

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage information
print_usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Set up secure GitLab CI/CD for K3s cluster using OIDC federation"
    echo
    echo "Options:"
    echo "  --gitlab-project PROJECT  GitLab project path (e.g., username/project)"
    echo "  --aws-region REGION       AWS region (default: us-west-2)"
    echo "  --help                    Display this help text and exit"
    echo
    echo "Prerequisites:"
    echo "  1. GitLab CLI (glab) installed and authenticated"
    echo "  2. AWS CLI configured with admin permissions"
    echo "  3. Terraform installed"
    echo
    echo "This script will:"
    echo "  1. Create IAM roles for GitLab OIDC federation"
    echo "  2. Set up GitLab CI/CD variables"
    echo "  3. Configure secure pipeline without stored credentials"
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # Check GitLab CLI
    if ! command -v glab &> /dev/null; then
        echo -e "${RED}Error: GitLab CLI (glab) not found.${NC}"
        echo "Install it: brew install glab (macOS) or visit: https://gitlab.com/gitlab-org/cli#installation"
        exit 1
    fi
    
    # Check GitLab authentication
    if ! glab auth status &> /dev/null; then
        echo -e "${RED}Error: Not authenticated with GitLab.${NC}"
        echo "Run: glab auth login"
        exit 1
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI not found.${NC}"
        echo "Install it: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}Error: AWS CLI not configured or no valid credentials.${NC}"
        echo "Run: aws configure or aws sso login"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Error: Terraform not found.${NC}"
        echo "Install it: https://developer.hashicorp.com/terraform/downloads"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All prerequisites met${NC}"
}

# Parse command line arguments
GITLAB_PROJECT=""
AWS_REGION="us-west-2"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --gitlab-project) GITLAB_PROJECT="$2"; shift ;;
        --aws-region) AWS_REGION="$2"; shift ;;
        --help) print_usage; exit 0 ;;
        *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
    esac
    shift
done

check_prerequisites

# Get GitLab project if not provided
if [ -z "$GITLAB_PROJECT" ]; then
    echo -n "Enter your GitLab project path (e.g., username/project): "
    read GITLAB_PROJECT
fi

if [ -z "$GITLAB_PROJECT" ]; then
    echo -e "${RED}Error: GitLab project path is required.${NC}"
    exit 1
fi

# Get AWS account information
echo -e "${BLUE}Getting AWS account information...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
AWS_CURRENT_REGION=$(aws configure get region || echo "$AWS_REGION")

echo -e "${YELLOW}AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${YELLOW}AWS Region: ${AWS_CURRENT_REGION}${NC}"
echo -e "${YELLOW}GitLab Project: ${GITLAB_PROJECT}${NC}"

# Confirm setup
echo -e "${YELLOW}This will create IAM roles and set up OIDC federation. Continue? (y/n)${NC}"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Step 1: Deploy IAM roles using Terraform
echo -e "${BLUE}Step 1: Creating IAM roles for GitLab OIDC...${NC}"

cd terraform

# Set Terraform variables
export TF_VAR_gitlab_project_path="$GITLAB_PROJECT"
export TF_VAR_gitlab_url="https://gitlab.com"

# Initialize and apply Terraform for IAM roles only
echo -e "${YELLOW}Initializing Terraform for IAM roles...${NC}"
terraform init -backend=false

echo -e "${YELLOW}Planning IAM role creation...${NC}"
terraform plan -target=aws_iam_openid_connect_provider.gitlab \
               -target=aws_iam_policy.cicd_policy \
               -target=aws_iam_policy.cicd_feature_policy \
               -target=aws_iam_role.gitlab_cicd_main \
               -target=aws_iam_role.gitlab_cicd_feature \
               -target=aws_iam_role_policy_attachment.gitlab_cicd_main_policy \
               -target=aws_iam_role_policy_attachment.gitlab_cicd_feature_policy \
               -out=iam-plan

echo -e "${YELLOW}Applying IAM role configuration...${NC}"
terraform apply -auto-approve iam-plan

# Get role ARNs
MAIN_ROLE_ARN=$(terraform output -raw gitlab_cicd_main_role_arn)
FEATURE_ROLE_ARN=$(terraform output -raw gitlab_cicd_feature_role_arn)
OIDC_PROVIDER_ARN=$(terraform output -raw gitlab_oidc_provider_arn)

echo -e "${GREEN}✓ IAM roles created successfully${NC}"
echo -e "${YELLOW}Main branch role ARN: ${MAIN_ROLE_ARN}${NC}"
echo -e "${YELLOW}Feature branch role ARN: ${FEATURE_ROLE_ARN}${NC}"

cd ..

# Step 2: Set up GitLab CI/CD variables
echo -e "${BLUE}Step 2: Setting up GitLab CI/CD variables...${NC}"

# Set AWS configuration variables
glab variable set AWS_DEFAULT_REGION -p "$GITLAB_PROJECT" -v "$AWS_CURRENT_REGION"
glab variable set AWS_ACCOUNT_ID -p "$GITLAB_PROJECT" -v "$AWS_ACCOUNT_ID"

# Set role ARNs
glab variable set GITLAB_CICD_MAIN_ROLE_ARN -p "$GITLAB_PROJECT" -v "$MAIN_ROLE_ARN"
glab variable set GITLAB_CICD_FEATURE_ROLE_ARN -p "$GITLAB_PROJECT" -v "$FEATURE_ROLE_ARN"

# Ask for other project-specific variables
echo -e "${YELLOW}Enter S3 bucket name for Terraform state storage:${NC}"
read TF_STATE_BUCKET
glab variable set TF_VAR_terraform_state_bucket -p "$GITLAB_PROJECT" -v "$TF_STATE_BUCKET"

echo -e "${YELLOW}Enter VPC ID:${NC}"
read VPC_ID
glab variable set TF_VAR_vpc_id -p "$GITLAB_PROJECT" -v "$VPC_ID"

echo -e "${YELLOW}Enter Subnet ID (private subnet with SSM endpoints):${NC}"
read SUBNET_ID
glab variable set TF_VAR_subnet_id -p "$GITLAB_PROJECT" -v "$SUBNET_ID"

echo -e "${YELLOW}Enter Security Group ID:${NC}"
read SG_ID
glab variable set TF_VAR_security_group_id -p "$GITLAB_PROJECT" -v "$SG_ID"

# Container registry choice
echo -e "${YELLOW}Which container registry would you like to use?${NC}"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Skip container registry setup"
read -p "Enter your choice (1-2): " REGISTRY_CHOICE

case $REGISTRY_CHOICE in
    1)
        glab variable set USE_ECR -p "$GITLAB_PROJECT" -v "true"
        echo -e "${YELLOW}Enter ECR repository prefix (default: k3s-app):${NC}"
        read ECR_PREFIX
        ECR_PREFIX=${ECR_PREFIX:-"k3s-app"}
        glab variable set ECR_REPO_PREFIX -p "$GITLAB_PROJECT" -v "$ECR_PREFIX"
        ;;
    2)
        echo "Skipping container registry setup."
        ;;
    *)
        echo "Invalid choice. Skipping container registry setup."
        ;;
esac

echo -e "${GREEN}✓ GitLab CI/CD variables set successfully${NC}"

# Step 3: Copy secure pipeline configuration
echo -e "${BLUE}Step 3: Setting up secure pipeline configuration...${NC}"

if [ -f ".gitlab-ci-oidc.yml" ]; then
    echo -e "${YELLOW}Would you like to replace your current .gitlab-ci.yml with the secure OIDC version? (y/n)${NC}"
    read -r REPLACE_CI
    if [[ "$REPLACE_CI" =~ ^[Yy] ]]; then
        cp .gitlab-ci-oidc.yml .gitlab-ci.yml
        echo -e "${GREEN}✓ Secure pipeline configuration activated${NC}"
    else
        echo -e "${YELLOW}Secure pipeline saved as .gitlab-ci-oidc.yml${NC}"
        echo -e "${YELLOW}To use it, rename it to .gitlab-ci.yml${NC}"
    fi
else
    echo -e "${RED}Error: .gitlab-ci-oidc.yml not found${NC}"
fi

# Step 4: Display setup summary
echo -e "${GREEN}🎉 Secure GitLab CI/CD setup completed!${NC}"
echo
echo -e "${BLUE}Summary:${NC}"
echo -e "${YELLOW}✓ OIDC Identity Provider created${NC}"
echo -e "${YELLOW}✓ IAM roles with minimal permissions created${NC}"
echo -e "${YELLOW}✓ GitLab CI/CD variables configured${NC}"
echo -e "${YELLOW}✓ Secure pipeline configuration ready${NC}"
echo
echo -e "${BLUE}Security Features:${NC}"
echo -e "${YELLOW}• No stored AWS credentials in GitLab${NC}"
echo -e "${YELLOW}• Role-based access with branch-specific permissions${NC}"
echo -e "${YELLOW}• Main branch: Full deployment permissions${NC}"
echo -e "${YELLOW}• Feature branches: Read-only + planning permissions${NC}"
echo -e "${YELLOW}• Automatic credential rotation via OIDC${NC}"
echo
echo -e "${BLUE}Next Steps:${NC}"
echo -e "${YELLOW}1. Commit and push your changes to trigger the pipeline${NC}"
echo -e "${YELLOW}2. Review the pipeline execution in GitLab CI/CD${NC}"
echo -e "${YELLOW}3. Main branch deployments require manual approval${NC}"
echo
echo -e "${BLUE}Important Notes:${NC}"
echo -e "${YELLOW}• The IAM roles are specific to your GitLab project: ${GITLAB_PROJECT}${NC}"
echo -e "${YELLOW}• Only branches from this project can assume the roles${NC}"
echo -e "${YELLOW}• Feature branches have limited permissions for security${NC}"
echo -e "${YELLOW}• All AWS operations are logged in CloudTrail${NC}"

# Optional: Test the setup
echo -e "${YELLOW}Would you like to test the OIDC setup now? (y/n)${NC}"
read -r TEST_SETUP
if [[ "$TEST_SETUP" =~ ^[Yy] ]]; then
    echo -e "${BLUE}Testing OIDC setup...${NC}"
    
    # This would require a GitLab CI job token, so we'll just validate the roles exist
    aws iam get-role --role-name gitlab-k3s-cicd-main &> /dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Main branch role accessible${NC}"
    else
        echo -e "${RED}✗ Main branch role not found${NC}"
    fi
    
    aws iam get-role --role-name gitlab-k3s-cicd-feature &> /dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Feature branch role accessible${NC}"
    else
        echo -e "${RED}✗ Feature branch role not found${NC}"
    fi
fi

echo -e "${GREEN}Setup complete! Your GitLab CI/CD is now secure and ready to use.${NC}"