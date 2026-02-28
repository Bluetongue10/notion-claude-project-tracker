#!/usr/bin/env bash
# hooks/session-start.sh — fired by Claude Code on SessionStart
# Updates or creates the project card in Notion with status "Active"

TRACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$TRACKER_DIR/lib/config.sh"
source "$TRACKER_DIR/lib/notion.sh"

load_config 2>/dev/null || exit 0
[[ -f "$NOTION_DB_ID_FILE" ]] || exit 0
DB_ID=$(cat "$NOTION_DB_ID_FILE")

SESSION_ID="${CLAUDE_SESSION_ID:-}"
CWD="${CLAUDE_CWD:-$PWD}"
GIT_BRANCH="${CLAUDE_GIT_BRANCH:-$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
PROJECT_NAME=$(basename "$CWD")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Try to update existing card by session ID first
if [[ -n "$SESSION_ID" ]]; then
  update_status_by_session "$DB_ID" "$SESSION_ID" "Active" 2>/dev/null && exit 0
fi

# Otherwise upsert (create or update by path)
upsert_project "$DB_ID" "$PROJECT_NAME" "$CWD" "Active" \
  "$GIT_BRANCH" "$NOW" "1" "${SESSION_ID:-}" > /dev/null
