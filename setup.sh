#!/usr/bin/env bash
# setup.sh — configure and launch the local Kanban server
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js is required. Install from https://nodejs.org" >&2
  exit 1
fi

# Load .env if present
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env" 2>/dev/null || true
fi

source "$ROOT_DIR/lib/config.sh"
load_config

echo "=== Claude Projects Kanban Setup ==="

# Validate CLAUDE_PROJECTS_DIR
if [[ ! -d "$CLAUDE_PROJECTS_DIR" ]]; then
  echo "ERROR: Claude projects directory not found: $CLAUDE_PROJECTS_DIR" >&2
  echo "Set CLAUDE_PROJECTS_DIR in .env or ensure ~/.claude/projects exists." >&2
  exit 1
fi
echo "  ✓ Projects dir: $CLAUDE_PROJECTS_DIR"

# Start the Kanban server
echo ""
echo "Starting Kanban server on port ${KANBAN_PORT}..."
exec "$ROOT_DIR/bin/serve"
