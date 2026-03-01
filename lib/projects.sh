#!/usr/bin/env bash
# lib/projects.sh — discover and parse Claude Code projects

is_active() {
  local last_session="$1"
  local two_hours_ago
  two_hours_ago=$(date -u -v-2H +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null \
    || date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%S.000Z")
  [[ "$last_session" > "$two_hours_ago" ]]
}

get_worktrees() {
  local project_path="$1"
  [[ -d "$project_path" ]] || { echo ""; return 0; }
  local worktree_output
  worktree_output=$(git -C "$project_path" worktree list 2>/dev/null) || { echo ""; return 0; }
  local branches
  branches=$(echo "$worktree_output" | tail -n +2 | sed -n 's/.*\[\(.*\)\]$/\1/p')
  [[ -z "$branches" ]] && { echo ""; return 0; }
  echo "$branches" | paste -sd ',' - | sed 's/,/, /g'
}

get_agents() {
  local project_dir="$1" session_id="$2"
  [[ -z "$session_id" ]] && { echo ""; return 0; }
  local claude_root
  claude_root=$(dirname "$(dirname "$project_dir")")
  local team_name=""
  local session_jsonl="$project_dir/${session_id}.jsonl"
  if [[ -f "$session_jsonl" ]]; then
    team_name=$(head -1 "$session_jsonl" 2>/dev/null | jq -r '.teamName // empty' 2>/dev/null)
  fi
  if [[ -n "$team_name" ]]; then
    local team_config="$claude_root/teams/$team_name/config.json"
    if [[ -f "$team_config" ]]; then
      local members
      members=$(jq -r '.members[].name' "$team_config" 2>/dev/null | paste -sd ',' - | sed 's/,/, /g')
      [[ -n "$members" ]] && { echo "$members"; return 0; }
    fi
  fi
  local subagents_dir="$project_dir/$session_id/subagents"
  if [[ -d "$subagents_dir" ]]; then
    local agent_count
    agent_count=$(find "$subagents_dir" -maxdepth 1 -name 'agent-*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
    [[ "$agent_count" -gt 0 ]] && { echo "${agent_count} agent(s)"; return 0; }
  fi
  echo ""
}

# Returns a JSON array of agent objects: [{name, type, model, status}]
# status: "active" (in-progress task or recent file), "idle", "done"
get_agent_details() {
  local project_dir="$1" session_id="$2"
  [[ -z "$session_id" ]] && { echo "[]"; return 0; }
  local claude_root
  claude_root=$(dirname "$(dirname "$project_dir")")
  local team_name=""
  local session_jsonl="$project_dir/${session_id}.jsonl"
  if [[ -f "$session_jsonl" ]]; then
    team_name=$(head -1 "$session_jsonl" 2>/dev/null | jq -r '.teamName // empty' 2>/dev/null)
  fi

  if [[ -n "$team_name" ]]; then
    local team_config="$claude_root/teams/$team_name/config.json"
    local tasks_dir="$claude_root/tasks/$team_name"
    if [[ -f "$team_config" ]]; then
      # Build JSON array from team members
      jq -c '.members[]' "$team_config" 2>/dev/null | while IFS= read -r member; do
        local name type model agent_status
        name=$(echo "$member" | jq -r '.name')
        type=$(echo "$member" | jq -r '.agentType // "agent"')
        model=$(echo "$member" | jq -r '.model // ""')
        agent_status="idle"

        # Check tasks for in-progress work owned by this agent
        if [[ -d "$tasks_dir" ]]; then
          local in_progress
          in_progress=$(find "$tasks_dir" -name '*.json' -print0 2>/dev/null \
            | xargs -0 jq -r --arg n "$name" \
              'select(.status=="in_progress" and .owner==$n) | .subject' 2>/dev/null \
            | head -1)
          if [[ -n "$in_progress" ]]; then
            agent_status="active"
          else
            local has_done
            has_done=$(find "$tasks_dir" -name '*.json' -print0 2>/dev/null \
              | xargs -0 jq -r --arg n "$name" \
                'select(.status=="completed" and .owner==$n) | .subject' 2>/dev/null \
              | head -1)
            [[ -n "$has_done" ]] && agent_status="done"
          fi
        fi

        jq -cn \
          --arg name "$name" \
          --arg type "$type" \
          --arg model "$model" \
          --arg status "$agent_status" \
          '{name:$name,type:$type,model:$model,status:$status}'
      done | jq -s '.'
      return 0
    fi
  fi

  # Subagents: infer status from JSONL modification time
  local subagents_dir="$project_dir/$session_id/subagents"
  if [[ -d "$subagents_dir" ]]; then
    local now
    now=$(date +%s)
    find "$subagents_dir" -maxdepth 1 -name 'agent-*.jsonl' 2>/dev/null | sort | while IFS= read -r f; do
      local mtime diff agent_status
      mtime=$(stat -f "%m" "$f" 2>/dev/null || stat -c "%Y" "$f" 2>/dev/null)
      diff=$((now - mtime))
      if   [[ "$diff" -lt 300  ]]; then agent_status="active"
      elif [[ "$diff" -lt 7200 ]]; then agent_status="idle"
      else                               agent_status="done"
      fi
      local fname
      fname=$(basename "$f" .jsonl)
      jq -cn \
        --arg name "$fname" \
        --arg type "subagent" \
        --arg model "" \
        --arg status "$agent_status" \
        '{name:$name,type:$type,model:$model,status:$status}'
    done | jq -s '.'
    return 0
  fi

  echo "[]"
}

# get_projects: prints one JSON object per line, each representing a project
# Output fields: name, path, git_branch, last_session_iso, session_count, session_id, worktrees, agents
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

    local worktrees agents agent_details proj_status last_commit
    worktrees=$(get_worktrees "$project_path")
    agents=$(get_agents "$project_dir" "$session_id")
    agent_details=$(get_agent_details "$project_dir" "$session_id")
    is_active "$last_session_iso" && proj_status="Active" || proj_status="Paused"
    last_commit=$(git -C "$project_path" log -1 --pretty=%s 2>/dev/null || echo "")

    jq -cn \
      --arg name "$project_name" \
      --arg path "$project_path" \
      --arg git_branch "$git_branch" \
      --arg last_session "$last_session_iso" \
      --argjson session_count "$session_count" \
      --arg session_id "$session_id" \
      --arg slug "$slug" \
      --arg worktrees "$worktrees" \
      --arg agents "$agents" \
      --argjson agent_details "${agent_details:-[]}" \
      --arg status "$proj_status" \
      --arg project_dir "$project_dir" \
      --arg last_commit "$last_commit" \
      '{name:$name, path:$path, git_branch:$git_branch, last_session:$last_session,
        session_count:$session_count, session_id:$session_id, slug:$slug,
        worktrees:$worktrees, agents:$agents, agent_details:$agent_details,
        status:$status, project_dir:$project_dir, last_commit:$last_commit}'
  done
}
