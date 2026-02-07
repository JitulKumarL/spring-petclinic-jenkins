#!/usr/bin/env bash
#
# Deploy script for production-grade pipeline
# Supports: local Docker, remote Docker (SSH), remote JAR (SSH)
# Usage: ./deploy.sh --env dev|staging|prod --image <image> --app <app-name>
#        ./deploy.sh --env dev --image <image> --app <app-name> --host <ip> [--user <ssh-user>]
#        ./deploy.sh --env dev --jar <path> --app <app-name> --host <ip> [--user <ssh-user>]
#
# For remote: set DEPLOY_HOST or use --host. Uses SSH_CREDENTIALS_ID or SSH key from agent.
#

set -euo pipefail

# Defaults
ENV="dev"
IMAGE=""
JAR_PATH=""
APP_NAME="petclinic"
DEPLOY_METHOD="${DEPLOY_METHOD:-docker}"
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-/home/deploy/petclinic}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV="$2"
            shift 2
            ;;
        --image)
            IMAGE="$2"
            shift 2
            ;;
        --jar)
            JAR_PATH="$2"
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
        --method)
            DEPLOY_METHOD="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Optional: set SSH_DEBUG=1 for verbose SSH (helps diagnose connection/auth failures)
SSH_OPTS="-o StrictHostKeyChecking=no"
[[ "${SSH_DEBUG:-0}" == "1" ]] && SSH_OPTS="-v ${SSH_OPTS}"

# SSH helper - run command on remote or locally
run_cmd() {
    local cmd="$1"
    if [[ -n "$DEPLOY_HOST" ]]; then
        ssh ${SSH_OPTS} "${DEPLOY_USER}@${DEPLOY_HOST}" "$cmd"
    else
        eval "$cmd"
    fi
}

# Copy file to remote
copy_to_remote() {
    local src="$1"
    local dest="$2"
    scp ${SSH_OPTS} "$src" "${DEPLOY_USER}@${DEPLOY_HOST}:${dest}"
}

echo "=== Deploying ${APP_NAME} to ${ENV} ==="
if [[ -n "$DEPLOY_HOST" ]]; then
    echo "Target host: ${DEPLOY_USER}@${DEPLOY_HOST}"
    echo "Testing SSH connection..."
    run_cmd "echo 'SSH OK'" || { echo "ERROR: Cannot connect to ${DEPLOY_USER}@${DEPLOY_HOST} (check host, firewall, SSH key in authorized_keys)"; exit 255; }
fi

# Remote Docker - pull from registry (requires image pushed to registry)
deploy_remote_docker_registry() {
    run_cmd "docker stop ${APP_NAME}-${ENV} 2>/dev/null || true"
    run_cmd "docker rm ${APP_NAME}-${ENV} 2>/dev/null || true"
    run_cmd "docker pull ${IMAGE}"
    run_cmd "docker run -d \
        --name ${APP_NAME}-${ENV} \
        -p 8080:8080 \
        -e SPRING_PROFILES_ACTIVE=${ENV} \
        --restart unless-stopped \
        ${IMAGE}"
    echo "Deployed via remote Docker (registry). Container: ${APP_NAME}-${ENV}"
}

# Remote Docker - transfer image via docker save/load (no registry needed)
deploy_remote_docker_transfer() {
    local tar_file="/tmp/${APP_NAME}-${ENV}-image.tar"
    echo "Transferring image to ${DEPLOY_HOST} (no registry)..."
    docker save "${IMAGE}" -o "${tar_file}"
    scp -o StrictHostKeyChecking=no "${tar_file}" "${DEPLOY_USER}@${DEPLOY_HOST}:/tmp/"
    run_cmd "docker load -i /tmp/$(basename ${tar_file})"
    run_cmd "docker stop ${APP_NAME}-${ENV} 2>/dev/null || true"
    run_cmd "docker rm ${APP_NAME}-${ENV} 2>/dev/null || true"
    run_cmd "docker run -d \
        --name ${APP_NAME}-${ENV} \
        -p 8080:8080 \
        -e SPRING_PROFILES_ACTIVE=${ENV} \
        --restart unless-stopped \
        ${IMAGE}"
    rm -f "${tar_file}"
    echo "Deployed via remote Docker (image transfer). Container: ${APP_NAME}-${ENV}"
}

# Remote Docker deployment (registry or transfer)
deploy_remote_docker() {
    if [[ -z "$IMAGE" ]]; then
        echo "Error: --image is required for Docker deployment"
        exit 1
    fi
    if [[ "${USE_REGISTRY:-true}" == "true" ]]; then
        deploy_remote_docker_registry
    else
        deploy_remote_docker_transfer
    fi
}

# Remote JAR deployment (no registry needed)
deploy_remote_jar() {
    if [[ -z "$JAR_PATH" ]] || [[ ! -f "$JAR_PATH" ]]; then
        echo "Error: --jar path required and must exist for JAR deployment"
        exit 1
    fi
    echo "Step 1/5: Creating remote directory ${REMOTE_APP_DIR}"
    run_cmd "mkdir -p ${REMOTE_APP_DIR}"
    echo "Step 2/5: Copying JAR to ${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_APP_DIR}/app.jar"
    copy_to_remote "$JAR_PATH" "${REMOTE_APP_DIR}/app.jar"
    echo "Step 3/5: Stopping existing process (if any)"
    run_cmd "pkill -f 'java.*app.jar' 2>/dev/null || :"
    run_cmd "sleep 2"
    echo "Step 4/5: Starting application"
    run_cmd "cd ${REMOTE_APP_DIR} && nohup java -jar app.jar > app.log 2>&1 &"
    run_cmd "sleep 3"
    echo "Step 5/5: Done"
    echo "Deployed via remote JAR to ${REMOTE_APP_DIR}"
}

# Local Docker (original behavior)
deploy_local_docker() {
    if [[ -z "$IMAGE" ]]; then
        echo "Error: --image is required"
        exit 1
    fi
    docker stop ${APP_NAME}-${ENV} 2>/dev/null || true
    docker rm ${APP_NAME}-${ENV} 2>/dev/null || true
    docker run -d \
        --name ${APP_NAME}-${ENV} \
        -p 8080:8080 \
        -e SPRING_PROFILES_ACTIVE="${ENV}" \
        --restart unless-stopped \
        "${IMAGE}"
    echo "Deployed via local Docker. Container: ${APP_NAME}-${ENV}"
}

# Main deployment logic
if [[ -n "$DEPLOY_HOST" ]]; then
    if [[ -n "$JAR_PATH" ]]; then
        deploy_remote_jar
    else
        deploy_remote_docker
    fi
else
    deploy_local_docker
fi

echo "=== Deployment complete ==="
