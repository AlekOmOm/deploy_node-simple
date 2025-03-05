#!/bin/bash
set -e

# Log function for better visibility
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

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
  exit 1
fi

# Generate a unique compose project name based on environment
#export COMPOSE_PROJECT_NAME="${APP_NAME}-${APP_ENV}"

# Log configuration
log "Starting deployment of ${IMAGE_NAME}:${TAG}"
log "Environment: ${APP_ENV}"
log "Container: ${CONTAINER_NAME}"
log "Port: ${PORT}"
#log "Compose project: ${COMPOSE_PROJECT_NAME}"

# Pull latest image
log "Pulling latest image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  log "Container ${CONTAINER_NAME} already exists, stopping it first"
  docker stop ${CONTAINER_NAME} || true
  docker rm ${CONTAINER_NAME} || true
fi

# Starting container
log "Starting container with docker-compose"
docker-compose up -d

# Verify deployment
log "Verifying deployment..."
max_retries=10
retry_count=0
success=false

while [ $retry_count -lt $max_retries ]; do
  log "Checking container health (attempt $((retry_count+1))/${max_retries})..."
  sleep 3
  
  # Check container status
  container_status=$(docker inspect --format='{{.State.Status}}' ${CONTAINER_NAME} 2>/dev/null || echo "not_found")
  
  if [ "$container_status" = "running" ]; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/ || echo "failed")
    
    if [ "$STATUS" = "200" ]; then
      log "✅ Deployment successful! Application is running."
      success=true
      break
    else
      log "Container is running but health check failed with status: ${STATUS}"
    fi
  else
    log "Container is not running. Status: ${container_status}"
  fi
  
  retry_count=$((retry_count+1))
done

# Starting container
log "Starting container with docker-compose"
if ! docker-compose up -d; then
  log "Error: Failed to start container with docker-compose"
  log "Trying docker run as fallback..."
  
  # Stop and remove container if it exists
  docker stop ${CONTAINER_NAME} 1>/dev/null || true
  docker rm ${CONTAINER_NAME} 1>/dev/null || true
  
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

  # Check container status
  container_status=$(docker inspect --format='{{.State.Status}}' ${CONTAINER_NAME} 2>/dev/null || echo "not_found")
  
  if [ "$container_status" = "running" ]; then
    $success=true
  fi
fi

if [ "$success" = false ]; then
  log "❌ Deployment verification failed after ${max_retries} attempts."
  log "Check container logs with: docker logs ${CONTAINER_NAME}"
  log "Container state:"
  docker inspect --format='{{.State}}' ${CONTAINER_NAME} || echo "Container not found"
  exit 1
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
