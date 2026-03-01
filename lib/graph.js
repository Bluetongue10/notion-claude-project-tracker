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
  // Optional: filter to a single project by path
  const filtered = opts.pathFilter
    ? projects.filter(p => p.path === opts.pathFilter)
    : projects

  if (!filtered || filtered.length === 0) {
    return 'flowchart LR\n  N["No projects found"]'
  }

  // Use filtered list from here on
  projects = filtered

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
