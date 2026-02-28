#!/usr/bin/env bash
# lib/projects.sh — discover and parse Claude Code projects

# get_projects: prints one JSON object per line, each representing a project
# Output fields: name, path, git_branch, last_session_iso, session_count, session_id
get_projects() {
  local projects_dir="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

  if [[ ! -d "$projects_dir" ]]; then
    echo "WARN: Claude projects dir not found: $projects_dir" >&2
    return 1
  fi

  for project_dir in "$projects_dir"/*/; do
    [[ -d "$project_dir" ]] || continue

    # Count session JSONL files
    local session_count
    session_count=$(find "$project_dir" -maxdepth 1 -name '*.jsonl' | wc -l | tr -d ' ')
    [[ "$session_count" -eq 0 ]] && continue

    # Most recent JSONL file (ls -t sorts by mtime descending)
    local latest_jsonl
    latest_jsonl=$(find "$project_dir" -maxdepth 1 -name '*.jsonl' -print0 \
      | xargs -0 ls -t 2>/dev/null | head -1)
    [[ -z "$latest_jsonl" ]] && continue

    # Last modified time as ISO 8601
    local last_session_iso
    last_session_iso=$(date -r "$latest_jsonl" -u +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null \
      || stat -c "%Y" "$latest_jsonl" | xargs -I{} date -d "@{}" -u +"%Y-%m-%dT%H:%M:%S.000Z")

    # Extract first record fields from latest JSONL
    local first_record
    first_record=$(head -1 "$latest_jsonl" 2>/dev/null)

    local project_path git_branch session_id slug
    project_path=$(echo "$first_record" | jq -r '.cwd // empty' 2>/dev/null)
    git_branch=$(echo "$first_record" | jq -r '.gitBranch // "main"' 2>/dev/null)
    session_id=$(echo "$first_record" | jq -r '.sessionId // empty' 2>/dev/null)
    slug=$(echo "$first_record" | jq -r '.slug // empty' 2>/dev/null)

    # Fallback: derive path from directory name (URL-decoded)
    if [[ -z "$project_path" ]]; then
      local dir_name
      dir_name=$(basename "$project_dir")
      project_path="/${dir_name//-//}"
    fi

    local project_name
    project_name=$(basename "$project_path")
    [[ -z "$project_name" ]] && project_name=$(basename "$project_dir")

    jq -n \
      --arg name "$project_name" \
      --arg path "$project_path" \
      --arg git_branch "$git_branch" \
      --arg last_session "$last_session_iso" \
      --argjson session_count "$session_count" \
      --arg session_id "$session_id" \
      --arg slug "$slug" \
      '{name:$name, path:$path, git_branch:$git_branch, last_session:$last_session,
        session_count:$session_count, session_id:$session_id, slug:$slug}'
  done
}
