#!/bin/bash
# FoodDash Deploy Script
# Called by GitHub Actions deploy job
# Generates ssm-deploy.json and sends it to EC2 via SSM
#
# Required env vars (set by GitHub Actions):
#   ECR_REGISTRY  - e.g. 926239637076.dkr.ecr.ap-south-2.amazonaws.com
#   IMAGE_TAG     - git commit SHA
#   AWS_REGION    - e.g. ap-south-2

set -euo pipefail

# ── 1. Find the SSM-managed EC2 instance ──────────────────────────────────────
echo ">>> Finding EC2 instance..."
INSTANCE_ID=$(aws ssm describe-instance-information \
  --filter "Key=tag:Project,Values=fooddash" \
  --query 'InstanceInformationList[0].InstanceId' \
  --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  echo "ERROR: No SSM-managed EC2 instance found with tag Project=fooddash"
  exit 1
fi

echo "Found instance: $INSTANCE_ID"

# ── 2. Generate the SSM command JSON ─────────────────────────────────────────
# We write the JSON cleanly using Python so no shell escaping issues.
# ECR_REGISTRY, IMAGE_TAG, AWS_REGION are substituted here on the runner.
# All $ variables in the commands array run on the EC2 instance.
python3 - <<PYEOF
import json, os

reg    = os.environ['ECR_REGISTRY']
tag    = os.environ['IMAGE_TAG']
region = os.environ['AWS_REGION']

commands = [
    'set -e',
    'ECR_REGISTRY=' + reg,
    'IMAGE_TAG=' + tag,
    'AWS_REGION=' + region,
    'echo "=== FoodDash Deployment ==="',
    'echo "Tag: $IMAGE_TAG"',
    # ECR login
    'aws ecr get-login-password --region $AWS_REGION | sudo docker login --username AWS --password-stdin $ECR_REGISTRY',
    # Fetch secrets
    'SECRET=$(aws secretsmanager get-secret-value --secret-id fooddash/db-credentials --region $AWS_REGION --query SecretString --output text)',
    'DB_HOST=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)[\'DB_HOST\'])")',
    'DB_USER=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)[\'DB_USER\'])")',
    'DB_PASSWORD=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)[\'DB_PASSWORD\'])")',
    'DB_NAME=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)[\'DB_NAME\'])")',
    'JWT_SECRET=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)[\'JWT_SECRET\'])")',
    'echo "DB_HOST: $DB_HOST"',
    # Stop pm2 and free ports
    'sudo systemctl stop pm2-ubuntu.service 2>/dev/null || true',
    'sudo systemctl disable pm2-ubuntu.service 2>/dev/null || true',
    'sudo -u ubuntu pm2 delete all 2>/dev/null || true',
    'sudo -u ubuntu pm2 save --force 2>/dev/null || true',
    'sudo fuser -k 3000/tcp 2>/dev/null || true',
    'sudo fuser -k 3001/tcp 2>/dev/null || true',
    'sudo fuser -k 3002/tcp 2>/dev/null || true',
    'sudo fuser -k 3003/tcp 2>/dev/null || true',
    # Stop old containers
    'sudo docker stop fooddash-user fooddash-restaurant fooddash-order fooddash-frontend 2>/dev/null || true',
    'sudo docker rm   fooddash-user fooddash-restaurant fooddash-order fooddash-frontend 2>/dev/null || true',
    'sleep 2',
    # Pull images
    'echo "Pulling images..."',
    'sudo docker pull $ECR_REGISTRY/fooddash/user-service:$IMAGE_TAG',
    'sudo docker pull $ECR_REGISTRY/fooddash/restaurant-service:$IMAGE_TAG',
    'sudo docker pull $ECR_REGISTRY/fooddash/order-service:$IMAGE_TAG',
    'sudo docker pull $ECR_REGISTRY/fooddash/frontend:$IMAGE_TAG',
    # Start containers
    'echo "Starting containers..."',
    'sudo docker run -d --name fooddash-user       -p 3001:3001 -e PORT=3001 -e DB_HOST=$DB_HOST -e DB_USER=$DB_USER -e DB_PASSWORD=$DB_PASSWORD -e DB_NAME=$DB_NAME -e JWT_SECRET=$JWT_SECRET --restart unless-stopped $ECR_REGISTRY/fooddash/user-service:$IMAGE_TAG',
    'sudo docker run -d --name fooddash-restaurant -p 3002:3002 -e PORT=3002 -e DB_HOST=$DB_HOST -e DB_USER=$DB_USER -e DB_PASSWORD=$DB_PASSWORD -e DB_NAME=$DB_NAME -e JWT_SECRET=$JWT_SECRET --restart unless-stopped $ECR_REGISTRY/fooddash/restaurant-service:$IMAGE_TAG',
    'sudo docker run -d --name fooddash-order      -p 3003:3003 -e PORT=3003 -e DB_HOST=$DB_HOST -e DB_USER=$DB_USER -e DB_PASSWORD=$DB_PASSWORD -e DB_NAME=$DB_NAME -e JWT_SECRET=$JWT_SECRET --restart unless-stopped $ECR_REGISTRY/fooddash/order-service:$IMAGE_TAG',
    'sudo docker run -d --name fooddash-frontend   -p 3000:3000 --restart unless-stopped $ECR_REGISTRY/fooddash/frontend:$IMAGE_TAG',
    # Health checks
    'echo "Running health checks..."',
    'sleep 15',
    'curl -sf http://localhost:3001/health || (echo "user-service FAILED" && sudo docker logs fooddash-user --tail 30 && exit 1)',
    'curl -sf http://localhost:3002/health || (echo "restaurant-service FAILED" && sudo docker logs fooddash-restaurant --tail 30 && exit 1)',
    'curl -sf http://localhost:3003/health || (echo "order-service FAILED" && sudo docker logs fooddash-order --tail 30 && exit 1)',
    'curl -sf -o /dev/null http://localhost:3000 || (echo "frontend FAILED" && sudo docker logs fooddash-frontend --tail 30 && exit 1)',
    'sudo docker image prune -f',
    'echo "=== Deployment Complete ==="',
]

with open('/tmp/ssm-deploy.json', 'w') as f:
    json.dump({'commands': commands}, f, indent=2)

print('SSM JSON written to /tmp/ssm-deploy.json')
PYEOF

# ── 3. Send SSM command ───────────────────────────────────────────────────────
echo ">>> Sending SSM command to $INSTANCE_ID..."
COMMAND_ID=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids "$INSTANCE_ID" \
  --parameters file:///tmp/ssm-deploy.json \
  --query 'Command.CommandId' \
  --output text)

echo "SSM Command ID: $COMMAND_ID"

# ── 4. Poll for completion ────────────────────────────────────────────────────
STATUS="InProgress"
ATTEMPTS=0
MAX_ATTEMPTS=60

while [ "$STATUS" = "InProgress" ] || [ "$STATUS" = "Pending" ]; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ $ATTEMPTS -gt $MAX_ATTEMPTS ]; then
    echo "ERROR: Timed out after $((MAX_ATTEMPTS * 10)) seconds"
    exit 1
  fi
  sleep 10
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' \
    --output text)
  echo "  Status: $STATUS ($ATTEMPTS/$MAX_ATTEMPTS)"
done

# ── 5. Print output ───────────────────────────────────────────────────────────
echo ""
echo "=== Deployment Output ==="
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text

if [ "$STATUS" = "Success" ]; then
  echo ""
  echo "✓ Deployment complete — tag: $IMAGE_TAG"
else
  echo ""
  echo "✗ Deployment FAILED"
  echo "=== Error Output ==="
  aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'StandardErrorContent' \
    --output text
  exit 1
fi
