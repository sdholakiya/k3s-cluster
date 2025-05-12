#!/bin/bash
# Script to extract AWS credentials from AWS SSO login and role

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if required tools are installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed.${NC}"
    echo "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check AWS CLI version (needs to be v2)
AWS_VERSION=$(aws --version | grep -o "aws-cli/[0-9]*" | cut -d '/' -f 2)
if [ "$AWS_VERSION" -lt "2" ]; then
    echo -e "${RED}Error: AWS CLI version 2 or higher is required.${NC}"
    echo "Current version: $(aws --version)"
    echo "Please upgrade: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Function to check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: jq is not installed. Output will not be formatted nicely.${NC}"
        return 1
    fi
    return 0
}

# Print usage information
print_usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Extract AWS credentials from AWS SSO login and role"
    echo
    echo "Options:"
    echo "  --sso-url URL         AWS SSO URL (e.g., https://my-sso-portal.awsapps.com/start)"
    echo "  --account-id ID       AWS Account ID (12 digits)"
    echo "  --role-name ROLE      AWS SSO Role Name (e.g., AdministratorAccess)"
    echo "  --profile NAME        Profile name to use (default: sso-temp-profile)"
    echo "  --aws-creds-name NAME Name for AWS credentials profile (default: same as --profile)"
    echo "  --help                Display this help text and exit"
    echo
    echo "If options are not provided, the script will prompt for them interactively."
}

# Parse command line arguments
SSO_URL=""
ACCOUNT_ID=""
ROLE_NAME=""
PROFILE_NAME=""
AWS_CREDS_NAME=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --sso-url) SSO_URL="$2"; shift ;;
        --account-id) ACCOUNT_ID="$2"; shift ;;
        --role-name) ROLE_NAME="$2"; shift ;;
        --profile) PROFILE_NAME="$2"; shift ;;
        --aws-creds-name) AWS_CREDS_NAME="$2"; shift ;;
        --help) print_usage; exit 0 ;;
        *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# Prompt for missing parameters
if [ -z "$SSO_URL" ]; then
    echo -n "Enter AWS SSO URL (e.g., https://my-sso-portal.awsapps.com/start): "
    read SSO_URL
fi

if [ -z "$ACCOUNT_ID" ]; then
    echo -n "Enter AWS Account ID: "
    read ACCOUNT_ID
fi

if [ -z "$ROLE_NAME" ]; then
    echo -n "Enter AWS SSO Role Name (e.g., AdministratorAccess): "
    read ROLE_NAME
fi

if [ -z "$PROFILE_NAME" ]; then
    PROFILE_NAME="sso-temp-profile"
    echo -e "Using default profile name: ${YELLOW}$PROFILE_NAME${NC}"
fi

if [ -z "$AWS_CREDS_NAME" ]; then
    AWS_CREDS_NAME="$PROFILE_NAME"
    echo -e "Using AWS credentials profile name: ${YELLOW}$AWS_CREDS_NAME${NC}"
fi

# Validate input
if [[ ! "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    echo -e "${RED}Error: Invalid AWS Account ID format. Should be 12 digits.${NC}"
    exit 1
fi

echo -e "${YELLOW}Initiating AWS SSO login process...${NC}"

# Configure SSO profile
aws configure set sso_start_url "$SSO_URL" --profile "$PROFILE_NAME"
aws configure set sso_account_id "$ACCOUNT_ID" --profile "$PROFILE_NAME"
aws configure set sso_role_name "$ROLE_NAME" --profile "$PROFILE_NAME"
aws configure set sso_region "$(aws configure get region || echo 'us-east-1')" --profile "$PROFILE_NAME"
aws configure set region "$(aws configure get region || echo 'us-east-1')" --profile "$PROFILE_NAME"

# Login to SSO
echo -e "${YELLOW}A browser window will open. Please complete the SSO authentication.${NC}"
if ! aws sso login --profile "$PROFILE_NAME"; then
    echo -e "${RED}Error: SSO login failed.${NC}"
    exit 1
fi

echo -e "${GREEN}SSO login successful!${NC}"

# Get temporary credentials
echo -e "${YELLOW}Fetching temporary AWS credentials...${NC}"
CREDENTIALS=$(aws sts get-caller-identity --query "Account" --profile "$PROFILE_NAME" > /dev/null 2>&1 && \
              aws configure export-credentials --format env --profile "$PROFILE_NAME")

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to get credentials.${NC}"
    exit 1
fi

# Extract credentials
AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | grep AWS_ACCESS_KEY_ID | cut -d'=' -f2- | tr -d '"')
AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | grep AWS_SECRET_ACCESS_KEY | cut -d'=' -f2- | tr -d '"')
AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | grep AWS_SESSION_TOKEN | cut -d'=' -f2- | tr -d '"')

# Extract region
AWS_REGION=$(aws configure get region --profile "$PROFILE_NAME")
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi

# Display credentials
echo -e "${GREEN}Successfully retrieved credentials:${NC}"
echo -e "${YELLOW}AWS_ACCESS_KEY_ID=${NC}${AWS_ACCESS_KEY_ID}"
echo -e "${YELLOW}AWS_SECRET_ACCESS_KEY=${NC}${AWS_SECRET_ACCESS_KEY:0:5}...${AWS_SECRET_ACCESS_KEY:(-5)}"
echo -e "${YELLOW}AWS_SESSION_TOKEN=${NC}${AWS_SESSION_TOKEN:0:5}...${AWS_SESSION_TOKEN:(-5)}"
echo -e "${YELLOW}AWS_DEFAULT_REGION=${NC}${AWS_REGION}"

# Create a credentials file for GitLab CI
echo -e "${YELLOW}Creating gitlab-aws-credentials.env file...${NC}"
cat > "$(dirname "$0")/gitlab-aws-credentials.env" << EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}
AWS_DEFAULT_REGION=${AWS_REGION}
EOF

echo -e "${GREEN}Credentials saved to: $(dirname "$0")/gitlab-aws-credentials.env${NC}"

# Option to update AWS credentials file
echo -e "${YELLOW}Would you like to update your AWS credentials file with these temporary credentials? (y/n)${NC}"
read UPDATE_AWS_CREDS

if [[ "$UPDATE_AWS_CREDS" =~ ^[Yy] ]]; then
    # Ensure the ~/.aws directory exists
    mkdir -p ~/.aws

    # Check if credentials file already exists
    if [ -f ~/.aws/credentials ]; then
        # Check if profile already exists
        if grep -q "\[$AWS_CREDS_NAME\]" ~/.aws/credentials; then
            # Update existing profile
            echo -e "${YELLOW}Updating existing profile '$AWS_CREDS_NAME' in AWS credentials file...${NC}"

            # Create a temporary file
            TEMP_FILE=$(mktemp)

            # Write to temporary file with updated credentials
            awk -v name="$AWS_CREDS_NAME" -v key="$AWS_ACCESS_KEY_ID" -v secret="$AWS_SECRET_ACCESS_KEY" -v token="$AWS_SESSION_TOKEN" -v region="$AWS_REGION" '
            BEGIN { in_profile=0; profile_found=0; }
            /^\[/ {
                if (in_profile && profile_found) {
                    in_profile=0;
                }
                else if ($0 == "["name"]") {
                    in_profile=1;
                    profile_found=1;
                }
            }
            {
                if (profile_found && in_profile) {
                    if ($0 ~ /^\[/) {
                        print $0;
                    } else if (!printed_creds) {
                        print "aws_access_key_id = " key;
                        print "aws_secret_access_key = " secret;
                        print "aws_session_token = " token;
                        print "region = " region;
                        printed_creds=1;
                    }
                } else {
                    print $0;
                }
            }
            END {
                if (profile_found && !printed_creds) {
                    print "aws_access_key_id = " key;
                    print "aws_secret_access_key = " secret;
                    print "aws_session_token = " token;
                    print "region = " region;
                }
            }' ~/.aws/credentials > "$TEMP_FILE"

            # Replace original file with temporary file
            mv "$TEMP_FILE" ~/.aws/credentials
            chmod 600 ~/.aws/credentials
        else
            # Append new profile
            echo -e "${YELLOW}Adding new profile '$AWS_CREDS_NAME' to AWS credentials file...${NC}"
            cat >> ~/.aws/credentials << EOF

[$AWS_CREDS_NAME]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
aws_session_token = $AWS_SESSION_TOKEN
region = $AWS_REGION
EOF
        fi
    else
        # Create new credentials file
        echo -e "${YELLOW}Creating new AWS credentials file with profile '$AWS_CREDS_NAME'...${NC}"
        cat > ~/.aws/credentials << EOF
[$AWS_CREDS_NAME]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
aws_session_token = $AWS_SESSION_TOKEN
region = $AWS_REGION
EOF
        chmod 600 ~/.aws/credentials
    fi

    echo -e "${GREEN}AWS credentials updated successfully.${NC}"
    echo -e "${YELLOW}To use these credentials with AWS CLI, run:${NC}"
    echo -e "aws s3 ls --profile $AWS_CREDS_NAME"
fi

# Option to automatically set up GitLab CI variables
echo -e "${YELLOW}Would you like to set these credentials as GitLab CI variables? (y/n)${NC}"
read SETUP_GITLAB

if [[ "$SETUP_GITLAB" =~ ^[Yy] ]]; then
    # Check if glab is installed
    if ! command -v glab &> /dev/null; then
        echo -e "${RED}GitLab CLI (glab) not found. Please install it first:${NC}"
        echo "  brew install glab   # macOS with Homebrew"
        echo "  or visit: https://gitlab.com/gitlab-org/cli#installation"
    else
        # Check if user is authenticated with GitLab
        if ! glab auth status &> /dev/null; then
            echo -e "${RED}You need to authenticate with GitLab first:${NC}"
            echo "  glab auth login"
        else
            echo -n "Enter your GitLab project path (e.g., username/project): "
            read GITLAB_PROJECT_PATH

            if [ -z "$GITLAB_PROJECT_PATH" ]; then
                echo -e "${RED}Project path cannot be empty.${NC}"
            else
                echo -e "${YELLOW}Setting up GitLab CI/CD variables...${NC}"

                glab variable set AWS_ACCESS_KEY_ID -p "$GITLAB_PROJECT_PATH" -v "$AWS_ACCESS_KEY_ID" --masked
                glab variable set AWS_SECRET_ACCESS_KEY -p "$GITLAB_PROJECT_PATH" -v "$AWS_SECRET_ACCESS_KEY" --masked
                glab variable set AWS_SESSION_TOKEN -p "$GITLAB_PROJECT_PATH" -v "$AWS_SESSION_TOKEN" --masked
                glab variable set AWS_DEFAULT_REGION -p "$GITLAB_PROJECT_PATH" -v "$AWS_REGION"

                echo -e "${GREEN}Successfully set up GitLab CI/CD variables for your project.${NC}"
                echo -e "${YELLOW}Note: These credentials will expire. You'll need to run this script again when they do.${NC}"
            fi
        fi
    fi
fi

# Add AWS CLI usage examples
echo -e "\n${GREEN}Usage examples with your new AWS credentials:${NC}"
echo -e "${YELLOW}1. List S3 buckets:${NC}"
echo -e "   aws s3 ls --profile $AWS_CREDS_NAME"
echo -e "${YELLOW}2. Describe EC2 instances:${NC}"
echo -e "   aws ec2 describe-instances --profile $AWS_CREDS_NAME"
echo -e "${YELLOW}3. Run Terraform:${NC}"
echo -e "   AWS_PROFILE=$AWS_CREDS_NAME terraform plan"

echo -e "\n${YELLOW}Note: These credentials are temporary and will expire (typically after 1-12 hours).${NC}"
echo -e "${GREEN}You can use these credentials with the K3s-Cluster project.${NC}"