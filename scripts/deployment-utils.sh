#!/bin/bash

# Common logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Load environment variables from file
load_environment() {
  local env_file=$1
  
  if [ ! -f "$env_file" ]; then
    log "Error: Environment file not found at $env_file"
    exit 1
  fi 

  log "Loading deployment variables from $env_file"
  
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
    
  done < "$env_file"
}

# Check for required environment variables
check_required_vars() {
  local required_vars=$1
  local missing_vars=0
  
  for var in $required_vars; do
    if [ -z "${!var}" ]; then
      log "Error: Required variable $var is not set"
      missing_vars=$((missing_vars+1))
    fi
  done
  
  if [ $missing_vars -gt 0 ]; then
    log "Error: $missing_vars required variables are missing"
    exit 1
  fi
}

# Verify deployment is running
verify_deployment() {
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
}

# Clean up old resources
cleanup_old_resources() {
  log "Cleaning up old images"
  docker image prune -f --filter "label=deployment.environment=${APP_ENV}"
  log "Deployment completed successfully"
}

# Check Docker availability
check_docker_availability() {
  if ! command -v docker &> /dev/null; then
    log "Error: Docker is not installed or not in PATH"
    exit 1
  fi
  
  if ! docker info &> /dev/null; then
    log "Error: Docker daemon is not running or current user doesn't have permissions"
    exit 1
  fi
}
