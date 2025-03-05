#!/bin/bash
set -e

# Log function for better visibility
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Set default values if not provided
DOCKER_REGISTRY=${DOCKER_REGISTRY:-ghcr.io}
IMAGE_NAME=${IMAGE_NAME:-username/test-cd-app}
TAG=${TAG:-latest}
CONTAINER_NAME=${CONTAINER_NAME:-test-cd-app}
PORT=${PORT:-3000}
APP_ENV=${APP_ENV:-development}
ENV_FILE=${ENV_FILE:-.env.dev}

# Mark deployment with timestamp and git SHA
export DEPLOYMENT_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
export DEPLOYMENT_SHA=${GITHUB_SHA:-local}

log "Starting deployment of ${IMAGE_NAME}:${TAG}"
log "Environment: ${APP_ENV}"
log "Container: ${CONTAINER_NAME}"
log "Port: ${PORT}"

# Ensure we have the environment file
if [ ! -f "${ENV_FILE}" ]; then
  log "Warning: ${ENV_FILE} not found. Using default environment variables."
fi

# Pull latest image
log "Pulling latest image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}

# Copy environment file to deployment.env for docker-compose
log "Preparing environment file for docker-compose"
if [ -f "${ENV_FILE}" ]; then
  cp ${ENV_FILE} deployment.env
else
  # Create a minimal environment file
  cat > deployment.env << EOL
HOST=${HOST}
PORT=${PORT}
APP_ENV=${APP_ENV}
APP_DEPLOYMENT=${DEPLOYMENT_SHA}
EOL
fi

# Run docker-compose
log "Starting container with docker-compose"
docker-compose up -d

# Verify deployment
log "Verifying deployment..."
sleep 5
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/ || echo "failed")

if [ "$STATUS" = "200" ]; then
  log "✅ Deployment successful! Application is running."
else
  log "❌ Deployment verification failed. Status: ${STATUS}"
  log "Check container logs with: docker logs ${CONTAINER_NAME}"
  exit 1
fi

# Clean up old images
log "Cleaning up old images"
docker image prune -f --filter "label=deployment.environment=${APP_ENV}"

log "Deployment completed successfully"
