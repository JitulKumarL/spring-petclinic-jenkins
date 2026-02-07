#!/usr/bin/env bash
#
# Rollback script - deploys previous build's artifact to remote or local
# Usage: ./rollback.sh --env <env> --build-number <N> --app <app-name>
#        ./rollback.sh --env dev --build-number 42 --app petclinic --host 192.168.31.121
#
# ROLLBACK_IMAGE or ROLLBACK_JAR must be set for remote deployment (from Jenkins Copy Artifact)
#

set -euo pipefail

# Defaults
ENV="dev"
BUILD_NUMBER=""
APP_NAME="petclinic"
REGISTRY="${DOCKER_REGISTRY:-registry.example.com}"
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-/home/deploy/petclinic}"
USE_REGISTRY="${USE_REGISTRY:-true}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV="$2"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --app)
            APP_NAME="$2"
            shift 2
            ;;
        --host)
            DEPLOY_HOST="$2"
            shift 2
            ;;
        --user)
            DEPLOY_USER="$2"
            shift 2
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$BUILD_NUMBER" ]]; then
    echo "Error: --build-number is required"
    exit 1
fi

# SSH helper
run_cmd() {
    local cmd="$1"
    if [[ -n "$DEPLOY_HOST" ]]; then
        ssh -o StrictHostKeyChecking=no "${DEPLOY_USER}@${DEPLOY_HOST}" "$cmd"
    else
        eval "$cmd"
    fi
}

copy_to_remote() {
    local src="$1"
    local dest="$2"
    scp -o StrictHostKeyChecking=no "$src" "${DEPLOY_USER}@${DEPLOY_HOST}:${dest}"
}

echo "=== ROLLBACK: Deploying build #${BUILD_NUMBER} (previous good build) ==="
if [[ -n "$DEPLOY_HOST" ]]; then
    echo "Target host: ${DEPLOY_USER}@${DEPLOY_HOST}"
fi

# Determine what to deploy
if [[ -n "${ROLLBACK_IMAGE:-}" ]]; then
    IMAGE_TO_DEPLOY="${ROLLBACK_IMAGE}"
    echo "Rolling back to image: ${IMAGE_TO_DEPLOY}"
    if [[ -n "$DEPLOY_HOST" ]]; then
        if [[ "${USE_REGISTRY}" == "true" ]]; then
            run_cmd "docker stop ${APP_NAME}-${ENV} 2>/dev/null || true"
            run_cmd "docker rm ${APP_NAME}-${ENV} 2>/dev/null || true"
            run_cmd "docker pull ${IMAGE_TO_DEPLOY}"
            run_cmd "docker run -d --name ${APP_NAME}-${ENV} -p 8080:8080 -e SPRING_PROFILES_ACTIVE=${ENV} --restart unless-stopped ${IMAGE_TO_DEPLOY}"
        else
            echo "Image transfer rollback must be run from Jenkins (agent has the image)"
            exit 1
        fi
    else
        docker stop ${APP_NAME}-${ENV} 2>/dev/null || true
        docker rm ${APP_NAME}-${ENV} 2>/dev/null || true
        docker run -d --name ${APP_NAME}-${ENV} -p 8080:8080 -e SPRING_PROFILES_ACTIVE="${ENV}" --restart unless-stopped "${IMAGE_TO_DEPLOY}"
    fi
elif [[ -n "${ROLLBACK_JAR:-}" ]] && [[ -f "${ROLLBACK_JAR}" ]]; then
    echo "Rolling back to JAR: ${ROLLBACK_JAR}"
    run_cmd "mkdir -p ${REMOTE_APP_DIR}"
    copy_to_remote "$ROLLBACK_JAR" "${REMOTE_APP_DIR}/app.jar"
    run_cmd "pkill -f 'java.*app.jar' 2>/dev/null || true"
    run_cmd "sleep 2"
    run_cmd "cd ${REMOTE_APP_DIR} && nohup java -jar app.jar > app.log 2>&1 &"
else
    echo "Error: ROLLBACK_IMAGE or ROLLBACK_JAR must be set with valid value"
    exit 1
fi

echo "=== Rollback complete. Previous build #${BUILD_NUMBER} restored. ==="
