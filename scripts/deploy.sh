#!/bin/bash
set -e

# Script location awareness
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utilities if available
UTILS_PATH="$SCRIPT_DIR/deployment-utils.sh"
if [ -f "$UTILS_PATH" ]; then
    source "$UTILS_PATH"
else
    # Minimal implementation if utils not available
    log() {
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    }
fi

# Configuration paths
ENV_CONFIG_PATH="$PROJECT_ROOT/config/.env.deploy"

# --- Main deployment flow ---

# 1. Check and load environment
log "Starting deployment process"
log "Working directory: $(pwd)"
log "Project root: $PROJECT_ROOT"

if [ ! -f "$ENV_CONFIG_PATH" ]; then
    log "Error: Required environment file not found at $ENV_CONFIG_PATH"
    log "Checking if we can generate it..."
    
    if [ -f "$SCRIPT_DIR/set-env.sh" ]; then
        log "Found set-env.sh, attempting to generate environment file"
        mkdir -p "$(dirname "$ENV_CONFIG_PATH")"
        chmod +x "$SCRIPT_DIR/set-env.sh"
        "$SCRIPT_DIR/set-env.sh" > "$ENV_CONFIG_PATH"
    else
        log "Error: Cannot generate environment file - set-env.sh not found"
        exit 1
    fi
fi

log "Loading deployment variables from $ENV_CONFIG_PATH"
# Use robust environment loading
if [ -f "$UTILS_PATH" ]; then
    load_environment "$ENV_CONFIG_PATH"
else
    # Fallback if utils not available
    set -a
    source "$ENV_CONFIG_PATH"
    set +a
fi

# 2. Validate critical variables
log "Validating required variables"
REQUIRED_VARS="DOCKER_REGISTRY IMAGE_NAME TAG PORT CONTAINER_NAME"
MISSING_VARS=0

for VAR in $REQUIRED_VARS; do
    if [ -z "${!VAR}" ]; then
        log "Error: Required variable $VAR is not set"
        MISSING_VARS=$((MISSING_VARS+1))
    fi
done

if [ $MISSING_VARS -gt 0 ]; then
    log "Error: $MISSING_VARS required variables are missing"
    exit 1
fi

# 3. Pull latest image
log "Pulling image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}

# 4. Deploy with docker-compose
log "Starting container with docker-compose"
docker-compose up -d

# 5. Verify deployment
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

# 6. Clean up
log "Cleaning up old images"
docker image prune -f --filter "label=deployment.environment=${APP_ENV}"

# Log deployment success
if [ -f "$PROJECT_ROOT/deployment_history.log" ]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') - Deployed ${IMAGE_NAME}:${TAG}" >> "$PROJECT_ROOT/deployment_history.log"
fi

log "Deployment completed successfully"
