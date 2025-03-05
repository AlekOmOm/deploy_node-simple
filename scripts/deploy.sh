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

# Use load_environment from deployment-utils.sh if available, otherwise fall back
if type load_environment &>/dev/null; then
  load_environment "$ENV_CONFIG_PATH" true
else
  exit 1
fi

# Use check_required_vars from deployment-utils.sh if available, otherwise fall back
if type check_required_vars &>/dev/null; then
  check_required_vars DOCKER_REGISTRY IMAGE_NAME TAG CONTAINER_NAME PORT
else
  # Check for required variables
  for var in DOCKER_REGISTRY IMAGE_NAME TAG CONTAINER_NAME PORT; do
    if [ -z "${!var}" ]; then
      log "Error: Required variable $var is not set"
      exit 1
    fi
  done
fi

# Log configuration
log "Starting deployment of ${IMAGE_NAME}:${TAG}"
log "Environment: ${APP_ENV}"
log "Container: ${CONTAINER_NAME}"
log "Port: ${PORT}"

# Use check_docker_availability from deployment-utils.sh if available, otherwise fall back
if type check_docker_availability &>/dev/null; then
  check_docker_availability
else
  # Check if Docker is available
  if ! command -v docker &> /dev/null; then
    log "Error: Docker is not installed or not in PATH"
    exit 1
  fi

  if ! docker info &> /dev/null; then
    log "Error: Docker daemon is not running or current user doesn't have permissions"
    exit 1
  fi
fi

# Pull latest image
log "Pulling latest image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
if ! docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}; then
  log "Failed to pull specific tag. Trying latest tag..."
  
  # Try to pull the latest tag for this environment
  if docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${LATEST_TAG}; then
    # Update TAG to use the successfully pulled image
    export TAG="${LATEST_TAG}"
    log "Using image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
  else
    log "Error: Failed to pull both specific and latest image"
    exit 1
  fi
fi

# check if CONTAINER_NAME and PORT are already in use
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
  log "Container with name ${CONTAINER_NAME} already exists. Stopping and removing..."
  docker stop ${CONTAINER_NAME} 2>/dev/null || true
  docker rm ${CONTAINER_NAME} 2>/dev/null || true

  # check if port is already in use

    # Check port availability
    if type check_port_availability &>/dev/null; then
      if ! check_port_availability "${PORT}" "${HOST:-0.0.0.0}"; then
        log "Error: Port ${PORT} is already in use on ${HOST:-0.0.0.0}"
        log "Please choose a different port or stop the service using this port"
        exit 1
      fi
    fi
fi

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

# Use verify_deployment from deployment-utils.sh if available, otherwise fall back
if type verify_deployment &>/dev/null; then
  verify_deployment "localhost" "${PORT}" 3 5
else
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
fi

# Use cleanup_old_resources from deployment-utils.sh if available, otherwise fall back
if type cleanup_old_resources &>/dev/null; then
  cleanup_old_resources "${APP_ENV}"
else
  # Clean up old images
  log "Cleaning up old images"
  docker image prune -f --filter "label=deployment.environment=${APP_ENV}" || true
fi

log "Deployment completed successfully"
