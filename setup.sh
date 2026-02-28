#!/usr/bin/env bash
# setup.sh — one-time setup: create Notion DB, install global Claude Code hooks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/notion.sh"

echo "=== Notion Claude Project Tracker Setup ==="

# 1. Load config
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "Copy .env.example to .env and fill in NOTION_TOKEN and NOTION_PARENT_PAGE_ID."
  exit 1
fi
load_config

# 2. Create Notion database
echo "Creating Notion database under page $NOTION_PARENT_PAGE_ID..."
DB_ID=$(create_database)
if [[ -z "$DB_ID" ]]; then
  echo "ERROR: Failed to create Notion database. Check your NOTION_TOKEN and NOTION_PARENT_PAGE_ID." >&2
  exit 1
fi
echo "$DB_ID" > "$NOTION_DB_ID_FILE"
echo "  ✓ Database created: $DB_ID"

# 3. Install Claude Code global hooks
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
HOOK_START="$SCRIPT_DIR/hooks/session-start.sh"
HOOK_STOP="$SCRIPT_DIR/hooks/session-stop.sh"

echo "Installing Claude Code hooks..."
# Use jq to merge hooks into existing settings.json
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  tmp=$(mktemp)
  jq --arg start "bash '$HOOK_START'" \
     --arg stop  "bash '$HOOK_STOP'" \
    '.hooks.SessionStart += [{"hooks":[{"type":"command","command":$start}]}] |
     .hooks.Stop        += [{"hooks":[{"type":"command","command":$stop}]}]' \
    "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
  echo "  ✓ Hooks installed in $CLAUDE_SETTINGS"
else
  echo "  WARN: ~/.claude/settings.json not found. Install Claude Code first." >&2
fi

# 4. Run initial sync
echo "Running initial sync..."
"$SCRIPT_DIR/bin/sync-notion"

echo ""
echo "Setup complete! Open your Notion page to see the Claude Projects Kanban."
echo "Run './bin/sync-notion' anytime to refresh all projects."
