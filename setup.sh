#!/usr/bin/env bash
# setup.sh — configure and launch the local Kanban server
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
echo "Starting Kanban server on port $KANBAN_PORT…"
exec "$ROOT_DIR/bin/serve"
