# Changelog

System evolution of youtube-radar — agents, conventions, infrastructure. **Does not duplicate** `logs/runs-*.jsonl` (per-run operational log); this file is about meta-changes to the system itself.

## Format

Reverse chronological (newest on top). Each entry has:
- **Date** in the section heading
- **Category** (`🆕 feature` / `🔧 infra` / `📝 docs` / `🐛 fix` / `💔 breaking` / `🧪 experiment`)
- Single-line title
- **What:** what concretely changed — 1-3 sentences, no fluff
- **Value:** what pain it closes, what capability it opens. If the value isn't obvious, the entry should be reconsidered.

## When to add an entry

- Editing a subagent prompt (`.claude/agents/*`)
- Editing the orchestrator
- Adding / removing / muting a channel in `channels.yaml`
- Changing filename conventions, file schema, `seen.json` structure
- Changing Environment or Routine configuration in claude.ai (allowlist, env vars, setup script, schedule)
- Discovering a new infrastructure gotcha worth documenting so it doesn't get rediscovered later
- A relevant architectural pivot

## When NOT to add an entry

- Every routine run — those go to `logs/runs-*.jsonl`
- Cosmetic doc edits (typos, formatting) — git log is enough
- Creating new content artifacts (`wiki/...`, `recommendations/...`) — filename and git log speak for themselves
- Adding / removing `.gitkeep` and similar

---

## Initial commit

### 🆕 feature: youtube-radar initial public release

**What:** Public, generic version of an originally personal YouTube digest pipeline. Architecture:
- Cloud routine on claude.ai/code/routines reads `.claude/orchestrator.md` from this repo (wrapper-pattern Instructions)
- Watcher via `yt-dlp --flat-playlist` per channel
- Per-video: yt-dlp transcript → cleanup → Extractor subagent → Synthesizer subagent → Telegram + git push
- Two context-isolated subagents (Extractor + Synthesizer)
- N user-defined lenses in `me.md` — Synthesizer projects each video through them
- Auto-merge PR workaround for cloud git proxy restriction
- STATUS.md auto-generated dashboard with cost tracking
- Failure alerts via Telegram with 🚨 emoji
- Setup wizard (`setup.sh`) collects profile, lenses, channels, secrets

**Value:** Anyone can fork, run `./setup.sh`, configure their own lenses, and have an autonomous daily YouTube digest in their Telegram within 15 minutes — without maintaining a server. All accumulated production gotchas (SSL cert in cloud env, PPA 403s, branch cleanup via REST API, parallel-cancellation cascade in watcher, etc.) are baked into the system from day one.

**Origin:** Forked from a private personal-use codebase that ran in production for ~1 week. Personal data stripped. English translation throughout. Lens system generalized from 3 hardcoded sections to N user-defined. Output language configurable.
