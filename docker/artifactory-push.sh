#!/bin/bash
# Script to build and push container images to Artifactory

# Variables
ARTIFACTORY_URL=${1:-"https://artifactory.example.com"}  # Artifactory URL
ARTIFACTORY_REPO=${2:-"docker-local"}                   # Docker repository name in Artifactory
ARTIFACTORY_USER=${3:-"$ARTIFACTORY_USERNAME"}          # Artifactory username (from env or parameter)
ARTIFACTORY_PASS=${4:-"$ARTIFACTORY_PASSWORD"}          # Artifactory password (from env or parameter)
IMAGE_PREFIX=${5:-"k3s-app"}                           # Image prefix
TAG=${6:-"latest"}                                      # Default tag if not specified

# Check if required parameters are provided
if [[ -z "$ARTIFACTORY_URL" || -z "$ARTIFACTORY_REPO" ]]; then
    echo "Error: Artifactory URL and repository name must be specified."
    echo "Usage: $0 <artifactory-url> <repository-name> [username] [password] [image-prefix] [tag]"
    exit 1
fi

# Prompt for credentials if not provided
if [[ -z "$ARTIFACTORY_USER" ]]; then
    echo -n "Artifactory Username: "
    read ARTIFACTORY_USER
fi

if [[ -z "$ARTIFACTORY_PASS" ]]; then
    echo -n "Artifactory Password: "
    read -s ARTIFACTORY_PASS
    echo
fi

# Construct image repository paths
FRONTEND_REPO="${ARTIFACTORY_URL}/${ARTIFACTORY_REPO}/${IMAGE_PREFIX}/frontend"
BACKEND_REPO="${ARTIFACTORY_URL}/${ARTIFACTORY_REPO}/${IMAGE_PREFIX}/backend"
DATABASE_REPO="${ARTIFACTORY_URL}/${ARTIFACTORY_REPO}/${IMAGE_PREFIX}/database"

# Login to Artifactory Docker registry
echo "Logging in to Artifactory Docker registry..."
echo ${ARTIFACTORY_PASS} | docker login ${ARTIFACTORY_URL} --username ${ARTIFACTORY_USER} --password-stdin

if [ $? -ne 0 ]; then
    echo "Error: Failed to login to Artifactory."
    exit 1
fi

# Set environment variables for docker-compose
export REGISTRY_URL="${ARTIFACTORY_URL}/${ARTIFACTORY_REPO}"
export TAG=$TAG

echo "Building container images..."
docker-compose build

echo "Pushing images to Artifactory..."
docker tag ${IMAGE_PREFIX}/frontend:${TAG} ${FRONTEND_REPO}:${TAG}
docker tag ${IMAGE_PREFIX}/backend:${TAG} ${BACKEND_REPO}:${TAG}
docker tag ${IMAGE_PREFIX}/database:${TAG} ${DATABASE_REPO}:${TAG}

docker push ${FRONTEND_REPO}:${TAG}
docker push ${BACKEND_REPO}:${TAG}
docker push ${DATABASE_REPO}:${TAG}

echo "Images available at:"
echo "- ${FRONTEND_REPO}:${TAG}"
echo "- ${BACKEND_REPO}:${TAG}"
echo "- ${DATABASE_REPO}:${TAG}"

echo "To update the Helm chart with these Artifactory images, modify values.yaml with:"
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