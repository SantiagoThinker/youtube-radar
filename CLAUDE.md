# youtube-radar — project context for Claude Code

This file is auto-loaded by Claude Code at session start. Its purpose: give any agent (cloud routine, local session, subagent) a fast orientation without forcing a full README read before every tool use.

## What this is

Agentic pipeline that monitors YouTube channels and produces personalized digests filtered through user-defined lenses. Delivered daily to Telegram.

Pipeline: cron routine → watcher → transcript → Extractor → Synthesizer → Telegram + git push.

## Where things live (read in this order when needed)

| File / folder | Why |
|---|---|
| **`README.md`** | What the system is, why it exists, architecture diagram. Start here if you're new. |
| **`QUICKSTART.md`** | 15-min setup walkthrough end to end |
| **`CONFIGURATION.md`** | Every knob: lenses, channels, language, env vars |
| **`ARCHITECTURE.md`** | How it works under the hood — file conventions, JSONL schema, customization points |
| **`me.md`** | User profile + lenses + stop-list. **Synthesizer reads this before every output.** Ships as a starter file with `[PLACEHOLDER]` markers — user edits directly (GitHub web or local) OR overwrites via `setup.sh`. |
| **`channels.yaml`** | Monitored channels with handle / priority / active / channel_id. Ships with 7 default channels — user edits directly OR via `setup.sh`. |
| **`seen.json`** | Processed video_ids per channel — **source of truth for deduplication** |
| **`.claude/orchestrator.md`** | Full prompt of the cloud routine (runtime logic: watcher, selection, subagents, Telegram, auto-merge). Routine reads this directly (wrapper pattern). |
| **`.claude/agents/extractor.md`** | Extractor subagent spec |
| **`.claude/agents/synthesizer.md`** | Synthesizer subagent spec |
| **`.claude/setup-routine.md`** | UI walkthrough for setting up the routine on claude.ai |
| **`CHANGELOG.md`** | System evolution. **Update on every meaningful change** (rules inside the file). |
| **`STATUS.md`** | Auto-generated dashboard. **Do not edit by hand** — overwritten next run. |
| **`scripts/utils.sh`** | Bash helpers: slug, clean_vtt, build_base, current_log_file |
| **`scripts/utils.py`** | Python helpers: prune_seen, all_log_files, current_log_file |
| **`scripts/gen_status.py`** | Generator of STATUS.md (run by orchestrator at end of each run) |
| **`logs/runs-YYYY-MM.jsonl`** | JSONL — one line per step per agent per run (rotated by month) |
| **`logs/<run_id>.md`** | Human-readable dump on failed runs (optional) |
| **`wiki/<base>.md`** | Extractor outputs — structured breakdown in user's output_language |
| **`recommendations/<base>.md`** | Synthesizer outputs — TL;DR + lens sections |
| **`transcripts/raw/<base>.txt`** | Cleaned EN transcripts (for replay / debug) |

## Conventions (must follow)

- **Filenames:** `<YYYY-MM-DD>_<channel-without-@>_<title-slug-max-60>_<youtube-id>.<ext>`. Spec + bash `slug()` in README § filename convention.
- **Telegram parse_mode = HTML.** Not Markdown — breaks on underscores in filenames.
- **Wrapper pattern for orchestrator.** The Instructions field of the routine on claude.ai is a thin wrapper that says "read `.claude/orchestrator.md`". All logic lives in the repo. All edits go through `git commit`, not UI.
- **CHANGELOG mandatory** for: subagent prompt edits, file schema changes, env/routine config, discovered gotchas.
- **STATUS.md is auto-only.** Manual edits are pointless.
- **seen.json** stores ONLY truly completed video_ids (with wiki + recommendations + Telegram done). Don't write "in-progress" or "failed" there.
- **Output language** lives in `me.md` (e.g., `output_language: en`). Extractor and Synthesizer respect it for all output.
- **GitHub URLs in orchestrator are parameterized** via `$GITHUB_REPO` (extracted from `git remote get-url origin` at runtime). No hardcoded `<owner>/<repo>`.

## Things to know (gotchas from production experience)

- **Cloud SSL**: yt-dlp in Claude Code cloud env requires `--no-check-certificates` (corporate proxy intercepts cert). Locally via `brew yt-dlp` you don't need it.
- **Cloud APT PPAs**: cloud env has `deadsnakes/ppa` and `ondrej/php` pre-configured; both return 403 Forbidden on `apt update`. Setup script must disable them via `sed '/ppa\.launchpadcontent\.net/...'` BEFORE `apt update`, otherwise exit code 100 breaks setup. See `.claude/setup-routine.md`.
- **Network allowlist**: `youtube.com` + `*.googlevideo.com` (where VTT subtitles live) + `api.telegram.org` are NOT in Anthropic's default Trusted allowlist. Required in Custom env Allowed domains.
- **Permissions toggle bug** (research preview): "Allow unrestricted git push" toggle silently fails — push always redirects to `claude/<branch>`. Workaround in orchestrator: after push, open PR via `gh pr create` + `gh pr merge --squash --delete-branch`, then delete branch via REST API as belt+suspenders.
- **Branch cleanup**: `gh --delete-branch` AND `git push origin --delete` both fail silently in cloud env (git proxy blocks ref deletion). Use `gh api -X DELETE /repos/.../git/refs/heads/<branch>` — REST API bypasses git proxy.
- **Watcher strictly sequential**: Claude Code parallel-cancellation cascade kills batch tool calls if any one fails. Do NOT run 7 yt-dlp calls in one Bash batch.
- **Subagents don't make content judgments**: video selection is fully deterministic (1 freshest unseen per channel + priority list). Content filtering is the Synthesizer's job through user-defined lenses.
- **YouTube IP rate-limit**: with close runs (>2/hour), yt-dlp may hit "Sign in to confirm you're not a bot". Usually clears in 1-3 hours. Currently with 24h cron less frequent. Persistent block on cloud subnet is also possible — see README known limitations.
- **Telegram fail = silent**: if TELEGRAM_BOT_TOKEN is broken, both video messages AND failure alerts go to nowhere. STATUS.md surfaces a banner when detected — only way to know without log archaeology.

## Don't

- Don't duplicate `.claude/orchestrator.md` into the Instructions field on claude.ai (wrapper pattern matters)
- Don't do content judgment in orchestrator during video selection — that's Synthesizer's role
- Don't write secrets (`TELEGRAM_BOT_TOKEN`, `GH_TOKEN`, `ANTHROPIC_*`) into repo / logs / commits
- Don't edit STATUS.md by hand
- Don't `git push origin main` from your local machine over routine commits without `git pull --rebase` first
- Don't delete `claude/*` branches that are still mid-merge — auto-merge should handle it via REST API

## When something breaks

Standard recovery flow:
1. `tail logs/runs-YYYY-MM.jsonl | jq '. | select(.status == "error")'` — last errors
2. If `logs/<run_id>.md` exists — human-readable failed-run dump
3. `STATUS.md` — status of last 10 runs, see if there's degradation
4. CHANGELOG.md — issue may already be documented with a workaround

Common signatures:
- Telegram delivery 404 = `TELEGRAM_BOT_TOKEN` broken (revoked / wrong / whitespace). Recheck via routine UI, can't recover from logs.
- Setup script exit 100 = APT PPA issue. Check setup script disables them before `apt update`.
- yt-dlp 403 "Sign in to confirm bot" = YouTube IP block. Wait 1-3 hours; if persistent, see README known limitations.
