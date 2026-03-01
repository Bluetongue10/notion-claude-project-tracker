# Notion Claude Project Tracker

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Node ≥18](https://img.shields.io/badge/node-%3E%3D18-brightgreen)](package.json)

A real-time dashboard that syncs your local Claude Code project sessions into a Notion Kanban board and a live browser UI with Board, Graph, and Cosmos views.

## Features

- **Board** — Kanban view of all projects: Active, Paused, Needs Review, Done
- **Graph** — Mermaid flowchart showing projects, git worktrees, and live agent teams with status-aware color coding (green = active, yellow = idle, grey = done) and model labels
- **Cosmos** — Animated galaxy view where each project is a planet; click a planet to orbit its satellites (agents)
- **Auto-sync** — Claude Code hooks flip project status to Active on session start and Paused on stop
- **Notion sync** — Full project metadata pushed to a Notion database for sharing and review

```
┌──────────┬────────┬──────────────┬──────┐
│  Active  │ Paused │ Needs Review │ Done │
├──────────┼────────┼──────────────┼──────┤
│ my-app   │ api    │ old-project  │ poc  │
│ website  │ lib    │              │      │
└──────────┴────────┴──────────────┴──────┘
```

## Prerequisites

- **macOS or Linux** with `bash` (≥ 3.2), `curl`, and `jq`
- **Node.js** ≥ 18
- **Claude Code** installed (`~/.claude/` directory exists)
- **Notion** account with an [integration token](https://www.notion.so/my-integrations) that has write access to your workspace
- A Notion page to host the database (you'll need its page ID)

## Setup

### 1. Clone the repo

```bash
git clone <this-repo-url>
cd notion-claude-project-tracker
```

### 2. Configure credentials

```bash
cp .env.example .env
```

Edit `.env` and fill in:

```bash
NOTION_TOKEN=secret_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
NOTION_PARENT_PAGE_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**How to get these values:**
- `NOTION_TOKEN`: Create an integration at https://www.notion.so/my-integrations → copy the "Internal Integration Secret"
- `NOTION_PARENT_PAGE_ID`: Open your target Notion page → copy the 32-character ID from the URL (e.g. `https://notion.so/My-Page-abc123def456...` → ID is `abc123def456...`)
- Make sure to **share the Notion page** with your integration (click "Share" → invite the integration)

### 3. Run setup

```bash
bash setup.sh
```

This will:
1. Validate your environment variables and Node.js installation
2. Create the "Claude Projects" Kanban database in Notion
3. Start the local Kanban server on port 7842

Open http://localhost:7842 to see your dashboard.

## Daily Usage

### Automatic (hooks)

Register the hooks in `~/.claude/settings.json` so Claude Code fires them automatically:

```json
{
  "hooks": {
    "SessionStart": [{ "type": "command", "command": "bash /path/to/hooks/session-start.sh" }],
    "Stop":         [{ "type": "command", "command": "bash /path/to/hooks/session-stop.sh"   }]
  }
}
```

Once registered:
- **Session starts** → card flips to **Active**
- **Session ends/stops** → card flips to **Paused**

### Manual sync

Run a full rescan at any time:

```bash
./bin/sync-notion
```

### Marking projects as "Needs Review" or "Done"

These statuses are set **manually in Notion** — click the Status field on any card. `sync-notion` only sets Active/Paused based on session activity.

## Development

```bash
# Start the server
npm start          # or: node lib/server.js

# Run tests
npm test           # or: node tests/graph.test.js
```

## Project Structure

```
notion-claude-project-tracker/
├── bin/
│   ├── serve                # Start the local HTTP server
│   └── sync-notion          # Notion sync CLI (executable)
├── hooks/
│   ├── session-start.sh     # Claude Code SessionStart hook → Active
│   └── session-stop.sh      # Claude Code Stop hook → Paused
├── lib/
│   ├── config.sh            # Load .env, set defaults
│   ├── graph.js             # Mermaid DSL builder (Graph tab)
│   └── server.js            # HTTP server + SSE + API routes
├── tests/
│   └── graph.test.js        # Unit tests for graph.js
├── web/
│   └── index.html           # Browser UI (Board, Graph, Cosmos tabs)
├── setup.sh                 # One-time setup: validate env + start server
├── .env.example             # Credentials template
├── package.json
└── README.md
```

## Notion Database Schema

| Property       | Type   | Values / Notes                          |
|----------------|--------|-----------------------------------------|
| Name           | title  | Project directory name                  |
| Status         | select | Active, Paused, Needs Review, Done      |
| Local Path     | text   | Full filesystem path                    |
| Git Branch     | text   | From latest session's git branch        |
| Last Session   | date   | Most recent `.jsonl` file mtime         |
| Session Count  | number | Total `.jsonl` files in project dir     |
| Session ID     | text   | Latest session UUID (used by hooks)     |

## Uninstalling Hooks

Edit `~/.claude/settings.json` and remove the entries referencing `session-start.sh` and `session-stop.sh` from the `hooks.SessionStart` and `hooks.Stop` arrays.

## Troubleshooting

**`sync-notion` exits with "No Notion database found"**
Run `bash setup.sh` first to create the database and write `.notion-db-id`.

**Cards not updating on session start/stop**
Check that `~/.claude/settings.json` contains entries for both hooks. Re-run hook registration steps above.

**"ERROR: NOTION_TOKEN is not set"**
Make sure `.env` exists and contains your token. Run `cp .env.example .env` and fill it in.

**`jq` not found**
Install with `brew install jq` (macOS) or `apt install jq` (Ubuntu/Debian).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
