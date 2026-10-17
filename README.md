# claude-home

Portable Claude Code config for cloud sessions. Cloud sessions do not read `~/.claude` on the local machine. A setup script copies this repo into `/root/.claude`.

Contents: `CLAUDE.md`, `rules/`, `agents/`, `skills/`, `hooks/`.

Not included: credentials, history, projects, plugins, and `settings.json` (it holds machine paths). Secrets go in network secrets, not in this repo.
