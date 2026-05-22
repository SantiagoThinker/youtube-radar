# youtube-radar

Personalized YouTube digest pipeline. Monitors a list of channels, transcribes new videos, and delivers structured English summaries to your Telegram — filtered through **your own lenses** (career, startup, technical radar, or any custom focus you define).

Built as a [Claude Code routine](https://code.claude.com/docs/en/routines) that runs autonomously on cloud infrastructure. No server to maintain. No code to write — just configure lenses, channels, and a Telegram bot.

---

## What you get

For each new video on monitored channels, you receive a Telegram message like:

```
🎬 @SomeChannel · Title of the video

🧩 Root tensions:
• Tension 1 in 6-12 words
• Tension 2
• ...

💡 Most original idea: One concrete contrarian insight from the speaker, with attribution.

📚 Wiki · 🎯 Recommendations · ▶️ YouTube
```

Click **Wiki** → full structured breakdown of the video (root tensions, original ideas, practical observations with names/numbers).

Click **Recommendations** → personalized bullets per lens you defined. Each lens can refuse honestly if the content doesn't apply — better than fluff.

---

## Architecture

```
                          ┌─────────────────────────┐
   cron 0 6 * * * UTC  →  │   Orchestrator routine  │  ← claude.ai/code/routines
   (one daily digest)     │   reads .claude/        │     (thin wrapper Instructions)
                          │   orchestrator.md       │
                          └────────┬────────────────┘
                                   │
                ┌──────────────────┼──────────────────┐
                ▼                  ▼                  ▼
         channels.yaml      yt-dlp (watcher       seen.json
         (what to watch)    + transcripts)        (what was processed)
                                   │
                                   ▼
                ┌────────────────────────────────────┐
                │   Extractor subagent (Claude)      │
                │   transcript → wiki/<base>.md      │
                │   structured breakdown             │
                └────────────────┬───────────────────┘
                                 │
                                 ▼
                ┌────────────────────────────────────┐
                │   Synthesizer subagent (Claude)    │
                │   wiki + me.md → recommendations/  │
                │   TL;DR + N lenses + ignored bin   │
                └────────────────┬───────────────────┘
                                 │
                                 ▼
                ┌────────────────────────────────────┐
                │  Telegram (TL;DR block)            │
                │  STATUS.md regen                   │
                │  git commit + push                 │
                │  auto-merge PR (cloud workaround)  │
                └────────────────────────────────────┘
```

Three Claude agents collaborate:
- **Orchestrator** — runs on cron, does I/O, no content analysis
- **Extractor** — language-neutral structural breakdown of a video
- **Synthesizer** — projects the breakdown through your personal lenses

Subagents are context-isolated so a 1-hour transcript (~30K tokens) doesn't pollute the main routine's context.

---

## Quick start

See [QUICKSTART.md](QUICKSTART.md) for the full 25-35 min walkthrough.

Big picture:
1. **Use this template** on GitHub → creates your own copy
2. Edit `me.md` (profile + lenses) and `channels.yaml` (what to watch) —
   either in GitHub web editor (no install) or via `./setup.sh` wizard locally
3. Set up cloud routine on claude.ai with three secrets (Telegram bot,
   GitHub PAT, Anthropic auth)
4. Click Run now → first digest in ~15-20 min

---

## Why this exists

Most YouTube channels you follow have value, but you don't have time to watch hours of content. RSS readers and "AI summarizers" produce generic bullet points — they don't know what's useful **to you**.

This pipeline differs:
- **You define lenses** — what makes a piece of content "useful" specifically for you
- **You define a stop-list** — what you already know that shouldn't be repeated as insight
- **Synthesizer is honest** — when content doesn't match your lenses, it says so instead of producing filler bullets
- **Architecture is transparent** — full agent prompts in repo, no black box

The system was built originally by one user for a specific career + startup context. This generic version preserves the architecture and removes all personal content. You bring your own lenses.

---

## Detailed docs

- [QUICKSTART.md](QUICKSTART.md) — 15-min setup
- [CONFIGURATION.md](CONFIGURATION.md) — all knobs: lenses, channels, language, env vars
- [ARCHITECTURE.md](ARCHITECTURE.md) — how it works under the hood, file conventions, JSONL log schema, customization points
- [CLAUDE.md](CLAUDE.md) — context file read automatically by Claude Code at session start
- [.claude/orchestrator.md](.claude/orchestrator.md) — full runtime prompt
- [.claude/setup-routine.md](.claude/setup-routine.md) — Claude.ai routine UI walkthrough

---

## Known limitations (honest disclosure)

This is built on Claude Code routines, which are **in research preview** at Anthropic. Several gotchas observed in production:

- **YouTube IP rate-limit**: Anthropic's cloud env shares IPs across users; YouTube periodically blocks transcript downloads with "Sign in to confirm you're not a bot". Currently no clean workaround in cloud (options: cookies-based auth, Whisper fallback, or move to personal infrastructure).
- **Cloud git proxy**: `git push` redirects to `claude/<branch>` regardless of "Allow unrestricted branch pushes" toggle. Orchestrator works around this via `gh pr merge` + REST API branch delete.
- **Branch cleanup**: `gh --delete-branch` silently fails because cloud git proxy blocks ref deletion; REST API workaround is wired in.
- **APT PPAs in cloud env**: `deadsnakes/ppa` and `ondrej/php` return 403, breaking `apt update`. Setup script disables them.
- **Telegram is single point of failure**: video messages AND failure alerts use the same bot; if token breaks, both go silent. STATUS.md surfaces a banner as backup signal.
- **Cost**: routine runs on your claude.ai Pro/Max/Team/Enterprise subscription quota. No per-call billing, no separate Anthropic token to set up. STATUS.md shows an API-equivalent burn estimate for understanding usage intensity. Budget against your plan's fair-use limits if you scale up channels / quota aggressively.

See [CHANGELOG.md](CHANGELOG.md) for full history of these discoveries and workarounds.

---

## License

MIT — see [LICENSE](LICENSE).

## Contributing

This is a personal-tool fork made publicly available. Issues and PRs welcome but be aware: the maintainer's primary use case is their own. If you want significant changes, fork and adapt freely under MIT.
