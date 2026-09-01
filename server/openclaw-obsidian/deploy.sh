#!/usr/bin/env bash
set -euo pipefail

# Deploy the overlay from an OpenClaw repository checkout. The official
# OpenClaw setup/onboarding remains responsible for the Gateway image,
# credentials, and its base docker-compose.yml.

bundle_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
openclaw_dir="${OPENCLAW_DIR:-$(pwd)}"
project_dir="${AI_STUDY_PROJECT_DIR:-$(cd "$bundle_dir/../.." && pwd)}"
user_id="${OBSIDIAN_USER_ID:-1}"
vault_path="${AI_STUDY_OBSIDIAN_VAULT_HOST_PATH:-$project_dir/server/data/obsidian-vault/$user_id}"

if [[ ! -f "$openclaw_dir/docker-compose.yml" ]]; then
  echo "OpenClaw docker-compose.yml was not found in: $openclaw_dir" >&2
  echo "Set OPENCLAW_DIR to the official OpenClaw repository root." >&2
  exit 1
fi

mkdir -p "$vault_path"
if [[ ! -e "$vault_path/AGENTS.md" ]]; then
  cp "$bundle_dir/AGENTS.md" "$vault_path/AGENTS.md"
fi

export AI_STUDY_OBSIDIAN_VAULT_HOST_PATH="$vault_path"
export OPENCLAW_TZ="${OPENCLAW_TZ:-Asia/Shanghai}"

compose=(docker compose
  -f "$openclaw_dir/docker-compose.yml"
  -f "$bundle_dir/docker-compose.obsidian.yml")

echo "Validating OpenClaw + AILearningOS Compose configuration..."
(cd "$openclaw_dir" && "${compose[@]}" config --quiet)

echo "Starting OpenClaw Gateway with the mounted vault: $vault_path"
(cd "$openclaw_dir" && "${compose[@]}" up -d openclaw-gateway)

echo "Running the read-only health probe..."
(cd "$openclaw_dir" && "${compose[@]}" exec -T openclaw-gateway \
  sh -lc 'curl -fsS http://127.0.0.1:18789/healthz >/dev/null')

echo
echo "Gateway is running. Apply openclaw.obsidian.json5 to openclaw.json, then run:"
echo "  docker compose -f docker-compose.yml -f $bundle_dir/docker-compose.obsidian.yml run --rm openclaw-cli wiki init"
echo "  docker compose -f docker-compose.yml -f $bundle_dir/docker-compose.obsidian.yml run --rm openclaw-cli wiki compile"
echo "  docker compose -f docker-compose.yml -f $bundle_dir/docker-compose.obsidian.yml run --rm openclaw-cli wiki lint"
