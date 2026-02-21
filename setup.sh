#!/bin/bash

# ==============================================================================
# Automated VPS Deployment Setup Script
# Works locally on the VPS or remotely via SSH
# ==============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}  Automated VPS Deployment Setup (React + FastAPI)  ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# --- 1. Gather Configuration ---

read -p "Project Name (e.g., myproject): " PROJECT_NAME
read -p "VPS SSH Username (e.g., ubuntu, root): " VPS_USER
read -p "VPS IP or Domain (e.g., 192.168.1.100): " VPS_HOST
read -p "VPS SSH Port [22]: " VPS_PORT
VPS_PORT=${VPS_PORT:-22}
read -p "Discord Webhook URL for Notifications (leave blank to disable): " DISCORD_WEBHOOK_URL
read -p "Frontend Directory inside Monorepo [frontend]: " FRONTEND_DIR_NAME
FRONTEND_DIR_NAME=${FRONTEND_DIR_NAME:-frontend}
read -p "Backend Directory inside Monorepo [backend]: " BACKEND_DIR_NAME
BACKEND_DIR_NAME=${BACKEND_DIR_NAME:-backend}

# Nginx / PM2 specific
read -p "PM2 Service Name for Backend (Uvicorn) [$PROJECT_NAME-backend]: " BACKEND_SERVICE_NAME
BACKEND_SERVICE_NAME=${BACKEND_SERVICE_NAME:-$PROJECT_NAME-backend}
read -p "Number of releases to keep for rollback [5]: " MAX_RELEASES
MAX_RELEASES=${MAX_RELEASES:-5}

echo ""
echo -e "${YELLOW}Where do you want to run this setup?${NC}"
echo "1) Locally (I am currently SSH'd into the VPS)"
echo "2) Remotely (Connect via SSH and set everything up automatically)"
read -p "Choice (1 or 2): " DEPLOY_MODE

# --- 2. Define the Remote Execution Block ---

# This variable contains the script that will actually run on the VPS
read -r -d '' REMOTE_SCRIPT << 'EOF' || true
#!/bin/bash
set -e

PROJECT_NAME="${PROJECT_NAME}"
VPS_USER="${VPS_USER}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"
FRONTEND_DIR_NAME="${FRONTEND_DIR_NAME}"
BACKEND_DIR_NAME="${BACKEND_DIR_NAME}"
BACKEND_SERVICE_NAME="${BACKEND_SERVICE_NAME}"
MAX_RELEASES="${MAX_RELEASES}"

# Set up paths
if [ "$VPS_USER" = "root" ]; then
    USER_HOME="/root"
else
    USER_HOME="/home/$VPS_USER"
fi

BASE_DIR="$USER_HOME/$PROJECT_NAME"
REPO_DIR="$BASE_DIR/repo.git"

echo "Creating directory structure at $BASE_DIR..."

mkdir -p "$BASE_DIR/releases"
mkdir -p "$BASE_DIR/secrets/frontend"
mkdir -p "$BASE_DIR/secrets/backend"
mkdir -p "$BASE_DIR/logs"

# Initialize bare git repo
if [ ! -d "$REPO_DIR" ]; then
    echo "Initializing bare git repository..."
    git init --bare "$REPO_DIR"
else
    echo "Bare git repository already exists."
fi

# Write the post-receive hook
cat << 'HOOK_EOF' > "$REPO_DIR/hooks/post-receive"
__POST_RECEIVE_HOOK_CONTENT__
HOOK_EOF

chmod +x "$REPO_DIR/hooks/post-receive"

# Write the rollback script
cat << 'ROLLBACK_EOF' > "$BASE_DIR/rollback.sh"
__ROLLBACK_SCRIPT_CONTENT__
ROLLBACK_EOF

chmod +x "$BASE_DIR/rollback.sh"

echo "Setup completed successfully on the server."
EOF

# --- 3. Read Templates from Files ---
# Ensure the template files exist in the same directory as this script.

SCRIPT_DIR=$(dirname "$0")

if [ ! -f "$SCRIPT_DIR/post-receive.template" ] || [ ! -f "$SCRIPT_DIR/rollback.template" ]; then
    echo -e "${RED}Error: post-receive.template or rollback.template not found in $SCRIPT_DIR${NC}"
    echo "Please ensure all 3 files (setup.sh, post-receive.template, rollback.template) are in the same folder."
    exit 1
fi

HOOK_CONTENT=$(cat "$SCRIPT_DIR/post-receive.template")
ROLLBACK_CONTENT=$(cat "$SCRIPT_DIR/rollback.template")

# Inject actual templates into the remote script string
REMOTE_SCRIPT="${REMOTE_SCRIPT/__POST_RECEIVE_HOOK_CONTENT__/"$HOOK_CONTENT"}"
REMOTE_SCRIPT="${REMOTE_SCRIPT/__ROLLBACK_SCRIPT_CONTENT__/"$ROLLBACK_CONTENT"}"

# --- 4. Execute ---

echo ""
if [ "$DEPLOY_MODE" == "1" ]; then
    echo -e "${GREEN}Running setup locally...${NC}"
    # Export variables so the heredoc inside bash -c can use them (though they are already templated)
    export PROJECT_NAME VPS_USER DISCORD_WEBHOOK_URL FRONTEND_DIR_NAME BACKEND_DIR_NAME BACKEND_SERVICE_NAME MAX_RELEASES
    bash -c "$REMOTE_SCRIPT"
elif [ "$DEPLOY_MODE" == "2" ]; then
    echo -e "${GREEN}Connecting to $VPS_USER@$VPS_HOST:$VPS_PORT and running setup...${NC}"
    ssh -p "$VPS_PORT" "$VPS_USER@$VPS_HOST" "bash -s" <<< "$REMOTE_SCRIPT"
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi

# --- 5. Instructions ---

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${GREEN}SUCCESS! The VPS is fully prepared.${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. On your local machine, inside your project folder, run:"
echo -e "   ${GREEN}git remote add production ssh://$VPS_USER@$VPS_HOST:$VPS_PORT/home/$VPS_USER/$PROJECT_NAME/repo.git${NC}"
echo "   (If using root, the path is /root/$PROJECT_NAME/repo.git)"
echo ""
echo -e "2. ${RED}IMPORTANT!${NC} SSH into the VPS and manually create your .env files:"
echo "   nano /home/$VPS_USER/$PROJECT_NAME/secrets/frontend/.env"
echo "   nano /home/$VPS_USER/$PROJECT_NAME/secrets/backend/.env"
echo ""
echo "3. Push your code to deploy!"
echo -e "   ${GREEN}git push production main${NC}"
echo ""
echo "4. PM2 / Nginx First-Time Setup (if you haven't already):"
echo "   - Ensure Nginx is pointing to /home/$VPS_USER/$PROJECT_NAME/production/$FRONTEND_DIR_NAME/dist"
echo "   - Start your PM2 backend once manually to save it:"
echo "     cd /home/$VPS_USER/$PROJECT_NAME/production/$BACKEND_DIR_NAME"
echo "     pm2 start \"uvicorn main:app --host 0.0.0.0 --port 8000\" --name $BACKEND_SERVICE_NAME"
echo "     pm2 save"
echo ""
