#!/usr/bin/env bash
set -euo pipefail

OPTIONS=/data/options.json
DATA=/data
SECRETS_FILE=/data/.inbox-zero-secrets.env
ENV_FILE=/data/.env
EXTRA_ENV_FILE=/data/extra.env
COMPOSE_FILE=/app/compose.yaml
PROJECT=inbox-zero-ha

# The add-on talks to the host Docker daemon (mounted by the supervisor).
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/docker.sock}"

log() { echo "[inbox-zero] $*"; }

# ---------------------------------------------------------------------------
# Read add-on configuration
# ---------------------------------------------------------------------------
DOMAIN=$(jq -r '.domain // empty' "$OPTIONS")
HTTP_PORT=$(jq -r '.http_port // 3000' "$OPTIONS")
APP_RELEASE=$(jq -r '.app_release // "latest"' "$OPTIONS")
GOOGLE_CLIENT_ID=$(jq -r '.google_client_id // empty' "$OPTIONS")
GOOGLE_CLIENT_SECRET=$(jq -r '.google_client_secret // empty' "$OPTIONS")
GOOGLE_PUBSUB_TOPIC_NAME=$(jq -r '.google_pubsub_topic_name // empty' "$OPTIONS")
MICROSOFT_CLIENT_ID=$(jq -r '.microsoft_client_id // empty' "$OPTIONS")
MICROSOFT_CLIENT_SECRET=$(jq -r '.microsoft_client_secret // empty' "$OPTIONS")
MICROSOFT_TENANT_ID=$(jq -r '.microsoft_tenant_id // "common"' "$OPTIONS")
LLM_API_KEY=$(jq -r '.llm_api_key // empty' "$OPTIONS")
DEFAULT_LLMS=$(jq -r '.default_llms // "anthropic:claude-sonnet-4-6"' "$OPTIONS")
AUTH_ALLOWED_EMAILS=$(jq -r '.auth_allowed_emails // empty' "$OPTIONS")
BYPASS_PREMIUM=$(jq -r '.bypass_premium_checks // true' "$OPTIONS")

if [ -z "$DOMAIN" ]; then
    log "ERROR: 'domain' is required. Set it in the add-on configuration and restart."
    exit 1
fi

# OAuth requires HTTPS. The add-on publishes plain HTTP on http_port; front it
# with a reverse proxy that terminates TLS at https://<domain>.
NEXT_PUBLIC_BASE_URL="https://$DOMAIN"

# The web app requires Google OAuth values (non-empty). When the user only
# configures Microsoft, the upstream docs recommend the placeholder "skipped".
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-skipped}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-skipped}"
GOOGLE_PUBSUB_TOPIC_NAME="${GOOGLE_PUBSUB_TOPIC_NAME:-projects/inbox-zero/topics/unset}"

# ---------------------------------------------------------------------------
# Resolve the host path of the add-on's /data directory so the sibling
# containers can bind-mount it (keeps all data inside HA add-on backups).
# ---------------------------------------------------------------------------
resolve_data_dir() {
    if command -v docker >/dev/null 2>&1; then
        local ctn src
        ctn=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "_${HOSTNAME:-inbox-zero}\$" | head -n 1)
        if [ -n "$ctn" ]; then
            src=$(docker inspect "$ctn" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
            if [ -n "$src" ]; then
                echo "$src"
                return
            fi
        fi
    fi
    local fsrc sub
    fsrc=$(findmnt -n -o SOURCE -T "$DATA" 2>/dev/null || true)
    case "$fsrc" in
        *"["*"]")
            sub="${fsrc#*\[}"; sub="${sub%]}"
            echo "/mnt/data$sub"
            ;;
        "")
            ;;
        *)
            echo "$fsrc"
            ;;
    esac
}

if ! docker info >/dev/null 2>&1; then
    log "ERROR: cannot reach the host Docker daemon."
    log "       In Home Assistant, open Settings → Add-ons → Inbox Zero and turn"
    log "       OFF 'Protection mode', then start the add-on again."
    exit 1
fi

DATA_DIR=$(resolve_data_dir)
if [ -z "$DATA_DIR" ]; then
    log "ERROR: could not resolve host path of $DATA"
    exit 1
fi
log "Data directory on host: $DATA_DIR"

# ---------------------------------------------------------------------------
# Load or generate persisted secrets (kept on the HA host, never in this repo)
# ---------------------------------------------------------------------------
if [ -f "$SECRETS_FILE" ]; then
    set -a
    . "$SECRETS_FILE"
    set +a
fi
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
AUTH_SECRET="${AUTH_SECRET:-$(openssl rand -hex 32)}"
EMAIL_ENCRYPT_SECRET="${EMAIL_ENCRYPT_SECRET:-$(openssl rand -hex 32)}"
EMAIL_ENCRYPT_SALT="${EMAIL_ENCRYPT_SALT:-$(openssl rand -hex 16)}"
INTERNAL_API_KEY="${INTERNAL_API_KEY:-$(openssl rand -hex 32)}"
API_KEY_SALT="${API_KEY_SALT:-$(openssl rand -hex 32)}"
CRON_SECRET="${CRON_SECRET:-$(openssl rand -hex 32)}"
UPSTASH_REDIS_TOKEN="${UPSTASH_REDIS_TOKEN:-$(openssl rand -hex 32)}"
GOOGLE_PUBSUB_VERIFICATION_TOKEN="${GOOGLE_PUBSUB_VERIFICATION_TOKEN:-$(openssl rand -hex 32)}"
MICROSOFT_WEBHOOK_CLIENT_STATE="${MICROSOFT_WEBHOOK_CLIENT_STATE:-$(openssl rand -hex 32)}"

cat > "$SECRETS_FILE" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
AUTH_SECRET=$AUTH_SECRET
EMAIL_ENCRYPT_SECRET=$EMAIL_ENCRYPT_SECRET
EMAIL_ENCRYPT_SALT=$EMAIL_ENCRYPT_SALT
INTERNAL_API_KEY=$INTERNAL_API_KEY
API_KEY_SALT=$API_KEY_SALT
CRON_SECRET=$CRON_SECRET
UPSTASH_REDIS_TOKEN=$UPSTASH_REDIS_TOKEN
GOOGLE_PUBSUB_VERIFICATION_TOKEN=$GOOGLE_PUBSUB_VERIFICATION_TOKEN
MICROSOFT_WEBHOOK_CLIENT_STATE=$MICROSOFT_WEBHOOK_CLIENT_STATE
EOF
chmod 600 "$SECRETS_FILE"

# ---------------------------------------------------------------------------
# Write the Compose .env file
# ---------------------------------------------------------------------------
cat > "$ENV_FILE" <<EOF
NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL
NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS=$BYPASS_PREMIUM

DATABASE_URL="postgresql://postgres:$POSTGRES_PASSWORD@db:5432/inboxzero?schema=public"
DIRECT_URL="postgresql://postgres:$POSTGRES_PASSWORD@db:5432/inboxzero?schema=public"

UPSTASH_REDIS_TOKEN=$UPSTASH_REDIS_TOKEN
INTERNAL_API_KEY=$INTERNAL_API_KEY
API_KEY_SALT=$API_KEY_SALT
CRON_SECRET=$CRON_SECRET
AUTH_SECRET=$AUTH_SECRET
EMAIL_ENCRYPT_SECRET=$EMAIL_ENCRYPT_SECRET
EMAIL_ENCRYPT_SALT=$EMAIL_ENCRYPT_SALT

GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET
GOOGLE_PUBSUB_TOPIC_NAME=$GOOGLE_PUBSUB_TOPIC_NAME
GOOGLE_PUBSUB_VERIFICATION_TOKEN=$GOOGLE_PUBSUB_VERIFICATION_TOKEN
MICROSOFT_CLIENT_ID=$MICROSOFT_CLIENT_ID
MICROSOFT_CLIENT_SECRET=$MICROSOFT_CLIENT_SECRET
MICROSOFT_TENANT_ID=$MICROSOFT_TENANT_ID
MICROSOFT_WEBHOOK_CLIENT_STATE=$MICROSOFT_WEBHOOK_CLIENT_STATE

AUTH_ALLOWED_EMAILS=$AUTH_ALLOWED_EMAILS

DEFAULT_LLMS=$DEFAULT_LLMS
ECONOMY_LLMS=anthropic:claude-haiku-4-5-20251001
CHAT_LLMS=anthropic:claude-haiku-4-5-20251001
NANO_LLMS=anthropic:claude-haiku-4-5-20251001
DRAFT_LLMS=anthropic:claude-sonnet-4-6
ANTHROPIC_API_KEY=$LLM_API_KEY

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
APP_RELEASE=$APP_RELEASE
HTTP_PORT=$HTTP_PORT
DATA_DIR=$DATA_DIR
EOF
chmod 600 "$ENV_FILE"

# ---------------------------------------------------------------------------
# Optional extra environment variables (KEY=VALUE), appended to the containers
# ---------------------------------------------------------------------------
: > "$EXTRA_ENV_FILE"
jq -r '.extra_env // [] | .[]' "$OPTIONS" >> "$EXTRA_ENV_FILE" || true
chmod 600 "$EXTRA_ENV_FILE"

# ---------------------------------------------------------------------------
# Start / manage the stack
# ---------------------------------------------------------------------------
compose() {
    docker compose -p "$PROJECT" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

cleanup() {
    log "Stopping Inbox Zero stack..."
    compose down --remove-orphans || true
    exit 0
}
trap cleanup TERM INT

log "Pulling Inbox Zero images (${APP_RELEASE})..."
compose pull

log "Starting Inbox Zero stack..."
compose up -d

log "Inbox Zero is starting at $NEXT_PUBLIC_BASE_URL (port $HTTP_PORT)"
log "Streaming container logs..."
compose logs -f --no-color --tail=50
