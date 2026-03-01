# Graph Tab + Testing Agents — Design Document

**Date:** 2026-03-01
**Status:** Approved

---

## Goal

Add a live "Graph" tab to the Kanban board that visualises the relationships between
projects, git worktrees, and Claude agents using a Mermaid `flowchart LR` diagram.
Deploy 5 real testing agents across two repos (`notion-claude-project-tracker` and
`Xyris`) to generate genuine worktree and agent data for the diagram.

---

## Architecture

```
web/
  index.html        ← add Board | Graph tab toggle + #graph panel
  mermaid.min.js    ← downloaded once, served locally (no CDN at runtime)

lib/
  server.js         ← add GET /api/graph + generic static handler for web/*.js
  graph.js          ← new: builds Mermaid DSL from cache + git + team configs
```

No new SSE endpoints. The existing SSE stream triggers a re-fetch of `/api/graph`
and a Mermaid re-render whenever the cache updates.

---

## Data Pipeline (`lib/graph.js`)

Three passes, all synchronous, no shell-outs (pure Node + `fs`):

### Pass 1 — Enrich worktrees
For each project in the in-memory cache, call
`git worktree list --porcelain` via `execSync`. Parse output into:
```
{ path, head, branch }[]
```
The project root worktree (first entry) is the trunk node. Additional entries
become child worktree nodes.

### Pass 2 — Resolve agents → worktrees
For the most recent session with a `teamName`, read
`~/.claude/teams/{teamName}/config.json`. Each member's `cwd` is compared
against the worktree paths:
- exact match → agent placed on that worktree node
- no match → agent placed on the project root node

### Pass 3 — Emit Mermaid DSL
Output: `flowchart LR` with:

| Element | Mermaid construct |
|---|---|
| Project (Active) | `subgraph` with green accent via `classDef` |
| Project (Paused) | `subgraph` with orange accent |
| Trunk branch | `([branch-name])` (stadium shape) |
| Worktree | `["branch\nshort-path"]` (rectangle) |
| Team | `subgraph` |
| Agent | `["name"]` (rectangle) |
| Project → Worktree | `-->` solid arrow |
| Team-lead → Agent | `-->` solid arrow |
| Agent → Worktree | `-. working in .->` dotted arrow |

**Example output:**
```
flowchart LR
  subgraph proj_0 ["notion-claude-project-tracker · Active"]
    P_0(["main"])
    WT_0_0["feature/add-tests\n.claude/worktrees/..."]
    P_0 --> WT_0_0
  end

  subgraph team_0 ["team: my-team"]
    TL_0["team-lead"]
    A_0_0["researcher"]
    TL_0 --> A_0_0
  end

  A_0_0 -. working in .-> WT_0_0
```

---

## UI (`web/index.html`)

### Tab toggle
- Header gains a `Board | Graph` pill switcher, styled to match existing header
- Active tab: solid background, full-opacity text
- Inactive tab: ghost style, muted text

### Graph panel
- `<div id="graph">` sibling to `.board`, `display:none` when Board tab active
- On switch to Graph tab: `fetch('/api/graph')` → `mermaid.render()` → inject SVG
- On SSE `onmessage` while Graph is active: re-fetch + re-render
- Mermaid config:
  ```js
  mermaid.initialize({
    startOnLoad: false,
    theme: 'dark',
    themeVariables: {
      background:   '#0d1117',
      mainBkg:      '#161b22',
      nodeBorder:   '#30363d',
      lineColor:    '#7d8590',
      clusterBkg:   '#161b22',
      titleColor:   '#e6edf3',
      edgeLabelBackground: '#0d1117',
    }
  })
  ```

### Static file serving
`server.js` gains a handler: `GET /web/:filename` → serve from `web/` directory
(replaces the hardcoded `index.html` handler with a general one).

---

## Testing Agents

Deployed in parallel using `isolation: "worktree"` so each creates a real git worktree.

| Repo | Agent | Task | Branch |
|---|---|---|---|
| notion-claude-project-tracker | researcher | Write shell tests for `projects.sh` | `feature/add-tests` |
| notion-claude-project-tracker | writer | Rewrite README for web app | `feature/update-readme` |
| notion-claude-project-tracker | stylist | CSS polish for `web/index.html` | `feature/graph-styling` |
| Xyris | auditor | Audit and annotate `docs/plans/` | `feature/doc-audit` |
| Xyris | commenter | Add inline comments to core module | `feature/inline-comments` |

All 5 agents work concurrently. Their worktrees appear in `/api/graph` within 2s of
creation (via `fs.watch` debounce).

---

## Future — Phase C: Timeline/Swimlane Tab

A third `Timeline` tab deferred to a follow-up:
- Horizontal lanes per project
- Agent activity blocks positioned by `last_session` timestamp
- Brush/zoom for time navigation

---

## Verification

```bash
# 1. Syntax
node --check lib/graph.js lib/server.js

# 2. Graph DSL output
node -e "const g=require('./lib/graph'); console.log(g([]))"

# 3. Server
./bin/serve
curl http://localhost:7842/api/graph   # returns Mermaid DSL

# 4. Browser
# → click Graph tab, verify diagram renders
# → drag a card, switch to Graph, verify agent still shown on correct worktree
# → touch a .jsonl file, verify graph auto-refreshes within 2s

# 5. Testing agents
# → open Graph tab, verify 5 new worktree nodes appear as agents start
```
