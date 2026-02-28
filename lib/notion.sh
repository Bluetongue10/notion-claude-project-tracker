#!/usr/bin/env bash
# lib/notion.sh — Notion REST API v1 helpers

NOTION_API="https://api.notion.com/v1"

_notion_curl() {
  local method="$1" endpoint="$2" body="${3:-}"
  local args=(-s -X "$method"
    -H "Authorization: Bearer $NOTION_TOKEN"
    -H "Notion-Version: 2022-06-28"
    -H "Content-Type: application/json"
    "$NOTION_API/$endpoint")
  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

# create_database: creates the Kanban database under NOTION_PARENT_PAGE_ID
# Prints the new database ID on success
create_database() {
  local body
  body=$(jq -n --arg parent "$NOTION_PARENT_PAGE_ID" '{
    parent: {type:"page_id", page_id:$parent},
    title: [{type:"text", text:{content:"Claude Projects"}}],
    is_inline: false,
    properties: {
      "Name":          {title:{}},
      "Status":        {select:{options:[
                          {name:"Active",       color:"green"},
                          {name:"Paused",       color:"yellow"},
                          {name:"Needs Review", color:"orange"},
                          {name:"Done",         color:"gray"}]}},
      "Local Path":    {rich_text:{}},
      "Git Branch":    {rich_text:{}},
      "Last Session":  {date:{}},
      "Session Count": {number:{format:"number"}},
      "Session ID":    {rich_text:{}}
    }
  }')
  local resp
  resp=$(_notion_curl POST "databases" "$body")
  echo "$resp" | jq -r '.id // empty'
}

# find_page_by_path: query DB for a page matching Local Path
# Returns page ID or empty
find_page_by_path() {
  local db_id="$1" path="$2"
  local body
  body=$(jq -n --arg path "$path" '{
    filter:{property:"Local Path", rich_text:{equals:$path}}
  }')
  local resp
  resp=$(_notion_curl POST "databases/$db_id/query" "$body")
  echo "$resp" | jq -r '.results[0].id // empty'
}

# upsert_project: create or update a Notion card for a project
# Args: db_id, name, path, status, git_branch, last_session, session_count, session_id
upsert_project() {
  local db_id="$1" name="$2" path="$3" status="$4"
  local git_branch="$5" last_session="$6" session_count="$7" session_id="$8"

  local existing_id
  existing_id=$(find_page_by_path "$db_id" "$path")

  local props
  props=$(jq -n \
    --arg name "$name" \
    --arg status "$status" \
    --arg path "$path" \
    --arg branch "$git_branch" \
    --arg last_session "$last_session" \
    --argjson count "$session_count" \
    --arg sid "$session_id" \
    '{
      "Name":          {title:[{text:{content:$name}}]},
      "Status":        {select:{name:$status}},
      "Local Path":    {rich_text:[{text:{content:$path}}]},
      "Git Branch":    {rich_text:[{text:{content:$branch}}]},
      "Last Session":  {date:{start:$last_session}},
      "Session Count": {number:$count},
      "Session ID":    {rich_text:[{text:{content:$sid}}]}
    }')

  if [[ -n "$existing_id" ]]; then
    _notion_curl PATCH "pages/$existing_id" "{\"properties\":$props}" | jq -r '.id // empty'
  else
    local body
    body=$(jq -n --arg db_id "$db_id" --argjson props "$props" \
      '{parent:{database_id:$db_id}, properties:$props}')
    _notion_curl POST "pages" "$body" | jq -r '.id // empty'
  fi
}

# update_status_by_session: update just the Status field on a page by Session ID
update_status_by_session() {
  local db_id="$1" session_id="$2" status="$3"
  local body
  body=$(jq -n --arg sid "$session_id" '{
    filter:{property:"Session ID", rich_text:{equals:$sid}}
  }')
  local page_id
  page_id=$(_notion_curl POST "databases/$db_id/query" "$body" | jq -r '.results[0].id // empty')
  [[ -z "$page_id" ]] && return 0
  _notion_curl PATCH "pages/$page_id" \
    "{\"properties\":{\"Status\":{\"select\":{\"name\":\"$status\"}}}}" > /dev/null
}
