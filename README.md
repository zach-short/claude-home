# claude-home

Portable Claude Code config for cloud sessions. Cloud sessions do not read `~/.claude` on the local machine. A setup script copies this repo into `/root/.claude`.

Contents: `CLAUDE.md`, `rules/`, `agents/`, `skills/`, `hooks/`, `settings.json`.

Not included: credentials, history, projects, plugins, and any machine-specific settings (`settings.json` here holds only two hooks: the completion gate on Stop and the prose check on Write and Edit). Secrets go in network secrets, not in this repo.
