#!/usr/bin/env bash
# hooks/session-stop.sh — fired by Claude Code on Stop
# Sets the project card status to "Paused"

TRACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
source "$TRACKER_DIR/lib/config.sh"
source "$TRACKER_DIR/lib/notion.sh"

load_config 2>/dev/null || exit 0
[[ -f "$NOTION_DB_ID_FILE" ]] || exit 0
DB_ID=$(cat "$NOTION_DB_ID_FILE")

SESSION_ID="${CLAUDE_SESSION_ID:-}"
[[ -z "$SESSION_ID" ]] && exit 0

update_status_by_session "$DB_ID" "$SESSION_ID" "Paused" 2>/dev/null || true
