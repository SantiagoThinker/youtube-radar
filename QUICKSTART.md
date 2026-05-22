# Quickstart — 15 minutes to first digest

End-to-end setup, from cloned repo to first Telegram digest in your chat.

---

## Prerequisites (5 min)

You need accounts on:
- **claude.ai** (Pro / Max / Team / Enterprise) with **Claude Code on the web** enabled. This is where the routine actually runs. [Sign up](https://claude.ai).
- **GitHub** — to host the repo this routine reads/writes
- **Telegram** — to receive digests
- **Anthropic API key** OR **claude.ai subscription** — the routine consumes Claude usage to run agents

Local tools (only for setup wizard; routine itself runs in cloud):
- `git` — usually pre-installed
- `gh` (GitHub CLI) — `brew install gh` on macOS
- `yt-dlp` — `brew install yt-dlp` (optional; you can verify channels without it)
- `python3` — usually pre-installed

---

## Step 1 — Clone and configure (5 min)

```bash
git clone https://github.com/<YOUR_ORG>/youtube-radar.git
cd youtube-radar
./setup.sh
```

The wizard asks:

1. **Your name** — used in `me.md` for personalized prompts
2. **Background paragraph** — 3-5 sentences about your context (role, company, what you build). The Synthesizer uses this to filter relevance.
3. **Lenses** — pick from common ones or define custom:
   - Career — "I'm looking for X kind of role"
   - Startup — "I'm building Y, exploring Z"
   - Industry radar — "I track trends in field W"
   - Investment thesis — "I evaluate companies in space V"
   - Skill building — "I'm learning U"
   - Custom — your own focus
4. **YouTube channels** — paste handles (one per line). Order = priority (most important first).
5. **Telegram bot token** — see "Telegram bot setup" below
6. **Telegram chat_id** — see same section
7. **GitHub PAT** (fine-grained) — see "GitHub token setup" below
8. **Anthropic auth** — pick API key OR OAuth setup-token (see "Anthropic auth" below)

The wizard creates:
- `me.md` from your inputs
- `channels.yaml` with your channels + priority
- `secrets.env` in `~/.config/youtube-radar/` (mode 600, never committed) — env vars for the routine

---

## Step 2 — Push to your GitHub (2 min)

```bash
gh repo create youtube-radar --private --source=. --remote=origin
git add .
git commit -m "initial setup from wizard"
git push -u origin main
```

If you already have a repo, just `git remote set-url` and push.

---

## Step 3 — Install Claude GitHub App on this repo (2 min)

The routine needs to clone and push to your repo. Anthropic's "Claude" GitHub App handles this.

1. Open [github.com/apps/claude](https://github.com/apps/claude)
2. Click **Install** (green button, top right)
3. Choose your account
4. **Repository access** → **Only select repositories** → pick `youtube-radar`
5. Install

---

## Step 4 — Create the cloud Environment (3 min)

Environment holds env vars (secrets) and a setup script that runs before each routine session.

1. Open [claude.ai/code](https://claude.ai/code)
2. Click the current environment selector in the session panel
3. **Add environment**
4. **Name**: `youtube-radar`
5. **Network access** → **Custom** → check **"Also include default list of common package managers"** → add to **Allowed domains**:
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
6. **Environment variables**: open `~/.config/youtube-radar/secrets.env` from your local machine, copy each `KEY=value` line, paste into the env vars field
7. **Setup script** (Bash):
   ```bash
   #!/bin/bash
   set -e

   pip install yt-dlp

   # Disable broken PPAs in cloud env (ppa.launchpadcontent.net returns 403)
   sed -i.bak '/ppa\.launchpadcontent\.net/s/^deb /# deb_disabled /' /etc/apt/sources.list.d/*.list 2>/dev/null || true

   apt-get update || true
   apt-get install -y gh
   ```
8. **Save**

---

## Step 5 — Create the Routine (3 min)

1. Open [claude.ai/code/routines](https://claude.ai/code/routines) → **New routine**
2. **Name**: `youtube-radar-digest`
3. **Instructions** (the prompt) — paste this thin wrapper:
   ```
   You are the Orchestrator routine of youtube-radar.

   First, read .claude/orchestrator.md from the cloned repository. That file
   is your complete operational manual: watcher logic, video selection,
   subagent invocation, Telegram formatting, auto-merge handling.

   Follow it precisely. The file may be updated between runs — always use
   the version in the repo, not your memory.

   Also read README.md and CLAUDE.md for context.

   Required env vars (already in your environment): TELEGRAM_BOT_TOKEN,
   TELEGRAM_CHAT_ID, GH_TOKEN.
   ```
4. **Repositories** → select your `youtube-radar` repo
5. **Environment** → select `youtube-radar` (created in Step 4)
6. **Trigger** → **Schedule** → custom cron `0 6 * * *` (06:00 UTC = customize for your morning)
7. **Permissions** tab → enable **"Allow unrestricted branch pushes"** for `youtube-radar` (note: known to silently fail in research preview — orchestrator works around it via `gh pr merge`)
8. **Create**

---

## Step 6 — Test it (1 min)

On the routine's detail page, click **Run now**.

A new session appears in your sidebar. Click into it to watch live.

Expected sequence:
1. Reads README + orchestrator.md from repo
2. Loads channels.yaml + seen.json (initially empty)
3. Sequential watcher across your channels — finds new videos
4. Picks up to 5 by deterministic priority
5. For each: yt-dlp transcript → Extractor → Synthesizer → Telegram
6. Commits everything, auto-merges PR

Total time: ~15-20 minutes for 5 videos.

**You should receive Telegram messages** with the TL;DR format. If not, check `logs/runs-YYYY-MM.jsonl` and `STATUS.md` (auto-generated) on your GitHub repo's main branch.

---

## Telegram bot setup

1. Open Telegram, search `@BotFather`
2. `/newbot` → give it a name and a unique handle (e.g., `mydigestbot`)
3. BotFather returns the API token (format `1234567890:AAH_xxxxxxxxxx`) — this is `TELEGRAM_BOT_TOKEN`
4. Find your bot in Telegram, send `/start` to activate it
5. To get your `chat_id`: search `@userinfobot`, send `/start`, it replies with your numeric ID (8-10 digits)

⚠️ Never paste these values into chat with AI assistants or anywhere outside `setup.sh` or the claude.ai env UI.

---

## GitHub token setup

1. [github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta) → **Generate new token (fine-grained)**
2. **Token name**: `youtube-radar-routine`
3. **Expiration**: 90 days (set a reminder to rotate)
4. **Repository access** → **Only select repositories** → pick your `youtube-radar` repo
5. **Repository permissions**:
   - Contents → Read and write
   - Pull requests → Read and write
   - Everything else → No access
6. Generate, copy the token (shown once)

The routine uses this to merge PRs (cloud git proxy redirects pushes to `claude/<branch>` instead of `main`; routine creates a PR and merges it via `gh` CLI).

---

## Anthropic auth

Two options, pick one:

### Option A: API key (recommended for predictable cost)

1. [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) → **Create Key**
2. Paste into the wizard when prompted — wizard stores in `secrets.env` as `ANTHROPIC_API_KEY`

Cost: pay-as-you-go from API credits.

### Option B: OAuth setup-token (uses claude.ai subscription)

1. In terminal: `claude setup-token`
2. Browser opens → authorize → copy the `sk-ant-oat-...` token shown
3. Paste into wizard — stored as `ANTHROPIC_TOKEN`

Cost: counts against your claude.ai subscription quota.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Routine starts but `setup script failed exit 100` | broken PPAs in cloud env | Use the setup script in Step 4 exactly — it disables them |
| Watcher works, transcripts all 403 | YouTube IP-blocked Anthropic cloud subnet | Wait 1-3h; if persistent see [ARCHITECTURE.md](ARCHITECTURE.md) § known limitations |
| Telegram silent, no error in logs | bot token invalid (revoked, typo, whitespace) | Regenerate via `@BotFather`, update env via routine UI |
| Telegram returns `chat not found` | you haven't sent `/start` to your bot from your own account | Open the bot in Telegram, press Start |
| PR created but not merged | `gh` PAT lacks Contents+PullRequests | Regenerate with correct scopes (Step "GitHub token setup") |
| Routine doesn't pick up edits to `orchestrator.md` | routine Instructions cached old version | Don't paste full orchestrator into Instructions — keep it as a thin wrapper that reads `.claude/orchestrator.md` (Step 5 instructions show the wrapper) |

See [CHANGELOG.md](CHANGELOG.md) for the full history of issues and fixes encountered during the original development.
