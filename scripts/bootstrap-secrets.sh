#!/usr/bin/env bash
# Create the local secret files and .env this stack mounts, so that no
# credentials need to be committed to Git. Re-running keeps existing values.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p secrets

# <file name> <description>; values are generated with openssl rand -hex 32.
random_secrets=(
  "headplane_cookie_secret:Headplane session cookie signing key"
  "headplane_oidc_client_secret:Headplane OIDC client secret (matches DEX_HEADPLANE_CLIENT_SECRET)"
  "headscale_oidc_client_secret:Headscale OIDC client secret (matches DEX_HEADSCALE_CLIENT_SECRET)"
)

for entry in "${random_secrets[@]}"; do
  file="secrets/${entry%%:*}"
  if [ -f "$file" ]; then
    echo "keep  $file"
  else
    openssl rand -hex 32 >"$file"
    chmod 600 "$file"
    echo "create $file"
  fi
done

# The Headscale API key cannot be generated offline: issue it with
#   docker exec headscale headscale apikeys create
# and put it here.
if [ ! -f secrets/headplane_headscale_api_key ]; then
  printf '' >secrets/headplane_headscale_api_key
  chmod 600 secrets/headplane_headscale_api_key
  echo "create secrets/headplane_headscale_api_key (empty — fill it in)"
fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "create .env (fill in the DEX_* values)"
fi

cat <<'EOF'

Next steps:
  1. Put the Headscale API key in secrets/headplane_headscale_api_key
  2. Set the same client secrets in .env:
       DEX_HEADPLANE_CLIENT_SECRET = $(cat secrets/headplane_oidc_client_secret)
       DEX_HEADSCALE_CLIENT_SECRET = $(cat secrets/headscale_oidc_client_secret)
  3. Generate the Dex user hashes (see .env.example) and fill DEX_*_PASSWORD_HASH
  4. sudo sh -c 'echo "127.0.0.1 dex.local" >> /etc/hosts'
  5. docker compose up -d
EOF
