#!/usr/bin/env bash
# lib/config.sh — load and validate configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

load_config() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi

  NOTION_TOKEN="${NOTION_TOKEN:-}"
  NOTION_PARENT_PAGE_ID="${NOTION_PARENT_PAGE_ID:-}"
  CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
  NOTION_DB_ID_FILE="$ROOT_DIR/.notion-db-id"

  if [[ -z "$NOTION_TOKEN" ]]; then
    echo "ERROR: NOTION_TOKEN is not set. Copy .env.example to .env and fill it in." >&2
    exit 1
  fi
  if [[ -z "$NOTION_PARENT_PAGE_ID" ]]; then
    echo "ERROR: NOTION_PARENT_PAGE_ID is not set." >&2
    exit 1
  fi
}
