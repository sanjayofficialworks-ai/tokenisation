#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
BUILD_DIR="${PROJECT_ROOT}/build"
ENV_FILE="${PROJECT_ROOT}/.env"

PORT="${PORT:-5000}"
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="${CHAIN_ID:-31337}"

log() { printf "\n\033[1;36m[run]\033[0m %s\n" "$*"; }
err() { printf "\n\033[1;31m[error]\033[0m %s\n" "$*" >&2; }

cleanup() {
  log "Shutting down Flask..."
  [[ -n "${FLASK_PID:-}" ]] && kill "${FLASK_PID}" 2>/dev/null || true
  wait >/dev/null 2>&1 || true
}
trap cleanup INT TERM

# Activate existing venv
if [[ -f "${PROJECT_ROOT}/.venv/bin/activate" ]]; then
  source "${PROJECT_ROOT}/.venv/bin/activate"
else
  err "No .venv found. Please create or activate manually."
  exit 1
fi

# Ensure env is loaded
if [[ -f "${ENV_FILE}" ]]; then
  set -a; source "${ENV_FILE}"; set +a
else
  err "Missing .env file. Please create it from .env.template."
  exit 1
fi

# Check RPC
log "Checking JSON-RPC at ${RPC_URL}..."
if ! curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
  "$RPC_URL" >/dev/null 2>&1; then
  err "RPC not responding at ${RPC_URL}. Start Anvil or your node separately."
  exit 1
fi

# Compile contract
log "Compiling contract..."
python "${SCRIPTS_DIR}/compile.py"

[[ -f "${BUILD_DIR}/BondSecurityToken.abi.json" ]] || { err "ABI not generated"; exit 1; }
[[ -f "${BUILD_DIR}/BondSecurityToken.bin" ]] || { err "Bytecode not generated"; exit 1; }

# Start Flask
log "Starting Flask server on :${PORT}"
python "${SCRIPTS_DIR}/server.py" >/tmp/flask.log 2>&1 &
FLASK_PID=$!

log "Waiting for API health..."
for _ in $(seq 1 60); do
  if curl -sSf "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then break; fi
  sleep 1
done

log "✅ Platform running!"
log "UI:     http://127.0.0.1:${PORT}"
log "Health: curl -s http://127.0.0.1:${PORT}/api/health | jq ."

tail -f /tmp/flask.log
