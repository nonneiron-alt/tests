#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
echo "=== kto.ty — one-click deploy to Cloudflare ==="
if ! command -v node >/dev/null; then echo "Node.js not found"; exit 1; fi
node_major=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$node_major" -lt 22 ]; then echo "Need Node.js 22+, got $(node --version)"; exit 1; fi
echo "[1/4] npm ci..."
npm ci
read -rp "Groq API key (gsk_...): " GROQ_API_KEY
read -rp "Cloudflare API Token (cfat_...): " CLOUDFLARE_API_TOKEN
read -rp "Cloudflare Account ID: " CLOUDFLARE_ACCOUNT_ID
read -rp "Worker name (Enter = kto-ty-quiz): " KTO_WORKER_NAME
KTO_WORKER_NAME="${KTO_WORKER_NAME:-kto-ty-quiz}"
export GROQ_API_KEY CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID KTO_WORKER_NAME CI=true
echo "[2/4] Deploying..."
npm run deploy:setup
echo "[3/4] Done. Open *.workers.dev link above."
