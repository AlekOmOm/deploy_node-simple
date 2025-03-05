#!/bin/bash
set -e

# Log function for better visibility
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Primary source of variables: .env.deploy

log "dir contents: $(ls -la)"
log "config contents $(ls -la config)"

ENV_CONFIG_PATH= ".env.deploy"

log "content of .env.deploy: $(cat $ENV_CONFIG_PATH)"

if [ -f "$ENV_CONFIG_PATH" ]; then
  log "Loading deployment variables from .env.deploy at $ENV_CONFIG_PATH"
  set -a # automatically export all variables
  source "$ENV_CONFIG_PATH"  
  set +a
else
  log "Error: .env.deploy file not found at $ENV_CONFIG_PATH" 
  exit 1
fi

# Log configuration
log "Starting deployment of ${IMAGE_NAME}:${TAG}"
log "Environment: ${APP_ENV}"
log "Container: ${CONTAINER_NAME}"
log "Port: ${PORT}"

# Pull latest image
log "Pulling latest image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}

# Use .env.deploy directly for docker-compose
log "Using .env.deploy for docker-compose"

# Starting container
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
