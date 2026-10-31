#!/bin/bash
# FoodDash Deploy Script
# Runs on GitHub Actions runner — fetches secrets here, passes values to EC2 via SSM
#
# Required env vars (set by GitHub Actions):
#   ECR_REGISTRY  - e.g. 926239637076.dkr.ecr.ap-south-2.amazonaws.com
#   IMAGE_TAG     - git commit SHA
#   AWS_REGION    - e.g. ap-south-2

set -euo pipefail

# ── 1. Find the SSM-managed EC2 instance ─────────────────────────────────────
echo ">>> Finding EC2 instance..."
INSTANCE_ID=$(aws ssm describe-instance-information \
  --filter "Key=tag:aws:autoscaling:groupName,Values=fooddash-asg" \
  --query 'InstanceInformationList[0].InstanceId' \
  --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  echo "ERROR: No SSM-managed EC2 instance found with tag Project=fooddash"
  exit 1
fi
echo "Found instance: $INSTANCE_ID"

# ── 2. Fetch secrets HERE on the GitHub runner ───────────────────────────────
# This avoids all JSON parsing complexity on the EC2 instance.
# The runner has AWS credentials and VPC access — fetch once, pass as values.
echo ">>> Fetching secrets from Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id fooddash/db-credentials \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

echo "Secret fetched, length: ${#SECRET_JSON} chars"

# Pass JSON as argument to avoid all pipe/stdin/echo formatting issues
DB_HOST=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['DB_HOST'])" "$SECRET_JSON")
DB_USER=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['DB_USER'])" "$SECRET_JSON")
DB_PASSWORD=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['DB_PASSWORD'])" "$SECRET_JSON")
DB_NAME=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['DB_NAME'])" "$SECRET_JSON")
JWT_SECRET=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['JWT_SECRET'])" "$SECRET_JSON")

echo "DB_HOST: $DB_HOST"
echo "DB_NAME: $DB_NAME"
echo "Secrets fetched successfully"

# Export so the Python heredoc can read them via os.environ
export DB_HOST DB_USER DB_PASSWORD DB_NAME JWT_SECRET

# ── 3. Generate the SSM command JSON ─────────────────────────────────────────
# All values are expanded HERE on the runner — EC2 receives plain strings.
# No variable expansion or JSON parsing happens on the EC2.
python3 - <<"PYEOF"
import json, os

reg      = os.environ['ECR_REGISTRY']
tag      = os.environ['IMAGE_TAG']
region   = os.environ['AWS_REGION']
db_host  = os.environ['DB_HOST']
db_user  = os.environ['DB_USER']
db_pass  = os.environ['DB_PASSWORD']
db_name  = os.environ['DB_NAME']
jwt      = os.environ['JWT_SECRET']

commands = [
    'set -e',
    'echo "=== FoodDash Deployment ==="',
    'echo "Tag: ' + tag + '"',
    # ECR login
    'aws ecr get-login-password --region ' + region + ' | sudo docker login --username AWS --password-stdin ' + reg,
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
    'sudo docker pull ' + reg + '/fooddash/user-service:' + tag,
    'sudo docker pull ' + reg + '/fooddash/restaurant-service:' + tag,
    'sudo docker pull ' + reg + '/fooddash/order-service:' + tag,
    'sudo docker pull ' + reg + '/fooddash/frontend:' + tag,
    # Start containers with host networking so they use EC2's network interface
    # This ensures RDS security group allows traffic (comes from EC2 IP not Docker bridge)
    'echo "Starting containers..."',
    'sudo docker run -d --name fooddash-user       --network host -e PORT=3001 -e DB_HOST=' + db_host + ' -e DB_USER=' + db_user + ' -e DB_PASSWORD=' + db_pass + ' -e DB_NAME=' + db_name + ' -e JWT_SECRET=' + jwt + ' --restart unless-stopped ' + reg + '/fooddash/user-service:' + tag,
    'sudo docker run -d --name fooddash-restaurant --network host -e PORT=3002 -e DB_HOST=' + db_host + ' -e DB_USER=' + db_user + ' -e DB_PASSWORD=' + db_pass + ' -e DB_NAME=' + db_name + ' -e JWT_SECRET=' + jwt + ' --restart unless-stopped ' + reg + '/fooddash/restaurant-service:' + tag,
    'sudo docker run -d --name fooddash-order      --network host -e PORT=3003 -e DB_HOST=' + db_host + ' -e DB_USER=' + db_user + ' -e DB_PASSWORD=' + db_pass + ' -e DB_NAME=' + db_name + ' -e JWT_SECRET=' + jwt + ' --restart unless-stopped ' + reg + '/fooddash/order-service:' + tag,
    'sudo docker run -d --name fooddash-frontend   --network host -e PORT=3000 --restart unless-stopped ' + reg + '/fooddash/frontend:' + tag,
    # Health checks with retries
    'echo "Running health checks..."',
    'sleep 20',
    'for svc_port in "3001:/health" "3002:/health" "3003:/health" "3000:/"; do port=${svc_port%%:*}; path=${svc_port##*:}; ok=0; for attempt in $(seq 1 5); do curl -sf http://localhost:$port$path && ok=1 && break || sleep 10; done; [ $ok -eq 1 ] || (echo "Service on port $port FAILED" && exit 1); done',
    'sudo docker image prune -f',
    'echo "=== Deployment Complete ==="',
]

with open('/tmp/ssm-deploy.json', 'w') as f:
    json.dump({'commands': commands}, f, indent=2)

print('SSM JSON written successfully')
PYEOF

# ── 5. Send SSM command ───────────────────────────────────────────────────────
echo ">>> Sending SSM command to $INSTANCE_ID..."
COMMAND_ID=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids "$INSTANCE_ID" \
  --parameters file:///tmp/ssm-deploy.json \
  --query 'Command.CommandId' \
  --output text)

echo "SSM Command ID: $COMMAND_ID"

# ── 6. Poll for completion ────────────────────────────────────────────────────
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

# ── 7. Print output ───────────────────────────────────────────────────────────
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
