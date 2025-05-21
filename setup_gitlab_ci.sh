#!/bin/bash
# This script helps set up GitLab CI/CD variables for your project including container registry access
# You must have the GitLab CLI (glab) installed: https://gitlab.com/gitlab-org/cli

if ! command -v glab &> /dev/null; then
    echo "GitLab CLI (glab) not found. Please install it first:"
    echo "  brew install glab   # macOS with Homebrew"
    echo "  or visit: https://gitlab.com/gitlab-org/cli#installation"
    exit 1
fi

# Check if user is authenticated with GitLab
if ! glab auth status &> /dev/null; then
    echo "You need to authenticate with GitLab first:"
    echo "  glab auth login"
    exit 1
fi

# Get project path
echo "Enter your GitLab project path (e.g., username/project):"
read GITLAB_PROJECT_PATH

if [ -z "$GITLAB_PROJECT_PATH" ]; then
    echo "Project path cannot be empty."
    exit 1
fi

# Get AWS credentials
echo "Enter your AWS Access Key ID:"
read AWS_ACCESS_KEY_ID

echo "Enter your AWS Secret Access Key:"
read -s AWS_SECRET_ACCESS_KEY
echo ""

echo "Enter your AWS Default Region (e.g., us-west-2):"
read AWS_DEFAULT_REGION

# Ask about container registry choice
echo "Which container registry would you like to use?"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Artifactory"
echo "3. None/Other"
read -p "Enter your choice (1-3): " REGISTRY_CHOICE

# Create variables in GitLab
echo "Setting up GitLab CI/CD variables..."

# Set AWS variables
glab variable set AWS_ACCESS_KEY_ID -p "$GITLAB_PROJECT_PATH" -v "$AWS_ACCESS_KEY_ID" --masked
if [ $? -ne 0 ]; then
    echo "Failed to set AWS_ACCESS_KEY_ID variable"
    exit 1
fi

glab variable set AWS_SECRET_ACCESS_KEY -p "$GITLAB_PROJECT_PATH" -v "$AWS_SECRET_ACCESS_KEY" --masked
if [ $? -ne 0 ]; then
    echo "Failed to set AWS_SECRET_ACCESS_KEY variable"
    exit 1
fi

glab variable set AWS_DEFAULT_REGION -p "$GITLAB_PROJECT_PATH" -v "$AWS_DEFAULT_REGION"
if [ $? -ne 0 ]; then
    echo "Failed to set AWS_DEFAULT_REGION variable"
    exit 1
fi

# Set container registry variables based on choice
case $REGISTRY_CHOICE in
    1)
        # AWS ECR
        echo "Setting up AWS ECR variables..."
        glab variable set USE_ECR -p "$GITLAB_PROJECT_PATH" -v "true"
        
        echo "Enter ECR repository prefix (default: k3s-app):"
        read ECR_PREFIX
        ECR_PREFIX=${ECR_PREFIX:-"k3s-app"}
        
        glab variable set ECR_REPO_PREFIX -p "$GITLAB_PROJECT_PATH" -v "$ECR_PREFIX"
        ;;
    2)
        # Artifactory
        echo "Setting up Artifactory variables..."
        glab variable set USE_ARTIFACTORY -p "$GITLAB_PROJECT_PATH" -v "true"
        
        echo "Enter Artifactory URL (e.g., https://artifactory.example.com):"
        read ARTIFACTORY_URL
        
        echo "Enter Artifactory Docker repository name (e.g., docker-local):"
        read ARTIFACTORY_REPO
        
        echo "Enter Artifactory username:"
        read ARTIFACTORY_USERNAME
        
        echo "Enter Artifactory password/API key:"
        read -s ARTIFACTORY_PASSWORD
        echo ""
        
        glab variable set ARTIFACTORY_URL -p "$GITLAB_PROJECT_PATH" -v "$ARTIFACTORY_URL"
        glab variable set ARTIFACTORY_REPO -p "$GITLAB_PROJECT_PATH" -v "$ARTIFACTORY_REPO"
        glab variable set ARTIFACTORY_USERNAME -p "$GITLAB_PROJECT_PATH" -v "$ARTIFACTORY_USERNAME"
        glab variable set ARTIFACTORY_PASSWORD -p "$GITLAB_PROJECT_PATH" -v "$ARTIFACTORY_PASSWORD" --masked
        ;;
    3)
        # None/Other
        echo "Skipping container registry setup."
        ;;
    *)
        echo "Invalid choice. Skipping container registry setup."
        ;;
esac

# Ask for Terraform variables
echo "Enter S3 bucket name for Terraform state storage:"
read TF_STATE_BUCKET

echo "Enter VPC ID:"
read VPC_ID

echo "Enter Subnet ID (must be a private subnet with SSM endpoints):"
read SUBNET_ID

echo "Enter Security Group ID:"
read SG_ID

# Set Terraform variables
glab variable set TF_VAR_terraform_state_bucket -p "$GITLAB_PROJECT_PATH" -v "$TF_STATE_BUCKET"
glab variable set TF_VAR_vpc_id -p "$GITLAB_PROJECT_PATH" -v "$VPC_ID"
glab variable set TF_VAR_subnet_id -p "$GITLAB_PROJECT_PATH" -v "$SUBNET_ID"
glab variable set TF_VAR_security_group_id -p "$GITLAB_PROJECT_PATH" -v "$SG_ID"

echo "Successfully set up GitLab CI/CD variables for your project."
echo "Your pipeline is now ready to run with AWS credentials and container registry access."