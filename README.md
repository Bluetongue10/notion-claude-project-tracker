# Notion Claude Project Tracker

A Bash/zsh integration that syncs your local Claude Code project sessions into a Notion Kanban board — automatically, in real-time.

## Overview

Projects are auto-discovered from `~/.claude/projects/` JSONL session files and pushed to a Notion database with four status columns: **Active**, **Paused**, **Needs Review**, **Done**.

Status updates fire automatically via Claude Code global hooks on session start/stop, and a `sync-notion` CLI lets you do a full rescan at any time.

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
1. Create the "Claude Projects" Kanban database in Notion
2. Install session hooks into `~/.claude/settings.json`
3. Run an initial sync of all your existing projects

## Daily Usage

### Automatic (hooks)

Once set up, hooks fire automatically:
- **Session starts** → card flips to **Active**
- **Session ends/stops** → card flips to **Paused**

No action required.

### Manual sync

Run a full rescan at any time:

```bash
./bin/sync-notion
```

This recalculates status for all projects (Active if last session < 2 hours ago, Paused otherwise) and updates Notion.

### Marking projects as "Needs Review" or "Done"

These statuses are set **manually in Notion** — click the Status field on any card and select the desired column. `sync-notion` will not overwrite manually-set statuses (it only sets Active/Paused based on session activity).

> **Tip:** Use "Needs Review" when you want a collaborator to look at a project, and "Done" when work is complete.

## Project Structure

```
notion-claude-project-tracker/
├── bin/
│   └── sync-notion           # Main sync CLI (executable)
├── hooks/
│   ├── session-start.sh      # Claude Code SessionStart hook
│   └── session-stop.sh       # Claude Code SessionStop hook
├── lib/
│   ├── config.sh             # Load .env, validate vars
│   ├── notion.sh             # Notion API helpers (curl wrappers)
│   └── projects.sh           # Claude project discovery & parsing
├── setup.sh                  # One-time setup: create DB + install hooks
├── .env.example              # Template for credentials
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

To remove the hooks from Claude Code, edit `~/.claude/settings.json` and remove the entries referencing `session-start.sh` and `session-stop.sh` from the `hooks.SessionStart` and `hooks.Stop` arrays.

## Troubleshooting

**`sync-notion` exits with "No Notion database found"**
Run `bash setup.sh` first to create the database and write `.notion-db-id`.

**Cards not updating on session start/stop**
Check that `~/.claude/settings.json` contains entries for both hooks. Re-run `bash setup.sh` to reinstall.

**"ERROR: NOTION_TOKEN is not set"**
Make sure `.env` exists and contains your token. Run `cp .env.example .env` and fill it in.

**`jq` not found**
Install with `brew install jq` (macOS) or `apt install jq` (Ubuntu/Debian).
