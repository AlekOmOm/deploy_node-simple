#!/bin/bash
set -e

# Try to source deployment utilities if available
if [ -f "./scripts/deployment-utils.sh" ]; then
  source "./scripts/deployment-utils.sh"
elif [ -f "./scripts/deployment_utils.sh" ]; then
  source "./scripts/deployment_utils.sh"
else
  # Fallback logging function if utilities aren't available
  log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
  }
  log "Warning: deployment-utils.sh not found, using limited functionality"
fi

log "Starting deployment process"
log "Working directory: $(pwd)"
log "Project root: $(pwd)"

log "content: $(ls -la)"
log "- config content: $(ls -la config)"
log "- scripts content: $(ls -la scripts)"

# Primary source of variables: .env.deploy
ENV_CONFIG_PATH="config/.env.deploy"

if [ -f "$ENV_CONFIG_PATH" ]; then
  log "Loading deployment variables from $ENV_CONFIG_PATH"
  
  # More robust way to load environment variables
  while IFS='=' read -r key value || [ -n "$key" ]; do
    # Skip empty lines and comments
    if [[ -z "$key" || "$key" =~ ^# ]]; then
      continue
    fi
    
    # Remove any whitespace and export the variable
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    export "$key=$value"
    
  done < "$ENV_CONFIG_PATH"
else
  log "Error: .env.deploy file not found at $ENV_CONFIG_PATH" 
  
  # Try to generate it using set-env.sh
  if [ -f "./scripts/set-env.sh" ]; then
    log "Attempting to generate .env.deploy using set-env.sh"
    mkdir -p config
    chmod +x ./scripts/set-env.sh
    ./scripts/set-env.sh > "$ENV_CONFIG_PATH"
    
    if [ -f "$ENV_CONFIG_PATH" ]; then
      log "Successfully generated $ENV_CONFIG_PATH"
      source "$ENV_CONFIG_PATH"
    else
      log "Failed to generate $ENV_CONFIG_PATH"
      exit 1
    fi
  else
    exit 1
  fi
fi

# Check for required variables
for var in DOCKER_REGISTRY IMAGE_NAME TAG CONTAINER_NAME PORT; do
  if [ -z "${!var}" ]; then
    log "Error: Required variable $var is not set"
    exit 1
  fi
done

# Log configuration
log "Starting deployment of ${IMAGE_NAME}:${TAG}"
log "Environment: ${APP_ENV}"
log "Container: ${CONTAINER_NAME}"
log "Port: ${PORT}"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
  log "Error: Docker is not installed or not in PATH"
  exit 1
fi

if ! docker info &> /dev/null; then
  log "Error: Docker daemon is not running or current user doesn't have permissions"
  exit 1
fi

# Pull latest image
log "Pulling latest image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG} || {
  log "Failed to pull specific tag. Trying latest for this environment..."
  docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:latest-${APP_ENV} || {
    log "Error: Failed to pull both specific and latest image"
    exit 1
  }
  # Update TAG to use the successfully pulled image
  export TAG="latest-${APP_ENV}"
  log "Using image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
}

# Starting container
log "Starting container with docker-compose"
if ! docker-compose up -d; then
  log "Error: Failed to start container with docker-compose"
  log "Trying docker run as fallback..."
  
  # Stop and remove container if it exists
  docker stop ${CONTAINER_NAME} 2>/dev/null || true
  docker rm ${CONTAINER_NAME} 2>/dev/null || true
  
  # Run with docker
  docker run -d \
    --name ${CONTAINER_NAME} \
    --restart ${RESTART_POLICY:-unless-stopped} \
    -p ${PORT}:${PORT} \
    -e PORT=${PORT} \
    -e APP_ENV=${APP_ENV} \
    -e APP_NAME=${APP_NAME} \
    -e APP_VERSION=${APP_VERSION} \
    ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}
fi

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
docker image prune -f --filter "label=deployment.environment=${APP_ENV}" || true

log "Deployment completed successfully"
