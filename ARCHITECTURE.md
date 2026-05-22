# Architecture

Deep dive for hackers — how it works under the hood, file conventions, data flow, customization points.

For setup see [QUICKSTART.md](QUICKSTART.md). For configuration knobs see [CONFIGURATION.md](CONFIGURATION.md). For the runtime prompt itself see [.claude/orchestrator.md](.claude/orchestrator.md).

---

## Component map

```
┌─────────────────────────────────────────────────────────────────────┐
│  Cloud Routine (claude.ai/code/routines)                            │
│  Trigger: cron 0 6 * * * UTC                                        │
│  Environment: youtube-radar (env vars, network allowlist, setup)    │
│  Instructions: thin wrapper "read .claude/orchestrator.md"          │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ session starts; orchestrator reads .claude/orchestrator.md
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Orchestrator (main Claude agent of the routine)                    │
│  Tools: Bash, Read, Write, Agent, GitHub built-ins                  │
│  No content analysis — pure orchestration + I/O                     │
└─────────────────────────────────────────────────────────────────────┘
        │                          │                          │
        │ for each active channel  │ for each picked video    │ end of run
        │ (sequential)             │                          │
        ▼                          ▼                          ▼
┌──────────────┐         ┌──────────────────┐         ┌────────────────┐
│  Watcher     │         │  Per-video       │         │  Finalization  │
│  (Bash via   │         │  pipeline        │         │                │
│  yt-dlp)     │         │                  │         │  - prune seen  │
│              │         │  1. transcript   │         │  - gen STATUS  │
│  Returns     │         │  2. Extractor    │         │  - alert if    │
│  new IDs     │         │     subagent     │         │    errors>0    │
│              │         │  3. Synthesizer  │         │  - git commit  │
│              │         │     subagent     │         │  - auto-merge  │
│              │         │  4. Telegram     │         │    PR (via gh) │
│              │         │  5. seen.json    │         │  - delete      │
│              │         │     append       │         │    branch via  │
│              │         │                  │         │    REST API    │
│              │         └──────────────────┘         └────────────────┘
└──────────────┘
```

Three agents in the routine:
- **Orchestrator** — top-level, no content judgment
- **Extractor** subagent — language-neutral video breakdown
- **Synthesizer** subagent — projects breakdown through user's lenses

Subagents are context-isolated. A 1.5-hour video transcript is ~30K tokens; running 5 of these through the orchestrator's main context would saturate it quickly. Subagents keep their own context, return only a short summary to the orchestrator.

---

## File layout

```
.
├── README.md                # what + why + arch diagram (this is for humans)
├── QUICKSTART.md            # 15-min setup
├── CONFIGURATION.md         # every knob
├── ARCHITECTURE.md          # this file
├── CHANGELOG.md             # system evolution (rules inside the file)
├── CLAUDE.md                # auto-loaded by Claude Code — agent context
├── LICENSE                  # MIT
│
├── me.md                    # user profile + lenses (created by setup.sh)
├── me.template.md           # template, kept in repo for reference
│
├── channels.yaml            # monitored channels (created by setup.sh)
├── channels.template.yaml   # template with example channels
│
├── seen.json                # {handle: [video_ids]} — source of truth for dedup
├── STATUS.md                # auto-generated dashboard (regen each run)
│
├── setup.sh                 # interactive setup wizard
│
├── .claude/
│   ├── orchestrator.md      # runtime logic — the cloud routine reads this
│   ├── setup-routine.md     # UI walkthrough for routine creation
│   └── agents/
│       ├── extractor.md     # Extractor subagent spec
│       └── synthesizer.md   # Synthesizer subagent spec
│
├── scripts/
│   ├── utils.sh             # bash helpers: slug, clean_vtt, build_base, current_log_file
│   ├── utils.py             # Python helpers: prune_seen, all_log_files, current_log_file
│   └── gen_status.py        # generates STATUS.md
│
├── wiki/<base>.md           # Extractor outputs
├── recommendations/<base>.md # Synthesizer outputs (TL;DR + lens sections)
├── transcripts/raw/<base>.txt # cleaned EN transcripts
└── logs/
    ├── runs-YYYY-MM.jsonl   # JSONL append-only, one line per agent step
    └── <run_id>.md          # human-readable dump on failed runs
```

---

## Filename convention

All artifacts of one video share a base filename:

```
<date>_<channel-without-@>_<title-slug-max-60>_<youtube-id>
```

Example:
```
wiki/2026-04-23_lennyspodcast_how-anthropics-product-team-moves-faster_PplmzlgE0kg.md
recommendations/2026-04-23_lennyspodcast_how-anthropics-product-team-moves-faster_PplmzlgE0kg.md
transcripts/raw/2026-04-23_lennyspodcast_how-anthropics-product-team-moves-faster_PplmzlgE0kg.txt
```

| Field | Source |
|---|---|
| `<date>` | yt-dlp `upload_date` → ISO `YYYY-MM-DD`. Falls back to `processed_at` if NA. |
| `<channel>` | handle without `@`, lowercase |
| `<title-slug>` | lowercase ASCII, dashes for non-alpha, max 60 chars (truncate at word boundary) |
| `<video-id>` | YouTube ID, 11 chars, unchanged — stable anchor |

**Why this design**:
- `ls wiki/ | sort` gives chronological view with channel grouping at the same date
- Title slug makes "what's this about" visible without opening
- video_id anchors at the end — `ls | grep <id>` finds the file even if YouTube renames the video
- `seen.json` stores just video_ids (lookup), not filenames

The slug function lives in [`scripts/utils.sh`](scripts/utils.sh):
```bash
slug "How AI Is Changing Things | Some Speaker"
# → "how-ai-is-changing-things-some-speaker"
```

---

## Data flow per run

1. **Setup** — orchestrator reads README, CLAUDE.md, channels.yaml, seen.json. Sources `scripts/utils.sh` for helpers. Generates `RUN_ID = YYYYMMDD-HHMM` (UTC). Sets `LOGFILE=$(current_log_file)`.

2. **Watcher** — sequentially across active channels (sorted by priority):
   ```
   yt-dlp --flat-playlist --print "%(id)s|%(title)s|%(upload_date)s" --playlist-items 1:10 ...
   ```
   - Returns last 10 videos per channel
   - Filter out seen IDs
   - Log one line per channel to `logs/runs-YYYY-MM.jsonl`
   - On individual channel failure: one retry, then log error and continue

3. **Selection** — deterministic:
   - One freshest unseen per channel (top of watcher output)
   - If candidates ≤ 5: take all
   - If > 5: pick 5 by `priority` ascending
   - No content judgment in this layer

4. **Per-video** (up to 5 videos in parallel-ish via subagent invocations):
   - **Idempotency check**: if `wiki/<base>.md` already exists → skip Extractor. Same for recommendations and Synthesizer. Allows safe retry after partial failures.
   - **Transcript**: `yt-dlp --write-auto-sub` → VTT → `clean_vtt()` → cleaned `.txt`. Sanity check: >500 words required.
   - **Extractor subagent** (context-isolated): reads transcript → writes `wiki/<base>.md` (structured breakdown, language-neutral).
   - **Synthesizer subagent** (context-isolated): reads `wiki/<base>.md` + `me.md` → writes `recommendations/<base>.md` (TL;DR + lens sections).
   - **Telegram**: pull TL;DR block from recommendations, format as HTML, POST to Bot API.
   - **State**: append video_id to `seen.json[handle]`.
   - **Logs**: every step gets a JSONL entry with `tokens_in` / `tokens_out` (estimated via `wc -w * 1.5`).

5. **Finalization**:
   - `prune_seen(30)` — trim seen.json to last 30 IDs per channel
   - `gen_status.py > STATUS.md` — regenerate dashboard
   - If errors > 0: send failure alert via Telegram (🚨 format, distinct from 🎬 video messages)
   - `git add -A && git commit && git push origin main`
   - If push redirected to `claude/<branch>` (cloud git proxy behavior): `gh pr create` + `gh pr merge --squash` + REST API branch delete

---

## JSONL log schema (logs/runs-YYYY-MM.jsonl)

One line per step. Fields:

```json
{
  "ts": "2026-05-05T06:01:11Z",
  "run_id": "20260505-0601",
  "agent": "extractor",
  "video_id": "PplmzlgE0kg",
  "channel": "@LennysPodcast",
  "action": "produce_wiki",
  "status": "ok",
  "duration_s": 47,
  "tokens_in": 24984,
  "tokens_out": 2730,
  "notes": "base: 2026-04-23_..."
}
```

Agents: `orchestrator`, `watcher`, `transcript`, `extractor`, `synthesizer`, `notifier`.
Statuses: `ok`, `error`, `skipped`.

Useful queries:
```bash
# all errors in current month
grep '"status":"error"' logs/runs-*.jsonl | jq

# all steps of one video
grep '<video_id>' logs/runs-*.jsonl | jq

# avg Extractor duration
grep '"agent":"extractor"' logs/runs-*.jsonl | jq '.duration_s' | awk '{s+=$1;n++} END {print s/n}'

# token cost per run (approximate)
grep '"run_id":"<id>"' logs/runs-*.jsonl | jq '.tokens_in + .tokens_out' | paste -sd+ | bc
```

---

## Token estimation

Real token counts would require parsing subagent invocation responses. We use a cheaper proxy: `wc -w` on input/output files × 1.5 (rough word→token ratio for English).

Accuracy ~±20%. Good enough for trend tracking and cost estimation in STATUS.md.

For exact accounting, you'd intercept subagent metadata responses.

---

## Customization points

| What | Where | Effort |
|---|---|---|
| Add a lens | `me.md` `## Lenses` section, new `### Name` heading | 2 min |
| Add a channel | `channels.yaml` + `seen.json` | 2 min |
| Change cron | claude.ai routine UI | 30 sec |
| Change quota (5 → N) | `.claude/orchestrator.md` "VIDEO SELECTION" section | 5 min |
| Change wiki/recs format | `.claude/agents/extractor.md` / `synthesizer.md` | 10-30 min |
| Different output language | `me.md` `output_language` field, subagents already respect it | 1 min |
| Add Slack alongside Telegram | New step in `.claude/orchestrator.md` step 6 — `curl` to Slack webhook | 30 min |
| Per-video filtering before processing | New step before Extractor invocation — early-skip based on title/duration | 30 min |
| Different transcript source | Replace yt-dlp step with Whisper / Deepgram / your API | 1-2 h |

All are git-commit changes. Wrapper-pattern means routine picks them up on next run.

---

## Known limitations and workarounds

### YouTube IP rate-limit on Claude cloud env

Anthropic's cloud runs on shared IPs. YouTube blocks aggressive scraping with "Sign in to confirm you're not a bot" (HTTP 403). Affects transcript downloads (`watch?v=...` requests). Watcher (flat-playlist) is less affected.

**Current workaround**: 24h cron reduces frequency; routine has per-channel retry + skip-video-on-failure logic; failed runs alert via Telegram.

**Future options (not yet implemented)**:
- Cookies-based auth: `--cookies-from-browser` or upload a `cookies.txt` to env
- Multi-client fallback: `--extractor-args "youtube:player_client=ios,android,tv_embedded"`
- Whisper API fallback: download audio, transcribe with Whisper (~$0.006/min)
- Move pipeline to a personal server with residential IP

### Cloud git proxy blocks push to main

Per Anthropic docs: "Restricts git push operations to the current working branch". Even with "Allow unrestricted branch pushes" toggled ON, push redirects to `claude/<branch>`.

**Workaround**: orchestrator detects redirected push, opens a PR via `gh pr create`, merges via `gh pr merge --squash`. Branch deletion via REST API (`gh api -X DELETE ...`) — because `gh --delete-branch` also goes through git proxy.

### APT PPAs return 403 in cloud env

`deadsnakes/ppa` and `ondrej/php` are pre-configured in cloud Ubuntu but return 403 Forbidden. `apt update` exits 100, setup script fails.

**Workaround** in setup script: `sed` greps `ppa.launchpadcontent.net` in `/etc/apt/sources.list.d/*.list` and comments out `deb` lines before `apt update`.

### Telegram is a single point of failure for notifications

Both video messages AND failure alerts use the same bot. If `TELEGRAM_BOT_TOKEN` is broken, both go silent. User has no signal that the system is failing.

**Mitigation**: STATUS.md detects notifier errors in latest run and surfaces a 🚨 banner. Open STATUS.md when in doubt.

---

## CHANGELOG discipline

[CHANGELOG.md](CHANGELOG.md) follows a custom format (not Keep a Changelog). Every entry must include:

- **What changed** in 1-3 sentences
- **Value** — what pain it closes, what capability it opens

If the value isn't obvious, the entry should be reconsidered. The discipline matters because much of the system's surface area is "hard-won workarounds" — knowing WHY each workaround exists helps future maintainers (you, in 6 months) avoid re-introducing the original bug.
