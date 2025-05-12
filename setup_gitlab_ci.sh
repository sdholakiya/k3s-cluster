#!/bin/bash
# This script helps set up GitLab CI/CD variables for your project
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

# Create variables in GitLab
echo "Setting up GitLab CI/CD variables..."

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

echo "Successfully set up GitLab CI/CD variables for your project."
echo "Your pipeline is now ready to run with AWS credentials."