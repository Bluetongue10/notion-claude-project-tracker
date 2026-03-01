#!/usr/bin/env bash
# Called by Claude Code on Stop. Sets project status → Paused.
source "$(dirname "$0")/../lib/config.sh"
load_config
PROJECT_PATH=$(jq -r '.cwd // empty' <<< "${CLAUDE_HOOK_INPUT:-{}}")
[[ -z "$PROJECT_PATH" ]] && exit 0
curl -sf -X POST "http://localhost:${KANBAN_PORT:-7842}/api/status" \
  -H 'Content-Type: application/json' \
  -d "{\"path\":\"$PROJECT_PATH\",\"status\":\"Paused\"}" >/dev/null 2>&1 || true
