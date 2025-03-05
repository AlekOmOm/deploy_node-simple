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

# Determine current branch
BRANCH=${GITHUB_REF#refs/heads/}

# Set environment based on branch
if [[ $BRANCH == "main" || $BRANCH == "master" ]]; then
  # Production environment
  echo "APP_ENV=${PROD_ENV:-production}"
  echo "TAG=production"
  echo "PORT=${PROD_PORT:-8080}"
  echo "HOST=${PROD_HOST:-0.0.0.0}"
  echo "CONTAINER_NAME=${PROD_CONTAINER_NAME:-${APP_NAME:-app}-prod}"
  echo "NODE_ENV=${PROD_NODE_ENV:-production}"
  echo "LOG_LEVEL=${PROD_LOG_LEVEL:-info}"
  echo "DEPLOYMENT_PATH=~/app-deployment/production"
else
  # Development environment
  echo "APP_ENV=${DEV_ENV:-development}"
  echo "TAG=development" 
  echo "PORT=${DEV_PORT:-3000}"
  echo "HOST=${DEV_HOST:-0.0.0.0}"
  echo "CONTAINER_NAME=${DEV_CONTAINER_NAME:-${APP_NAME:-app}-dev}"
  echo "NODE_ENV=${DEV_NODE_ENV:-development}"
  echo "LOG_LEVEL=${DEV_LOG_LEVEL:-debug}"
  echo "DEPLOYMENT_PATH=~/app-deployment/development"
fi

# Common variables for both environments
echo "DOCKER_REGISTRY=${DOCKER_REGISTRY:-ghcr.io}"
#echo "IMAGE_NAME=${GITHUB_REPOSITORY_OWNER:-username}/${APP_NAME:-app}"
# IMAGE_NAME to lower case
echo "IMAGE_NAME=$(echo ${GITHUB_REPOSITORY_OWNER:-username}/${APP_NAME:-app} | tr '[:upper:]' '[:lower:]')"
echo "NODE_VERSION=${NODE_VERSION:-lts}"
echo "NODE_VERSION_TAG=${NODE_VERSION_TAG:-slim}"
echo "APP_VERSION=${APP_VERSION:-1.0.0}"
echo "RESTART_POLICY=${RESTART_POLICY:-unless-stopped}"
echo "DEPLOYMENT_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "DEPLOYMENT_SHA=${GITHUB_SHA:-local}"
