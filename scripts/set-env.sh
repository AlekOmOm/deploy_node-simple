#!/bin/bash
# Script for determining environment variables based on branch

# Source the configuration file first
if [ -f "./config/.env.config" ]; then
  set -a
  source "./config/.env.config"
  set +a
else
  echo "Warning: config/.env.config not found, using fallback values"
fi

# Accept environment variables from parameters if available
GIT_BRANCH=${1:-${GITHUB_REF_NAME:-""}}
GIT_COMMIT=${2:-${GITHUB_SHA:-""}}

# Try to get Git info if not provided and in a Git repository
if [ -z "$GIT_BRANCH" ] && command -v git &> /dev/null && git rev-parse --is-inside-work-tree &> /dev/null; then
  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  GIT_COMMIT=$(git rev-parse HEAD)
fi

# Set fallback values if Git info is still missing
if [ -z "$GIT_BRANCH" ]; then
  if [ -n "$APP_ENV" ] && [ "$APP_ENV" = "production" ]; then
    GIT_BRANCH="main"
  else
    GIT_BRANCH="dev"
  fi
  echo "# Warning: Using fallback branch $GIT_BRANCH" >&2
fi

if [ -z "$GIT_COMMIT" ]; then
  GIT_COMMIT=$(date +%Y%m%d%H%M%S)
  echo "# Warning: Using timestamp as commit ID" >&2
fi

# Convert to lowercase for Docker compatibility
APP_NAME=$(echo ${APP_NAME:-deploy_node-simple} | tr '[:upper:]' '[:lower:]')
GITHUB_USERNAME=$(echo ${GITHUB_USERNAME:-alekomom} | tr '[:upper:]' '[:lower:]')

# Set environment based on branch
if [[ $GIT_BRANCH == "main" || $GIT_BRANCH == "master" ]]; then
  # Production environment
  echo "APP_ENV=${PROD_ENV:-production}"
  echo "PORT=${PROD_PORT:-8080}"
  echo "HOST=${PROD_HOST:-0.0.0.0}"
  echo "TAG=production-$(echo ${GIT_COMMIT} | tr '[:upper:]' '[:lower:]')"
  echo "IMAGE_NAME=$(echo ${GITHUB_USERNAME}/${APP_NAME} | tr '[:upper:]' '[:lower:]')"
  echo "CONTAINER_NAME=$(echo ${PROD_CONTAINER_NAME:-${APP_NAME}-prod} | tr '[:upper:]' '[:lower:]')"
  echo "NODE_ENV=${PROD_NODE_ENV:-production}"
  echo "LOG_LEVEL=${PROD_LOG_LEVEL:-info}"
  echo "DEPLOYMENT_PATH=~/app-deployment/production"
else
  # Development environment
  echo "APP_ENV=${DEV_ENV:-development}"
  echo "PORT=${DEV_PORT:-3000}"
  echo "HOST=${DEV_HOST:-0.0.0.0}"
  echo "TAG=development-$(echo ${GIT_COMMIT} | tr '[:upper:]' '[:lower:]')"
  echo "IMAGE_NAME=$(echo ${GITHUB_USERNAME}/${APP_NAME} | tr '[:upper:]' '[:lower:]')"
  echo "CONTAINER_NAME=$(echo ${DEV_CONTAINER_NAME:-${APP_NAME}-dev} | tr '[:upper:]' '[:lower:]')"
  echo "NODE_ENV=${DEV_NODE_ENV:-development}"
  echo "LOG_LEVEL=${DEV_LOG_LEVEL:-debug}"
  echo "DEPLOYMENT_PATH=~/app-deployment/development"
fi

# Common variables for both environments
echo "DOCKER_REGISTRY=${DOCKER_REGISTRY:-ghcr.io}"
echo "NODE_VERSION=${NODE_VERSION:-lts}"
echo "NODE_VERSION_TAG=${NODE_VERSION_TAG:-slim}"
echo "APP_VERSION=${APP_VERSION:-1.0.0}"
echo "RESTART_POLICY=${RESTART_POLICY:-unless-stopped}"
echo "DEPLOYMENT_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "DEPLOYMENT_SHA=${GIT_COMMIT}"
