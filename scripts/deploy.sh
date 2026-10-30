#!/bin/bash
#
# FoodDash Deployment Script
# Runs ON the EC2 instance via AWS SSM Run Command (triggered by GitHub Actions)
#
# Usage: deploy.sh <ECR_REGISTRY> <IMAGE_TAG> <AWS_REGION>
#
# What it does:
#   1. Logs into ECR
#   2. Fetches DB credentials from Secrets Manager
#   3. Stops pm2 processes (if transitioning from pm2 to Docker)
#   4. Pulls the 4 latest Docker images from ECR (3 backend + 1 frontend)
#   5. Stops & removes old containers
#   6. Starts new containers with env vars from Secrets Manager
#   7. Runs health checks on each service (4 total)
#   8. Cleans up old images
#

set -euo pipefail

# ── Arguments ──────────────────────────────────────────────
ECR_REGISTRY="$1"
IMAGE_TAG="$2"
AWS_REGION="$3"

echo "========================================"
echo "  FoodDash Deployment"
echo "  Registry : $ECR_REGISTRY"
echo "  Tag      : $IMAGE_TAG"
echo "  Region   : $AWS_REGION"
echo "========================================"

# ── Step 1: ECR Login ──────────────────────────────────────
echo ">>> [1/8] Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# ── Step 2: Fetch secrets from Secrets Manager ─────────────
echo ">>> [2/8] Fetching DB credentials from Secrets Manager..."
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "fooddash/db-credentials" \
  --region "$AWS_REGION" \
  --query 'SecretString' \
  --output text)

# Parse JSON using python3 (python3 is pre-installed on the Golden AMI)
DB_HOST=$(echo "$SECRET"     | python3 -c "import sys,json; print(json.load(sys.stdin)['DB_HOST'])")
DB_USER=$(echo "$SECRET"     | python3 -c "import sys,json; print(json.load(sys.stdin)['DB_USER'])")
DB_PASSWORD=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)['DB_PASSWORD'])")
DB_NAME=$(echo "$SECRET"     | python3 -c "import sys,json; print(json.load(sys.stdin)['DB_NAME'])")
JWT_SECRET=$(echo "$SECRET"  | python3 -c "import sys,json; print(json.load(sys.stdin)['JWT_SECRET'])")

echo "    DB Host: $DB_HOST"
echo "    DB User: $DB_USER"
echo "    DB Name: $DB_NAME"

# ── Step 3: Stop pm2 services ──────────────────────────────
# The Golden AMI boots services via pm2. Docker containers need
# the same ports (3001-3003), so we stop pm2 first to avoid conflicts.
echo ">>> [3/8] Stopping pm2 services (if running)..."
if command -v pm2 &>/dev/null; then
  sudo -u ubuntu pm2 stop all 2>/dev/null || echo "    No pm2 processes to stop"
else
  echo "    pm2 not installed — skipping"
fi

# ── Step 4: Pull latest images from ECR ────────────────────
echo ">>> [4/8] Pulling latest Docker images from ECR..."
docker pull "$ECR_REGISTRY/fooddash/user-service:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/fooddash/restaurant-service:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/fooddash/order-service:$IMAGE_TAG"
docker pull "$ECR_REGISTRY/fooddash/frontend:$IMAGE_TAG"

# ── Step 5: Stop & remove old containers ───────────────────
echo ">>> [5/8] Stopping old containers (if any)..."
for svc in fooddash-user fooddash-restaurant fooddash-order fooddash-frontend; do
  docker stop "$svc" 2>/dev/null || true
  docker rm   "$svc" 2>/dev/null || true
done

# ── Step 6: Start new containers ───────────────────────────
echo ">>> [6/8] Starting new containers..."

docker run -d --name fooddash-user \
  -p 3001:3001 \
  -e DB_HOST="$DB_HOST" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_NAME="$DB_NAME" \
  -e PORT=3001 \
  -e JWT_SECRET="$JWT_SECRET" \
  --restart unless-stopped \
  "$ECR_REGISTRY/fooddash/user-service:$IMAGE_TAG"

docker run -d --name fooddash-restaurant \
  -p 3002:3002 \
  -e DB_HOST="$DB_HOST" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_NAME="$DB_NAME" \
  -e PORT=3002 \
  -e JWT_SECRET="$JWT_SECRET" \
  --restart unless-stopped \
  "$ECR_REGISTRY/fooddash/restaurant-service:$IMAGE_TAG"

docker run -d --name fooddash-order \
  -p 3003:3003 \
  -e DB_HOST="$DB_HOST" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_NAME="$DB_NAME" \
  -e PORT=3003 \
  -e JWT_SECRET="$JWT_SECRET" \
  --restart unless-stopped \
  "$ECR_REGISTRY/fooddash/order-service:$IMAGE_TAG"

# Frontend container — no DB credentials needed
# The Vite app uses the ALB URL for API calls (baked into the code at build time)
docker run -d --name fooddash-frontend \
  -p 3000:3000 \
  --restart unless-stopped \
  "$ECR_REGISTRY/fooddash/frontend:$IMAGE_TAG"

# ── Step 7: Health checks ──────────────────────────────────
echo ">>> [7/8] Running health checks..."
sleep 5

check_health() {
  local name="$1"
  local port="$2"

  for i in $(seq 1 10); do
    if curl -sf "http://localhost:$port/health" | grep -q "ok"; then
      echo "  ✓ $name is healthy (attempt $i)"
      return 0
    fi
    sleep 2
  done

  echo "  ✗ $name FAILED health check after 10 attempts"
  echo "  --- Last 15 log lines ---"
  docker logs "fooddash-$(echo "$name" | sed 's/-service//')" --tail 15 2>&1 || true
  return 1
}

check_health "user-service"       3001
check_health "restaurant-service" 3002
check_health "order-service"       3003

# Frontend health check — Vite dev server has no /health endpoint
# so we check if port 3000 responds with HTTP 200
FRONTEND_OK=false
for i in $(seq 1 10); do
  if curl -sf -o /dev/null "http://localhost:3000"; then
    echo "  ✓ frontend is healthy (attempt $i)"
    FRONTEND_OK=true
    break
  fi
  sleep 2
done

if [ "$FRONTEND_OK" = false ]; then
  echo "  ✗ frontend FAILED health check after 10 attempts"
  echo "  --- Last 15 log lines ---"
  docker logs fooddash-frontend --tail 15 2>&1 || true
  exit 1
fi

# ── Step 8: Cleanup ────────────────────────────────────────
echo ">>> [8/8] Cleaning up old (dangling) images..."
docker image prune -f 2>/dev/null || true

echo ""
echo "========================================"
echo "  ✓ Deployment Complete!"
echo "  4 services running with tag: $IMAGE_TAG"
echo "  → user-service       (port 3001)"
echo "  → restaurant-service (port 3002)"
echo "  → order-service      (port 3003)"
echo "  → frontend           (port 3000)"
echo "========================================"
