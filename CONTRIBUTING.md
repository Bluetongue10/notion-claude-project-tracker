# Contributing

## Prerequisites

- **bash** (≥ 3.2) and **zsh**
- **Node.js** ≥ 18
- **jq** (`brew install jq` or `apt install jq`)
- **Claude Code** (`~/.claude/` directory exists)

## Local dev setup

```bash
git clone <repo-url>
cd notion-claude-project-tracker
cp .env.example .env   # then fill in NOTION_TOKEN and NOTION_PARENT_PAGE_ID
node lib/server.js     # starts the kanban server on :7842
```

Open http://localhost:7842 in your browser.

## Running tests

```bash
npm test
# or directly:
node tests/graph.test.js
```

## Code style

- **No external npm dependencies** — use Node.js stdlib only
- **Bash scripts** must pass `shellcheck` (`brew install shellcheck`)
- Keep each module focused: `lib/server.js` for HTTP, `lib/graph.js` for Mermaid DSL generation
- Prefer clarity over cleverness; comment only non-obvious logic

## PR process

1. Branch from `main`: `git checkout -b feat/my-feature`
2. Link the relevant issue in your PR description
3. One feature or fix per PR
4. Ensure `npm test` passes before opening
5. Squash trivial fixup commits before merge
