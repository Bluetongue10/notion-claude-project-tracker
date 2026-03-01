# Graph Tab + Testing Agents Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a live "Graph" tab to the Kanban board showing project → worktree → agent relationships as a Mermaid `flowchart LR` diagram; deploy 5 real testing agents to generate genuine worktree data.

**Architecture:** `lib/graph.js` builds Mermaid DSL from the in-memory cache + `git worktree list --porcelain` + `~/.claude/teams/*/config.json`. `server.js` gets a `/api/graph` route + generic static handler for `web/*.js`. `web/index.html` gets a `Board | Graph` pill switcher; Mermaid renders entirely in-browser from locally-bundled `web/mermaid.min.js`. Testing agents are launched with `isolation: "worktree"` so real git worktrees appear immediately in the diagram.

**Tech Stack:** Node.js built-ins only, Mermaid v11 (downloaded once to `web/mermaid.min.js`), vanilla JS, bash

---

### Task 1: Download Mermaid and emit `project_dir` from `projects.sh`

**Files:**
- Create: `web/mermaid.min.js` (downloaded)
- Modify: `lib/projects.sh`
- Modify: `.gitignore`

**Step 1: Download Mermaid minified bundle**

```bash
curl -L -o web/mermaid.min.js \
  "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
ls -lh web/mermaid.min.js
```

Expected: file exists, size > 500KB

**Step 2: Add to .gitignore**

Add this line to `.gitignore`:
```
web/mermaid.min.js
```

**Step 3: Add `project_dir` field to `get_projects` output in `lib/projects.sh`**

In the `jq -cn` call at the bottom of `get_projects`, add `--arg project_dir "$project_dir"` and `project_dir:$project_dir` to the output object. The variable `$project_dir` is already in scope (it's the loop variable). Change the jq block from:

```bash
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
      --arg status "$proj_status" \
      '{name:$name, path:$path, git_branch:$git_branch, last_session:$last_session,
        session_count:$session_count, session_id:$session_id, slug:$slug,
        worktrees:$worktrees, agents:$agents, status:$status}'
```

To:

```bash
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
      --arg status "$proj_status" \
      --arg project_dir "$project_dir" \
      '{name:$name, path:$path, git_branch:$git_branch, last_session:$last_session,
        session_count:$session_count, session_id:$session_id, slug:$slug,
        worktrees:$worktrees, agents:$agents, status:$status, project_dir:$project_dir}'
```

**Step 4: Verify syntax**

```bash
bash -n lib/projects.sh && echo "syntax OK"
source lib/projects.sh && get_projects 2>/dev/null | grep '^{' | jq '{name, status, project_dir}' | head -12
```

Expected: each project object includes `"project_dir": "/Users/.../.claude/projects/-..."` (the directory under `~/.claude/projects/`)

**Step 5: Commit**

```bash
git add .gitignore lib/projects.sh
git commit -m "feat: emit project_dir field from get_projects; add mermaid to gitignore"
```

---

### Task 2: Create `lib/graph.js` — Mermaid DSL builder

**Files:**
- Create: `lib/graph.js`
- Create: `tests/graph.test.js`

**Step 1: Create `tests/` directory and write the failing test**

```bash
mkdir -p tests
```

Create `tests/graph.test.js`:

```js
'use strict'
const assert = require('assert')
const { buildGraph } = require('../lib/graph')

const mockProjects = [
  {
    name: 'my-project',
    path: '/tmp/my-project',
    git_branch: 'main',
    status: 'Active',
    session_count: 3,
    agents: '',
    worktrees: '',
    project_dir: '/tmp/fake-project-dir',
    _teamName: null,
  }
]

// Test 1: DSL starts with flowchart LR
{
  const dsl = buildGraph(mockProjects, { skipGit: true, skipTeams: true })
  assert(dsl.startsWith('flowchart LR'), 'missing flowchart LR header')
  assert(dsl.includes('my-project'), 'missing project name')
  assert(dsl.includes('main'), 'missing branch name')
  console.log('✓ basic DSL structure')
}

// Test 2: Empty projects → placeholder node
{
  const dsl = buildGraph([], { skipGit: true, skipTeams: true })
  assert(dsl.includes('flowchart LR'), 'empty: missing header')
  assert(dsl.includes('No projects'), 'empty: missing placeholder')
  console.log('✓ empty projects placeholder')
}

// Test 3: Active project gets active classDef applied
{
  const dsl = buildGraph(mockProjects, { skipGit: true, skipTeams: true })
  assert(dsl.includes(':::active'), 'missing :::active class on trunk node')
  console.log('✓ active class applied to trunk node')
}

// Test 4: Paused project gets paused class
{
  const paused = [{ ...mockProjects[0], status: 'Paused' }]
  const dsl = buildGraph(paused, { skipGit: true, skipTeams: true })
  assert(dsl.includes(':::paused'), 'missing :::paused class')
  console.log('✓ paused class applied')
}

// Test 5: classDef block always emitted
{
  const dsl = buildGraph(mockProjects, { skipGit: true, skipTeams: true })
  assert(dsl.includes('classDef active'), 'missing classDef active')
  assert(dsl.includes('classDef agent'), 'missing classDef agent')
  console.log('✓ classDef declarations present')
}

console.log('\nAll graph.js tests passed')
```

**Step 2: Run test to verify it fails**

```bash
node tests/graph.test.js
```

Expected: `Error: Cannot find module '../lib/graph'`

**Step 3: Create `lib/graph.js`**

```js
'use strict'

const { execSync } = require('child_process')
const fs = require('fs')
const path = require('path')
const { homedir } = require('os')

/**
 * Parse `git worktree list --porcelain` output into an array of
 * { path, head, branch } objects. First entry is always the main worktree.
 */
function getWorktrees(projectPath, { skipGit = false } = {}) {
  if (skipGit || !projectPath) return []
  try {
    const raw = execSync(
      `git -C ${JSON.stringify(projectPath)} worktree list --porcelain`,
      { timeout: 5000, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }
    )
    const worktrees = []
    let cur = {}
    for (const line of raw.split('\n')) {
      if (line.startsWith('worktree ')) {
        if (cur.path) worktrees.push(cur)
        cur = { path: line.slice(9).trim() }
      } else if (line.startsWith('branch ')) {
        cur.branch = line.slice(7).trim().replace('refs/heads/', '')
      } else if (line.startsWith('HEAD ')) {
        cur.head = line.slice(5).trim().slice(0, 7)
      }
    }
    if (cur.path) worktrees.push(cur)
    return worktrees
  } catch {
    return []
  }
}

/**
 * Read ~/.claude/teams/{teamName}/config.json.
 * Returns null if not found or unreadable.
 */
function getTeamConfig(teamName, { skipTeams = false } = {}) {
  if (skipTeams || !teamName) return null
  const configPath = path.join(homedir(), '.claude', 'teams', teamName, 'config.json')
  try {
    return JSON.parse(fs.readFileSync(configPath, 'utf8'))
  } catch {
    return null
  }
}

/**
 * Resolve the most recent teamName for a project by scanning its
 * ~/.claude/projects/{project_dir}/*.jsonl first lines.
 */
function resolveTeamName(proj, { skipTeams = false } = {}) {
  if (skipTeams || proj._teamName) return proj._teamName || null
  const projectDir = proj.project_dir
  if (!projectDir) return null
  try {
    const files = fs.readdirSync(projectDir)
      .filter(f => f.endsWith('.jsonl'))
      .map(f => ({ f, mtime: fs.statSync(path.join(projectDir, f)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime)
      .map(x => x.f)
    for (const f of files.slice(0, 5)) {
      try {
        const first = fs.readFileSync(path.join(projectDir, f), 'utf8').split('\n')[0]
        const rec = JSON.parse(first)
        if (rec.teamName) return rec.teamName
      } catch { /* skip malformed */ }
    }
  } catch { /* dir not found */ }
  return null
}

/**
 * Build a Mermaid flowchart LR DSL string from the projects array.
 *
 * @param {Array}  projects - from the server's in-memory cache
 * @param {object} opts     - { skipGit, skipTeams } for unit testing
 * @returns {string} Mermaid DSL
 */
function buildGraph(projects, opts = {}) {
  if (!projects || projects.length === 0) {
    return 'flowchart LR\n  N["No projects found"]'
  }

  const lines = [
    'flowchart LR',
    '  classDef active  stroke:#3fb950,stroke-width:2px,color:#3fb950',
    '  classDef paused  stroke:#e3b341,stroke-width:2px,color:#e3b341',
    '  classDef agent   fill:#161b22,stroke:#388bfd,color:#a5d6ff',
    '  classDef worktree fill:#161b22,stroke:#30363d,color:#e6edf3',
    '',
  ]

  for (let pi = 0; pi < projects.length; pi++) {
    const proj = projects[pi]
    const pid = `P${pi}`
    const statusClass = proj.status === 'Active' ? 'active' : 'paused'
    const label = `${proj.name} · ${proj.status}`

    // ── Project subgraph ──────────────────────────────────────────────────
    lines.push(`  subgraph ${pid}_grp ["${label}"]`)

    // Trunk node (main branch)
    const trunkId = `${pid}_trunk`
    const branch = proj.git_branch || 'main'
    lines.push(`    ${trunkId}(["${branch}"]):::${statusClass}`)

    // Worktrees (skip index 0 — that's the main worktree / trunk)
    const worktrees = getWorktrees(proj.path, opts)
    const wtNodes = []
    for (let wi = 1; wi < worktrees.length; wi++) {
      const wt = worktrees[wi]
      const wtId = `${pid}_wt${wi}`
      const wtBranch = wt.branch || 'detached'
      const shortPath = wt.path.split('/').slice(-3).join('/')
      lines.push(`    ${wtId}["${wtBranch}\\n…/${shortPath}"]:::worktree`)
      lines.push(`    ${trunkId} --> ${wtId}`)
      wtNodes.push({ id: wtId, wt })
    }

    lines.push(`  end`)
    lines.push('')

    // ── Team / agents subgraph ────────────────────────────────────────────
    const teamName = resolveTeamName(proj, opts)
    const team = getTeamConfig(teamName, opts)
    if (team && team.members && team.members.length > 0) {
      const tid = `T${pi}`
      lines.push(`  subgraph ${tid}_grp ["team: ${team.name}"]`)

      const lead = team.members.find(m => m.agentType === 'team-lead' || m.name === 'team-lead')
      const others = team.members.filter(m => m !== lead)
      const leadId = lead ? `${tid}_lead` : null

      if (lead) {
        lines.push(`    ${leadId}["${lead.name}\\n${lead.agentType}"]:::agent`)
      }

      for (let ai = 0; ai < others.length; ai++) {
        const agent = others[ai]
        const agentId = `${tid}_a${ai}`
        lines.push(`    ${agentId}["${agent.name}\\n${agent.agentType}"]:::agent`)
        if (leadId) lines.push(`    ${leadId} --> ${agentId}`)

        // Wire agent to the worktree whose path matches agent's cwd
        const matchWt = wtNodes.find(w => agent.cwd && agent.cwd.startsWith(w.wt.path))
        const target = matchWt ? matchWt.id : trunkId
        lines.push(`    ${agentId} -. in .-> ${target}`)
      }

      if (lead) {
        const matchWt = wtNodes.find(w => lead.cwd && lead.cwd.startsWith(w.wt.path))
        const target = matchWt ? matchWt.id : trunkId
        lines.push(`    ${leadId} -. in .-> ${target}`)
      }

      lines.push(`  end`)
      lines.push('')
    }
  }

  return lines.join('\n')
}

module.exports = { buildGraph, getWorktrees, getTeamConfig }
```

**Step 4: Run test to verify it passes**

```bash
node tests/graph.test.js
```

Expected:
```
✓ basic DSL structure
✓ empty projects placeholder
✓ active class applied to trunk node
✓ paused class applied
✓ classDef declarations present

All graph.js tests passed
```

**Step 5: Commit**

```bash
git add lib/graph.js tests/graph.test.js
git commit -m "feat: add graph.js Mermaid DSL builder with tests"
```

---

### Task 3: Add `/api/graph` to `lib/server.js` + generic static handler

**Files:**
- Modify: `lib/server.js`

**Step 1: Add `require('./graph')` at the top of server.js**

After the existing requires, add:

```js
const { buildGraph } = require('./graph')
```

**Step 2: Add `/api/graph` route**

In the HTTP handler, add this block immediately before the existing `GET /` static handler:

```js
  // GET /api/graph — Mermaid DSL
  if (req.method === 'GET' && url.pathname === '/api/graph') {
    const dsl = buildGraph(cache)
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' })
    res.end(dsl)
    return
  }
```

**Step 3: Replace the hardcoded `/` static handler with a generic `web/` handler**

Find the existing block:

```js
  // Static files: GET / → web/index.html
  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
    const filePath = path.join(WEB_DIR, 'index.html')
    fs.readFile(filePath, (err, data) => {
      if (err) { res.writeHead(404); res.end('Not found'); return }
      res.writeHead(200, { 'Content-Type': 'text/html' })
      res.end(data)
    })
    return
  }
```

Replace it with:

```js
  // Static files: GET / or /web/<file>
  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html' || url.pathname.startsWith('/web/'))) {
    const filename = (url.pathname === '/' || url.pathname === '/index.html')
      ? 'index.html'
      : path.basename(url.pathname)
    const filePath = path.join(WEB_DIR, filename)
    // Prevent path traversal
    if (!filePath.startsWith(WEB_DIR + path.sep) && filePath !== path.join(WEB_DIR, 'index.html')) {
      res.writeHead(403); res.end('Forbidden'); return
    }
    const ext = path.extname(filename)
    const mime = ext === '.js' ? 'application/javascript' : 'text/html'
    fs.readFile(filePath, (err, data) => {
      if (err) { res.writeHead(404); res.end('Not found'); return }
      res.writeHead(200, { 'Content-Type': mime })
      res.end(data)
    })
    return
  }
```

**Step 4: Verify syntax and smoke test**

```bash
node --check lib/server.js && echo "syntax OK"
```

```bash
KANBAN_PORT=17843 node lib/server.js &
sleep 2
echo "=== /api/graph first 3 lines ==="
curl -s http://localhost:17843/api/graph | head -3
echo ""
echo "=== /web/mermaid.min.js (first 40 chars) ==="
curl -s http://localhost:17843/web/mermaid.min.js | head -c 40
echo ""
kill %1
```

Expected:
```
=== /api/graph first 3 lines ===
flowchart LR
  classDef active  stroke:#3fb950,...
  classDef paused  stroke:#e3b341,...

=== /web/mermaid.min.js (first 40 chars) ===
!function(e,t){"use strict";  ← or similar Mermaid banner
```

**Step 5: Commit**

```bash
git add lib/server.js
git commit -m "feat: add /api/graph endpoint and generic web/ static file handler"
```

---

### Task 4: Update `web/index.html` — tab toggle + Mermaid graph panel

**Files:**
- Modify: `web/index.html`

**Step 1: Add tab-switcher CSS**

Inside the `<style>` block, add after the `#loading` rules:

```css
/* ── Tab switcher ── */
.tabs {
  display: flex;
  gap: 2px;
  background: var(--surface2);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 3px;
  margin-left: 16px;
}
.tab-btn {
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 12px;
  font-family: var(--font-ui);
  padding: 4px 12px;
  border-radius: 4px;
  cursor: pointer;
  transition: background 0.1s, color 0.1s;
}
.tab-btn.active {
  background: var(--surface);
  color: var(--text);
}
.tab-btn:hover:not(.active) { color: var(--text); }

/* ── Graph panel ── */
#graph {
  padding: 24px;
  flex: 1;
  overflow: auto;
  display: none;
}
#graph-inner svg {
  max-width: 100%;
  height: auto;
}
.graph-toolbar {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 16px;
}
.graph-refresh-btn {
  background: var(--surface2);
  border: 1px solid var(--border);
  color: var(--text-muted);
  font-size: 11px;
  font-family: var(--font-mono);
  padding: 4px 10px;
  border-radius: 4px;
  cursor: pointer;
}
.graph-refresh-btn:hover { color: var(--text); border-color: var(--border2); }
.graph-loading {
  color: var(--text-subtle);
  font-size: 12px;
  font-family: var(--font-mono);
}
```

**Step 2: Add tab switcher to `<header>`**

Inside `<header>`, after the `<div class="header-right">...</div>` block, add:

```html
<div class="tabs" id="tabs">
  <button class="tab-btn active" data-tab="board">Board</button>
  <button class="tab-btn" data-tab="graph">Graph</button>
</div>
```

**Step 3: Add `id="board"` to the board div**

Change:
```html
<div class="board" id="board">
```
(Verify it already has this id — it does from the current code. No change needed.)

**Step 4: Add graph panel after `.board`**

After the closing `</div>` of the `.board` div, add:

```html
<div id="graph">
  <div class="graph-toolbar">
    <button class="graph-refresh-btn" id="graph-refresh-btn">↻ Refresh</button>
    <span class="graph-loading" id="graph-loading" style="display:none">Rendering…</span>
  </div>
  <div id="graph-inner"></div>
</div>
```

**Step 5: Load Mermaid and add tab logic to `<script>`**

Add before the closing `</script>` tag (after `connectSSE()`):

```js
// ── Mermaid setup ─────────────────────────────────────────────────────────
const mermaidScript = document.createElement('script')
mermaidScript.src = '/web/mermaid.min.js'
mermaidScript.onload = () => {
  mermaid.initialize({
    startOnLoad: false,
    theme: 'dark',
    themeVariables: {
      background:          '#0d1117',
      mainBkg:             '#161b22',
      nodeBorder:          '#30363d',
      lineColor:           '#7d8590',
      clusterBkg:          '#0d1117',
      clusterBorder:       '#30363d',
      titleColor:          '#e6edf3',
      edgeLabelBackground: '#0d1117',
      nodeTextColor:       '#e6edf3',
    }
  })
}
document.head.appendChild(mermaidScript)

let activeTab = 'board'
let graphRendering = false

async function renderGraph() {
  if (graphRendering) return
  graphRendering = true
  const loadingEl = document.getElementById('graph-loading')
  loadingEl.style.display = 'inline'
  try {
    const dsl = await fetch('/api/graph').then(r => r.text())
    const id = 'kg-' + Date.now()
    const { svg } = await mermaid.render(id, dsl)
    document.getElementById('graph-inner').innerHTML = svg
  } catch (err) {
    document.getElementById('graph-inner').textContent = 'Render error: ' + err.message
  } finally {
    loadingEl.style.display = 'none'
    graphRendering = false
  }
}

document.getElementById('tabs').addEventListener('click', e => {
  const btn = e.target.closest('.tab-btn')
  if (!btn) return
  const tab = btn.dataset.tab
  if (tab === activeTab) return
  activeTab = tab
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === tab))
  document.getElementById('board').style.display = tab === 'board' ? '' : 'none'
  document.getElementById('graph').style.display = tab === 'graph' ? 'flex' : 'none'
  if (tab === 'graph') renderGraph()
})

document.getElementById('graph-refresh-btn').addEventListener('click', renderGraph)
```

**Step 6: Patch SSE `onmessage` to re-render graph when active**

In the existing `connectSSE()` function, find:

```js
  es.onmessage = e => {
    const data = JSON.parse(e.data)
    projects = data.projects ?? []
    render()
```

Add one line after `render()`:

```js
    if (activeTab === 'graph') renderGraph()
```

**Step 7: Verify in browser**

```bash
./bin/serve
```

Open `http://localhost:7842`. Verify:
- Board tab shows Kanban cards (default)
- Clicking "Graph" hides board, shows Mermaid diagram with project nodes
- Clicking "Board" restores Kanban
- "↻ Refresh" button re-renders diagram
- "Rendering…" label appears briefly during render

Stop server: `Ctrl+C`

**Step 8: Commit**

```bash
git add web/index.html
git commit -m "feat: add Graph tab with Mermaid live diagram, tab switcher, refresh button"
```

---

### Task 5: Deploy 5 testing agents in parallel

**Context:** All agents use `isolation: "worktree"` — this creates a real git worktree that shows up in the graph diagram automatically. Deploy all 5 simultaneously using the Agent tool.

**Agent 1 — `notion-claude-project-tracker` / tests**
- `subagent_type`: general-purpose
- `isolation`: worktree
- Repo: `/Users/kaitonakamichi/Documents/TEST/PROJECT_TRACKER/notion-claude-project-tracker`
- Task: Create `tests/projects.test.sh` that sources `lib/projects.sh` and tests `is_active()` using mock ISO timestamps — one test where the timestamp is recent (last 30 minutes, should return active) and one where it's 3 hours ago (should return inactive). Run it with `bash tests/projects.test.sh`. Fix any failures. Commit.

**Agent 2 — `notion-claude-project-tracker` / readme**
- `subagent_type`: general-purpose
- `isolation`: worktree
- Repo: `/Users/kaitonakamichi/Documents/TEST/PROJECT_TRACKER/notion-claude-project-tracker`
- Task: Rewrite `README.md` to document the local Kanban web app. Cover: prerequisites (Node.js, jq), quick start (`./bin/serve`), what the Board tab shows, how drag-and-drop status overrides work and where they persist (`~/.claude/kanban-status.json`), what the Graph tab shows (projects, worktrees, agents, teams), and environment variables (`KANBAN_PORT`, `CLAUDE_PROJECTS_DIR`). Commit.

**Agent 3 — `notion-claude-project-tracker` / graph-styling**
- `subagent_type`: general-purpose
- `isolation`: worktree
- Repo: `/Users/kaitonakamichi/Documents/TEST/PROJECT_TRACKER/notion-claude-project-tracker`
- Task: In `web/index.html`, improve the graph panel styling: (1) make the SVG fill the full panel width by setting `#graph-inner svg { width: 100%; height: auto; }`, (2) add a subtle `#0d1117` background grid pattern to the `#graph` panel using CSS `background-image: radial-gradient(...)`, (3) add a thin `border: 1px solid var(--border)` around the rendered SVG. Verify visually with `./bin/serve`. Commit.

**Agent 4 — `Xyris` / doc-audit**
- `subagent_type`: general-purpose
- `isolation`: worktree
- Repo: `/Users/kaitonakamichi/Documents/TEST/EXPERIMENT/Xyris`
- Task: Read all markdown files in `docs/plans/`. Create `docs/AUDIT.md` with a table: `| File | Date | One-line summary |` for each plan file found. Then add a "Key architectural decisions" section listing the 3-5 most important decisions mentioned across all plans. Commit.

**Agent 5 — `Xyris` / inline-comments**
- `subagent_type`: general-purpose
- `isolation`: worktree
- Repo: `/Users/kaitonakamichi/Documents/TEST/EXPERIMENT/Xyris`
- Task: Read `src/app.ts` (321 lines). For every exported function or class that lacks a JSDoc comment, add one describing what it does, its parameters, and return value. Do not modify any logic. Run `npx tsc --noEmit` to verify types still pass. Commit.

**Verification after agents complete:**
```bash
./bin/serve
# Open http://localhost:7842 → Graph tab
# Should show worktree nodes for each of the 5 agent branches
# e.g. notion-claude-project-tracker subgraph should have 3 worktree children
# Xyris subgraph should have 2 worktree children
```

---

## Full Verification Checklist

```bash
# 1. Syntax
bash -n lib/projects.sh lib/config.sh
node --check lib/server.js lib/graph.js

# 2. Unit tests
node tests/graph.test.js

# 3. Integration — API
KANBAN_PORT=17844 node lib/server.js &
sleep 2
curl -s http://localhost:17844/api/graph | head -5     # should start: flowchart LR
curl -s http://localhost:17844/web/mermaid.min.js | wc -c  # should be > 500000
kill %1

# 4. Browser
./bin/serve
# → Board tab: cards visible
# → Graph tab: Mermaid diagram renders
# → Refresh button works
# → SSE update (touch a jsonl) triggers graph re-render

# 5. Agents visible in graph
# → With 5 test agents running, graph shows worktree nodes
# → Team members wired to correct worktree nodes with dotted edges
```
