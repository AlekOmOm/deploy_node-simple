#!/bin/bash
set -e

# Base directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the utility functions
if [ -f "$SCRIPT_DIR/deployment-utils.sh" ]; then
  source "$SCRIPT_DIR/deployment-utils.sh"
else
  # Define minimal log function if utils not available
  log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
  }
  log "Warning: deployment-utils.sh not found, using limited functionality"
fi

# Log initial information
log "Starting deployment process"
log "Working directory: $(pwd)"
log "Project root: $PROJECT_ROOT"

# Check directory content
log "content: $(ls -la)"
log " - config content: $(ls -la config)"
log " - scripts content: $(ls -la scripts)"

# Environment configuration path
ENV_CONFIG_PATH="config/.env.deploy"

# Environment file loading
if [ -f "$ENV_CONFIG_PATH" ]; then
  log "Loading deployment variables from $ENV_CONFIG_PATH"
  
  # Use utility function if available
  if type load_environment &>/dev/null; then
    load_environment "$ENV_CONFIG_PATH"
  else
    # Original approach: Parse line by line
    while IFS='=' read -r key value || [ -n "$key" ]; do
      # Skip empty lines and comments
      if [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]]; then
        continue
      fi
      
      # Remove any whitespace and export the variable
      key=$(echo "$key" | xargs)
      value=$(echo "$value" | xargs)
      
      # Validate key before export to avoid command execution
      if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        export "$key=$value"
      else
        log "Warning: Skipping invalid variable name: $key"
      fi
    done < "$ENV_CONFIG_PATH"
  fi
else
  log "Error: .env.deploy file not found at $ENV_CONFIG_PATH"
  exit 1
fi

# Log configuration
log "Starting deployment of ${IMAGE_NAME}:${TAG}"
log "Environment: ${APP_ENV}"
log "Container: ${CONTAINER_NAME}"
log "Port: ${PORT}"

# Check Docker availability
if type check_docker_availability &>/dev/null; then
  check_docker_availability || exit 1
else
  # Simple check
  if ! command -v docker &> /dev/null; then
    log "Error: Docker is not installed or not in PATH"
    exit 1
  fi
fi

# Required variables
REQUIRED_VARS=("DOCKER_REGISTRY" "IMAGE_NAME" "TAG" "PORT" "CONTAINER_NAME")
MISSING=0

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    log "Error: Required variable $var is not set"
    MISSING=$((MISSING+1))
  fi
done

if [ $MISSING -gt 0 ]; then
  log "Error: $MISSING required variables are missing"
  exit 1
fi

# Pull latest image
log "Pulling latest image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}

# Starting container
log "Starting container with docker-compose"
if [[ "$(docker compose version 2>/dev/null)" ]]; then
  docker compose up -d
else
  docker-compose up -d
fi

# Verify deployment
if type verify_deployment &>/dev/null; then
  verify_deployment "localhost" "$PORT" 3 5 || exit 1
else
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

# Clean up old images
if type cleanup_old_resources &>/dev/null; then
  cleanup_old_resources "$APP_ENV"
else
  log "Cleaning up old images"
  docker image prune -f --filter "label=deployment.environment=${APP_ENV}" || true
fi

log "Deployment completed successfully"
