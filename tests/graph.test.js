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

// Test 6: agent_details renders status-aware classes (subagent fallback path)
{
  const projects = [{
    ...mockProjects[0],
    _teamName: null,
    agent_details: [
      { name: 'researcher', type: 'general-purpose', model: 'claude-sonnet-4-6', status: 'active' },
      { name: 'tester',     type: 'general-purpose', model: 'claude-haiku-4-5-20251001', status: 'idle' },
      { name: 'old-agent',  type: 'general-purpose', model: '',                           status: 'done'  },
    ]
  }]
  const dsl = buildGraph(projects, { skipGit: true, skipTeams: true })
  assert(dsl.includes(':::agent-active'), 'missing :::agent-active class')
  assert(dsl.includes(':::agent-idle'),   'missing :::agent-idle class')
  assert(dsl.includes(':::agent-done'),   'missing :::agent-done class')
  assert(dsl.includes('subagents'),       'missing subagents subgraph label')
  assert(dsl.includes('sonnet-4-6'),      'missing shortened model name')
  assert(dsl.includes('haiku-4-5'),       'missing shortened haiku model name')
  console.log('✓ agent status classes and model labels rendered')
}

console.log('\nAll graph.js tests passed')
