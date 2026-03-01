#!/usr/bin/env node
'use strict'

const http = require('http')
const fs = require('fs')
const path = require('path')
const { execSync } = require('child_process')
const { homedir } = require('os')
const { buildGraph } = require('./graph')

const PORT = parseInt(process.env.KANBAN_PORT ?? '7842', 10)
const PROJECTS_DIR = process.env.CLAUDE_PROJECTS_DIR ?? path.join(homedir(), '.claude/projects')
const STATE_FILE = path.join(homedir(), '.claude/kanban-status.json')
const SCRIPT_DIR = path.resolve(__dirname)
const PROJECTS_SH = path.join(SCRIPT_DIR, 'projects.sh')
const WEB_DIR = path.join(SCRIPT_DIR, '..', 'web')

// --- In-memory state ---
let cache = [] // latest projects array
let sseClients = [] // active SSE response objects
let writeLock = false

// --- Status file helpers ---
function readStatusFile() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'))
  } catch {
    return {}
  }
}

function writeStatusFile(data) {
  const tmp = STATE_FILE + '.tmp'
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2))
  fs.renameSync(tmp, STATE_FILE)
}

// --- Project refresh ---
function refresh() {
  let raw
  try {
    raw = execSync(
      `bash -c 'source ${JSON.stringify(PROJECTS_SH)} && get_projects'`,
      { timeout: 10000, encoding: 'utf8', env: { ...process.env, CLAUDE_PROJECTS_DIR: PROJECTS_DIR } }
    )
  } catch (err) {
    console.error('[server] get_projects failed:', err.message)
    return // keep stale cache
  }

  const overrides = readStatusFile()
  const projects = []

  for (const line of raw.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed) continue
    let proj
    try { proj = JSON.parse(trimmed) } catch { continue }

    // Status merge logic:
    // - "Active" (from projects.sh) always wins
    // - else use persisted override if present
    // - else use computed "Paused"
    if (proj.status !== 'Active' && overrides[proj.path]) {
      proj.status = overrides[proj.path]
    }
    projects.push(proj)
  }

  cache = projects
  broadcast()
}

// --- SSE broadcast ---
function broadcast() {
  const payload = `data: ${JSON.stringify({ projects: cache })}\n\n`
  for (const res of sseClients) {
    try { res.write(payload) } catch { /* client gone */ }
  }
}

// --- fs.watch with debounce ---
let debounceTimer = null
function startWatcher() {
  try {
    fs.watch(PROJECTS_DIR, { recursive: false }, () => {
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(refresh, 500)
    })
    console.log(`[server] Watching ${PROJECTS_DIR} for changes`)
  } catch (err) {
    console.warn('[server] fs.watch unavailable:', err.message)
  }
}

// --- HTTP server ---
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`)

  // SSE endpoint
  if (req.method === 'GET' && url.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    })
    res.write(`data: ${JSON.stringify({ projects: cache })}\n\n`)
    sseClients.push(res)
    req.on('close', () => {
      sseClients = sseClients.filter(c => c !== res)
    })
    return
  }

  // GET /api/projects
  if (req.method === 'GET' && url.pathname === '/api/projects') {
    const body = JSON.stringify({ projects: cache })
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(body)
    return
  }

  // POST /api/status
  if (req.method === 'POST' && url.pathname === '/api/status') {
    let body = ''
    req.on('data', chunk => { body += chunk })
    req.on('end', () => {
      let payload
      try { payload = JSON.parse(body) } catch {
        res.writeHead(400)
        res.end('{"error":"invalid JSON"}')
        return
      }
      const { path: projPath, status } = payload
      const valid = ['Needs Review', 'Done', 'Paused']
      if (!projPath || !valid.includes(status)) {
        res.writeHead(400)
        res.end(`{"error":"status must be one of ${valid.join(', ')}"}`)
        return
      }

      if (writeLock) { res.writeHead(409); res.end('{"error":"write in progress"}'); return }
      writeLock = true
      try {
        const overrides = readStatusFile()
        if (status === 'Paused') {
          delete overrides[projPath] // clear override, let computed status take effect
        } else {
          overrides[projPath] = status
        }
        writeStatusFile(overrides)
      } finally {
        writeLock = false
      }

      refresh()
      res.writeHead(200, { 'Content-Type': 'application/json' })
      res.end('{"ok":true}')
    })
    return
  }

  // GET /api/graph — Mermaid DSL
  if (req.method === 'GET' && url.pathname === '/api/graph') {
    const dsl = buildGraph(cache)
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' })
    res.end(dsl)
    return
  }

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

  res.writeHead(404)
  res.end('Not found')
})

// --- Boot ---
server.listen(PORT, '127.0.0.1', () => {
  console.log(`Kanban board running at http://localhost:${PORT}`)
  refresh()
  startWatcher()
  setInterval(refresh, 30000)

  // Auto-open browser
  const open = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open'
  try { execSync(`${open} http://localhost:${PORT}`) } catch { /* ignore */ }
})

server.on('error', err => {
  console.error('[server] Fatal:', err.message)
  process.exit(1)
})
