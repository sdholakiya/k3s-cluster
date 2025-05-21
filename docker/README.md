# Custom Container Images for K3s Cluster

This directory contains Dockerfiles and configuration to build custom container images for deployment in your K3s cluster. These images can replace the default images used in the Helm chart.

## Directory Structure

```
docker/
├── docker-compose.yml           # Defines all three containers
├── build-and-push.sh            # Script to build and push images
├── frontend/                    # Frontend container (Nginx)
│   ├── Dockerfile
│   └── index.html
├── backend/                     # Backend container (Python Flask)
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
└── database/                    # Database container (PostgreSQL)
    ├── Dockerfile
    └── init.sql
```

## Customizing Containers

You can modify each container by editing its Dockerfile and associated files:

### Frontend Container

- Edit `frontend/Dockerfile` to change the base image or build steps
- Modify `frontend/index.html` to change the web interface
- Add additional static files as needed

### Backend Container

- Edit `backend/Dockerfile` to change the base image or build steps
- Modify `backend/app.py` to implement your API logic
- Update `backend/requirements.txt` with required Python packages

### Database Container

- Edit `database/Dockerfile` to change the base image or build configuration
- Modify `database/init.sql` to change the database initialization script

## Building and Pushing Images

The project includes scripts for building and pushing container images to different container registries:

### For Generic Registries

Use the general `build-and-push.sh` script:

1. Make the script executable:
   ```bash
   chmod +x build-and-push.sh
   ```

2. Run the script with your container registry URL and optional tag:
   ```bash
   ./build-and-push.sh my-registry.example.com v1.0.0
   ```

   If you're testing locally, you can start a local registry first:
   ```bash
   docker run -d -p 5000:5000 --name registry registry:2
   ```
   Then build and push to it:
   ```bash
   ./build-and-push.sh localhost:5000 latest
   ```

3. The script will output the values needed to update your Helm chart.

### For AWS ECR

Use the ECR-specific script for pushing to Amazon Elastic Container Registry:

1. Make the script executable:
   ```bash
   chmod +x ecr-push.sh
   ```

2. Run the script with AWS region, account ID (optional), repository prefix, and tag:
   ```bash
   ./ecr-push.sh us-west-2 123456789012 k3s-app v1.0.0
   ```

   If you've already configured AWS CLI, you can omit the account ID:
   ```bash
   ./ecr-push.sh us-west-2 k3s-app v1.0.0
   ```

### For Artifactory

Use the Artifactory-specific script for pushing to JFrog Artifactory:

1. Make the script executable:
   ```bash
   chmod +x artifactory-push.sh
   ```

2. Run the script with Artifactory URL, repository name, credentials, and tag:
   ```bash
   ./artifactory-push.sh https://artifactory.example.com docker-local myuser mypassword k3s-app v1.0.0
   ```

   You can also set credentials as environment variables:
   ```bash
   export ARTIFACTORY_USERNAME=myuser
   export ARTIFACTORY_PASSWORD=mypassword
   ./artifactory-push.sh https://artifactory.example.com docker-local
   ```

## Updating the Helm Chart

After building and pushing your custom images, update the `values.yaml` file in the Helm chart:

```yaml
containers:
  frontend:
    image:
      repository: my-registry.example.com/k3s-app/frontend
      tag: v1.0.0
  backend:
    image:
      repository: my-registry.example.com/k3s-app/backend
      tag: v1.0.0
  database:
    image:
      repository: my-registry.example.com/k3s-app/database
      tag: v1.0.0
```

## Testing Locally with Docker Compose

You can test your containers locally before deploying to Kubernetes:

```bash
docker-compose up
```

The application will be available at http://localhost:8080