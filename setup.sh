#!/usr/bin/env bash
# setup.sh — configure and launch the local Kanban server
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate required environment variables and tools before anything else
if [[ ! -f "$ROOT_DIR/.env" ]]; then
  echo "ERROR: .env not found. Run: cp .env.example .env and fill it in." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$ROOT_DIR/.env" 2>/dev/null || true

if [[ -z "${NOTION_TOKEN:-}" ]]; then
  echo "ERROR: NOTION_TOKEN is not set. Run: cp .env.example .env and fill it in." >&2
  exit 1
fi
if [[ -z "${NOTION_PARENT_PAGE_ID:-}" ]]; then
  echo "ERROR: NOTION_PARENT_PAGE_ID is not set." >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js is required. Install from https://nodejs.org" >&2
  exit 1
fi

source "$ROOT_DIR/lib/config.sh"
load_config

echo "=== Claude Projects Kanban Setup ==="

# 1. Validate CLAUDE_PROJECTS_DIR
if [[ ! -d "$CLAUDE_PROJECTS_DIR" ]]; then
  echo "ERROR: Claude projects directory not found: $CLAUDE_PROJECTS_DIR" >&2
  echo "Set CLAUDE_PROJECTS_DIR in .env or ensure ~/.claude/projects exists." >&2
  exit 1
fi
echo "  ✓ Projects dir: $CLAUDE_PROJECTS_DIR"

# 2. Remove any previously-installed Notion hooks from ~/.claude/settings.json
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  if jq -e '.hooks.SessionStart // .hooks.Stop' "$CLAUDE_SETTINGS" > /dev/null 2>&1; then
    tmp=$(mktemp)
    jq 'del(.hooks.SessionStart) | del(.hooks.Stop)' "$CLAUDE_SETTINGS" > "$tmp" \
      && mv "$tmp" "$CLAUDE_SETTINGS"
    echo "  ✓ Removed old Notion hooks from $CLAUDE_SETTINGS"
  fi
fi

# 3. Start the Kanban server
echo ""
echo "Starting Kanban server on port ${KANBAN_PORT}..."
exec "$ROOT_DIR/bin/serve"
