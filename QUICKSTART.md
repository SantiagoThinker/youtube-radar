# Quickstart — from zero to first digest

Total time: **~25-35 minutes** for the careful walkthrough. Done once,
runs forever.

This guide walks you through **three phases**:

- **Phase A** — Get your own copy of youtube-radar (2 min)
- **Phase B** — Configure your profile + lenses + channels (5-10 min)
- **Phase C** — Wire up the cloud routine on claude.ai (15-25 min)

Read top to bottom. Don't skip — order matters.

---

## What you'll need before starting

You need accounts (free or paid) on these services:

| Service | Why | Cost |
|---|---|---|
| GitHub | Hosts your config files | Free |
| claude.ai (Pro/Max/Team/Enterprise) with **Claude Code on the web** enabled | Runs the routine | $20+/mo |
| Telegram | Receives your digests | Free |
| Anthropic auth: OAuth via claude.ai subscription OR API key | Pays for Claude calls | OAuth: covered by your claude.ai plan. API key: pay-as-you-go (~$3-5/run) |

Local tools — only if you choose Phase B Path 2 (CLI wizard):
- `git` (usually pre-installed)
- `bash` 3.2+ (default on macOS / Linux)
- `python3` (usually pre-installed)

---

# Phase A — Get your own copy

Click **Use this template** at the top of this repo's GitHub page →
**Create a new repository**.

Suggested settings:
- Name: `youtube-radar` (or anything you like)
- **Private** is fine — but Public works too, just remember:
  - Wiki and recommendations files will be public (the content of your digests)
  - me.md is public (your profile)
  - Secrets stay in claude.ai env-vars, NOT in repo — they're safe either way

Once created, you have **your own copy** at `github.com/<you>/youtube-radar`.

---

# Phase B — Configure your profile, lenses, and channels

You have two paths. Choose one:

- **Path 1** — Edit files in GitHub web editor (no install needed) — **5-10 min**
- **Path 2** — Clone + run `./setup.sh` interactive wizard locally — **7 min**

Both paths produce the same end state: a [`me.md`](me.md), [`channels.yaml`](channels.yaml), and [`seen.json`](seen.json)
in your repo that the cloud routine will read.

## Path 1 — GitHub web (recommended, no install)

### B1.1 — Open me.md in your repo's web editor

Click [`me.md`](me.md) in the file list → click the pencil ✏️ icon → web editor opens.

The file has clearly-marked `[PLACEHOLDER]` sections with inline examples
showing what good content looks like.

### B1.2 — Replace each placeholder

Walk through the file top to bottom:

- **Background** (3-5 sentences): your role, what you build, what you track
- **Lenses** (1-5 sections): each lens = name + goal + active questions + signal definition
- **Stop-list**: banalities to filter (start with 3-5 items, add more over time)
- **Output language**: keep `en` or change to `ru` etc.

Spend the most time on **lenses** — that's what filters your digest from
generic to personally useful. Avoid broad lenses ("Technology"); use specific
ones ("How AI-first orgs structure their PM teams").

### B1.3 — Commit me.md via GitHub UI

Scroll down → "Commit changes" → message "configure my profile" → Commit.

### B1.4 — Now edit channels.yaml

Same flow. The starter has 7 default channels (AI Engineer, Sequoia, etc.).

For each channel you want:
- Keep it (do nothing)
- Remove it (delete the block)
- Add new: paste a new block with the next priority number

To add a channel, you need its handle (e.g., `@lexfridman`). Order = priority:
on busy days, top-priority channels get processed first (quota is 5 per run).

Commit channels.yaml.

→ **Skip to Phase C.**

(You don't need to touch [`seen.json`](seen.json) — the routine maintains
it automatically. It tracks processed video IDs per channel for deduplication.
Missing or new channels are handled gracefully as empty.)

## Path 2 — Local CLI wizard

```bash
git clone https://github.com/<you>/youtube-radar.git
cd youtube-radar
./setup.sh
```

The wizard walks 4 steps:
1. Your name + background paragraph
2. Lenses (1-5, with descriptions)
3. Channels (paste handles, one per line)
4. Save to disk

It generates [`me.md`](me.md), [`channels.yaml`](channels.yaml), and updates [`seen.json`](seen.json). Then:

```bash
git add me.md channels.yaml seen.json
git commit -m "initial config from setup wizard"
git push
```

→ **Continue to Phase C.**

---

# Phase C — Wire up the cloud routine

This is the longest phase but each step is short. **Don't skip — order matters.**

## C1 — Install the Claude GitHub App on your repo

The cloud routine needs to clone your repo and push results back.
Anthropic's "Claude" GitHub App handles this.

1. Open [github.com/apps/claude](https://github.com/apps/claude)
2. Click **Install** (green button, top right)
3. Choose your account
4. **Repository access** → **Only select repositories** → pick `youtube-radar`
5. Install

You should see the install confirmation page redirect back to GitHub.

## C2 — Get your three secrets

Don't paste these into the repo or share them with anyone. You'll paste them
into claude.ai env-vars UI in step C3.

### C2.1 — Telegram bot token

This is what sends you the daily digest message.

1. In Telegram, search `@BotFather`
2. Send `/newbot` → give it any name and a unique handle (e.g., `mydigestbot`)
3. BotFather replies with a token like `1234567890:AAH_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
4. Copy and save this — you'll need it in step C3 as `TELEGRAM_BOT_TOKEN`
5. **Important**: find your new bot in Telegram and send it `/start` to activate

### C2.2 — Telegram chat ID

Tells the bot which user to send messages to.

1. In Telegram, search `@userinfobot`
2. Send `/start`
3. It replies with `Id: <numeric>` — that's your chat ID (8-10 digits)
4. Copy and save as `TELEGRAM_CHAT_ID`

### C2.3 — GitHub fine-grained PAT

Lets the routine push commits to your repo (cloud git proxy redirects pushes
to `claude/<branch>` instead of `main`; routine creates a PR and merges via
`gh` CLI which needs this token).

1. Open [github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)
2. **Generate new token (fine-grained)**
3. **Token name**: `youtube-radar-routine`
4. **Expiration**: 90 days (calendar reminder to rotate)
5. **Repository access** → **Only select repositories** → pick your `youtube-radar` repo
6. **Repository permissions**:
   - Contents → **Read and write**
   - Pull requests → **Read and write**
   - Everything else → No access
7. Click **Generate token**
8. Copy the token (shown once — save it!) as `GH_TOKEN`

### C2.4 — Anthropic auth (pick one)

Pays for Claude AI calls. Two options:

**Option A — OAuth setup-token (recommended if you have claude.ai Pro/Max/Team)**

1. In terminal: `claude setup-token`
2. Browser opens → authorize → copy the `sk-ant-oat-...` token shown
3. Save as `ANTHROPIC_TOKEN`

Counts against your claude.ai subscription quota — **no per-call billing**. If
you already pay $20/$200/etc. for claude.ai, the routine costs you nothing
extra (within your plan's fair-use limits).

**Option B — API key (pay-as-you-go from API balance)**

1. [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) → **Create Key**
2. Copy the `sk-ant-api03-...` value
3. Save as `ANTHROPIC_API_KEY`

Roughly a few dollars per run of 5 videos at Sonnet 4.x prices. Use this if
you want a separate accounting line (e.g., business expensing) or you don't
have a claude.ai subscription.

## C3 — Create the cloud Environment

Environment holds env vars (your secrets) and a setup script that runs before
each routine session.

1. Open [claude.ai/code](https://claude.ai/code)
2. Click the current environment selector in the session panel
3. Click **Add environment**
4. Fill in:

   **Name**: `youtube-radar`

   **Network access** → select **Custom** → check **"Also include default
   list of common package managers"** → in **Allowed domains** add (one per line):
   ```
   api.telegram.org
   youtube.com
   www.youtube.com
   m.youtube.com
   googlevideo.com
   *.googlevideo.com
   ytimg.com
   *.ytimg.com
   youtu.be
   ```

   **Why these domains**:
   - `api.telegram.org` — sends your digest messages
   - `youtube.com` + variants — fetches channel metadata
   - `*.googlevideo.com` — **where VTT subtitles live** (without this the
     pipeline can't get transcripts)
   - `*.ytimg.com` — thumbnails (warnings without are harmless)

   **Environment variables** (paste your secrets from step C2, format: `KEY=value`
   one per line, **no quotes**):
   ```
   TELEGRAM_BOT_TOKEN=<your token from C2.1>
   TELEGRAM_CHAT_ID=<your chat ID from C2.2>
   GH_TOKEN=<your PAT from C2.3>
   ```

   Plus one of:
   ```
   ANTHROPIC_API_KEY=<from C2.4 option A>
   ```
   OR
   ```
   ANTHROPIC_TOKEN=<from C2.4 option B>
   ```

   ⚠️ **Anthropic doc warning**: "_env vars are visible to anyone who can
   edit this environment_". On personal accounts this is fine. On team
   accounts, only invite trusted collaborators.

   **Setup script** (Bash):
   ```bash
   #!/bin/bash
   set -e

   # Install yt-dlp via pip
   pip install yt-dlp

   # Disable broken PPAs in cloud env (ppa.launchpadcontent.net returns 403).
   sed -i.bak '/ppa\.launchpadcontent\.net/s/^deb /# deb_disabled /' /etc/apt/sources.list.d/*.list 2>/dev/null || true

   apt-get update || true
   apt-get install -y gh
   ```

   **Why disable PPAs**: cloud env ships with `deadsnakes/ppa` and `ondrej/php`
   pre-configured. Both currently return 403 Forbidden on `apt update`, exit
   code 100, setup fails, routine doesn't start. The sed line comments them
   out before `apt update`.

5. Save the environment.

## C4 — Create the Routine

1. Open [claude.ai/code/routines](https://claude.ai/code/routines) → **New routine**

2. **Name**: `youtube-radar-digest`

3. **Instructions** (the textarea): paste this **wrapper-pattern** prompt
   exactly:

   ```
   You are the Orchestrator routine of youtube-radar.

   First, read .claude/orchestrator.md from the cloned repository. That file
   is your complete operational manual: watcher logic, video selection,
   subagent invocation, Telegram formatting, auto-merge handling.

   Follow it precisely. The file may be updated between runs — always use
   the version in the repo, not your memory.

   Also read README.md and CLAUDE.md for context.

   Required env vars (already in your environment): TELEGRAM_BOT_TOKEN,
   TELEGRAM_CHAT_ID, GH_TOKEN, plus ANTHROPIC_API_KEY or ANTHROPIC_TOKEN.
   ```

   **Why wrapper-pattern**: when you update logic in `.claude/orchestrator.md`
   and push to your repo, the routine picks it up automatically on the next
   run. If you paste the full orchestrator into Instructions, it goes stale
   and you'd have to remember to update both file AND UI. Wrapper avoids
   this completely.

4. **Model selector** (inside prompt input): choose **Claude Sonnet 4.x**
   (cheap + sufficient). Opus 4.7 works too but costs more.

5. **Select repositories**: add your `youtube-radar` repo. Appears in the
   list after the GitHub App is installed in step C1.

6. **Select an environment**: pick `youtube-radar` (the one you created in C3).

7. **Select a trigger** → choose **Schedule**:
   - Custom cron expression: `0 6 * * *` (06:00 UTC = customize for your morning)
   - Timezone — your local; auto-converted

8. **Permissions tab** (at the bottom): enable **"Allow unrestricted branch pushes"**
   for your repo.

   ⚠️ **Known to silently fail in research preview** — routine still pushes
   to `claude/*` despite toggle. Workaround is baked into orchestrator
   (auto-merge via `gh` + REST API branch delete). Toggle ON anyway.

9. **Connectors tab**: leave only what's actually needed. Default may include
   Google Drive, Slack, etc. — remove them; we don't use them.

10. **Create**.

## C5 — Test the routine

On the routine's page click **Run now**.

A new session appears in the sidebar. Click into it to watch live output.

Expected sequence (~15-20 min):
1. Reads README.md, channels.yaml, seen.json
2. Walks through all active channels sequentially (yt-dlp watcher)
3. Finds N new videos (up to 10 per channel, quota caps at 5 per run)
4. For each: yt-dlp transcript → Extractor subagent → Synthesizer subagent →
   Telegram message → seen.json append
5. End: STATUS.md regenerated, git push (which redirects to `claude/*`, then
   auto-merged via `gh`)

**What should arrive**:
- Up to 5 Telegram messages from your bot, each with:
  - 🧩 Root tensions from the video
  - 💡 Most original idea
  - 📚 Wiki · 🎯 Recommendations · ▶️ YouTube links
- New commit on `main`: `routine YYYYMMDD-HHMM: processed N videos`
- Files `wiki/<base>.md`, `recommendations/<base>.md` in your repo
- Updated `STATUS.md` and entries in `logs/runs-YYYY-MM.jsonl`

---

# Troubleshooting

Open the failed session (routine page → click into a past run).

| Symptom | Likely cause | Fix |
|---|---|---|
| `Setup script failed exit 100` | broken PPAs not disabled before apt | Step C3, verify your setup script matches exactly |
| `Could not clone repository` | Claude GitHub App not installed | Step C1, install on the right repo |
| `yt-dlp: command not found` | setup script didn't run | Wait — first session rebuilds env cache (~1 min) |
| `Host not in allowlist` | network allowlist missing a domain | Step C3, re-check Allowed domains |
| `curl: ... api.telegram.org` blocked | Telegram domain missing | Step C3, add `api.telegram.org` to Allowed domains |
| `refusing to push to main` | "Allow unrestricted branch pushes" off | Step C4 step 8 (note: known to silently fail; orchestrator handles via `gh pr merge` workaround) |
| `Telegram 401` | invalid `TELEGRAM_BOT_TOKEN` | Step C2.1, regenerate via @BotFather, update env |
| `Telegram 400 chat not found` | wrong `TELEGRAM_CHAT_ID` or you never `/start`'d the bot | Open Telegram, find your bot, press Start |
| `Anthropic 401 invalid x-api-key` | API key revoked / wrong / whitespace | Step C2.4, regenerate at console.anthropic.com |
| All transcripts return 403 / "Sign in to confirm bot" | YouTube IP rate-limit on Anthropic cloud | Wait 1-3 hours; if persistent, see README known limitations |

For specific cloud routine details see [.claude/setup-routine.md](.claude/setup-routine.md).

---

# What happens next

After your first successful Run now:

- ✅ Daily 06:00 UTC, routine fires automatically
- ✅ For 24h-old new videos on your channels: Extractor + Synthesizer → Telegram
- ✅ Empty days (no new videos): silent, just a watcher log entry
- ✅ Error days: 🚨 alert in Telegram with link to STATUS.md

**STATUS.md dashboard** on your repo's main branch shows: last 10 runs,
processed count, error count, token cost, current backlog. Open it any
time to check health.

**Adjusting later**:
- Edit [`me.md`](me.md) to change profile or lenses (commit + push, next run picks up)
- Edit [`channels.yaml`](channels.yaml) to add/mute channels
- All edits via GitHub web are fine — the routine reads from your repo
  on every run

See [CONFIGURATION.md](CONFIGURATION.md) for every knob.
