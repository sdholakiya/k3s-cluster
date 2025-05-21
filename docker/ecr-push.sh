#!/bin/bash
# Script to build and push container images to AWS ECR

# Variables
AWS_REGION=${1:-"us-west-2"}       # Default region if not specified
AWS_ACCOUNT_ID=${2:-$(aws sts get-caller-identity --query "Account" --output text)}
ECR_REPO_PREFIX=${3:-"k3s-app"}    # Repository prefix
TAG=${4:-"latest"}                 # Default tag if not specified

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# ECR repository URLs
FRONTEND_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend"
BACKEND_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend"
DATABASE_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/database"

echo "Creating ECR repositories if they don't exist..."

# Create repositories if they don't exist
aws ecr describe-repositories --repository-names "${ECR_REPO_PREFIX}/frontend" --region ${AWS_REGION} || \
  aws ecr create-repository --repository-name "${ECR_REPO_PREFIX}/frontend" --region ${AWS_REGION}

aws ecr describe-repositories --repository-names "${ECR_REPO_PREFIX}/backend" --region ${AWS_REGION} || \
  aws ecr create-repository --repository-name "${ECR_REPO_PREFIX}/backend" --region ${AWS_REGION}

aws ecr describe-repositories --repository-names "${ECR_REPO_PREFIX}/database" --region ${AWS_REGION} || \
  aws ecr create-repository --repository-name "${ECR_REPO_PREFIX}/database" --region ${AWS_REGION}

# Authenticate Docker to ECR
echo "Authenticating Docker client to ECR registry..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Set environment variables for docker-compose
export REGISTRY_URL=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
export TAG=$TAG

echo "Building container images..."
docker-compose build

echo "Pushing images to ECR..."
docker tag ${ECR_REPO_PREFIX}/frontend:${TAG} ${FRONTEND_REPO}:${TAG}
docker tag ${ECR_REPO_PREFIX}/backend:${TAG} ${BACKEND_REPO}:${TAG}
docker tag ${ECR_REPO_PREFIX}/database:${TAG} ${DATABASE_REPO}:${TAG}

docker push ${FRONTEND_REPO}:${TAG}
docker push ${BACKEND_REPO}:${TAG}
docker push ${DATABASE_REPO}:${TAG}

echo "Images available at:"
echo "- ${FRONTEND_REPO}:${TAG}"
echo "- ${BACKEND_REPO}:${TAG}"
echo "- ${DATABASE_REPO}:${TAG}"

echo "To update the Helm chart with these ECR images, modify values.yaml with:"
cat << EOF

containers:
  frontend:
    image:
      repository: ${FRONTEND_REPO}
      tag: ${TAG}
  backend:
    image:
      repository: ${BACKEND_REPO}
      tag: ${TAG}
  database:
    image:
      repository: ${DATABASE_REPO}
      tag: ${TAG}
EOF

echo "Done!"