#!/bin/bash
# Script to build and push container images to a container registry

# Variables
REGISTRY_URL=${1:-"localhost:5000"}  # Default to local registry if not specified
TAG=${2:-"latest"}                   # Default tag if not specified

# Set registry and tag in env vars for docker-compose
export REGISTRY_URL=$REGISTRY_URL
export TAG=$TAG

echo "Building container images..."
docker-compose build

echo "Pushing images to registry: $REGISTRY_URL"
docker-compose push

echo "Images available at:"
echo "- $REGISTRY_URL/k3s-app/frontend:$TAG"
echo "- $REGISTRY_URL/k3s-app/backend:$TAG"
echo "- $REGISTRY_URL/k3s-app/database:$TAG"

echo "To update the Helm chart with these images, modify values.yaml with:"
cat << EOF

containers:
  frontend:
    image:
      repository: $REGISTRY_URL/k3s-app/frontend
      tag: $TAG
  backend:
    image:
      repository: $REGISTRY_URL/k3s-app/backend
      tag: $TAG
  database:
    image:
      repository: $REGISTRY_URL/k3s-app/database
      tag: $TAG
EOF

echo "Done!"