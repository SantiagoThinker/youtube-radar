# Routine setup — claude.ai UI walkthrough

Step-by-step instructions for setting up the cloud routine. Based on official docs (`code.claude.com/docs/en/routines` and `code.claude.com/docs/en/claude-code-on-the-web`), not memory.

If the UI doesn't match this description in some detail — follow the official docs, not memory.

---

## Prerequisites (must be true before starting)

- [ ] **Subscription**: Pro / Max / Team / Enterprise with **Claude Code on the web** enabled
- [ ] **Claude GitHub App** installed on your account with access to your `youtube-radar` repo ([github.com/apps/claude](https://github.com/apps/claude) → Install → Only select repositories → youtube-radar)
- [ ] **Telegram bot** created via `@BotFather`, token obtained, bot activated (you sent `/start` to it)
- [ ] **Telegram chat_id** known (from `@userinfobot`)
- [ ] **GitHub fine-grained PAT** with Contents+PullRequests on the repo
- [ ] **Anthropic auth** (API key or OAuth setup-token)

If any prerequisite is missing, see [QUICKSTART.md](../QUICKSTART.md) sections at the bottom.

---

## Part 1 — Create the Environment (claude.ai/code)

**Why**: env holds your secrets (tokens), setup script (installs yt-dlp + gh), and custom network allowlist (Telegram + YouTube). Without a custom env, the routine will fail on multiple steps.

### Steps

1. Open [claude.ai/code](https://claude.ai/code).
2. Open the current environment selector in the session panel (per docs: "Select the current environment to open the selector").
3. Click **Add environment**.
4. Fill in:

   **Name**: `youtube-radar`

   **Network access**: select **Custom**.
   - Check **"Also include default list of common package managers"** (gives you GitHub, PyPI, etc.)
   - In **Allowed domains**, add (one per line):
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
   - `api.telegram.org` — Bot API for notifications (NOT in default Trusted)
   - `youtube.com` + variants — channel pages and metadata for yt-dlp
   - `*.googlevideo.com` — Google CDN, **where VTT subtitles live**. Without this domain the transcript won't download and the pipeline is useless.
   - `*.ytimg.com` — thumbnails; warnings without it are harmless but kept anyway
   - `youtu.be` — short URLs, just in case

   **Symptom if YouTube isn't allowlisted**: routine fails on the first channel with `Host not in allowlist`. Lesson learned during research preview.

   **Environment variables** (format `.env`, **no quotes around values**):
   ```
   TELEGRAM_BOT_TOKEN=<your fresh token from BotFather>
   TELEGRAM_CHAT_ID=<your numeric chat_id from @userinfobot>
   GH_TOKEN=<your fine-grained PAT>
   ```
   (No Anthropic token needed — the routine uses your claude.ai subscription session for all Claude calls, including Extractor and Synthesizer subagents.)

   **GH_TOKEN — how to get a fine-grained PAT** (needed for auto-merge):
   1. [github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta) → **Generate new token (fine-grained)**
   2. **Token name**: `youtube-radar-routine`
   3. **Expiration**: 90 days (set a calendar reminder to rotate)
   4. **Repository access** → **Only select repositories** → pick your repo
   5. **Repository permissions**:
      - **Contents** → Read and write
      - **Pull requests** → Read and write
      - everything else → No access
   6. **Generate token** → copy (shown once)
   7. Paste into env vars — token is hidden after save

   `gh` CLI reads `GH_TOKEN` automatically; no `gh auth login` needed.

   **Setup script** (Bash):
   ```bash
   #!/bin/bash
   set -e

   # Install yt-dlp via pip
   pip install yt-dlp

   # Disable broken PPAs in cloud env (ppa.launchpadcontent.net returns 403).
   # Match by file CONTENT (not filename) — safer against naming variations.
   sed -i.bak '/ppa\.launchpadcontent\.net/s/^deb /# deb_disabled /' /etc/apt/sources.list.d/*.list 2>/dev/null || true

   # Belt+suspenders: || true on update in case of any other transient failure
   apt-get update || true

   apt-get install -y gh
   ```

   **Why disable PPAs**: cloud env ships with `deadsnakes/ppa` and `ondrej/php` pre-configured. Both currently return 403 Forbidden on `apt update`, exit code 100, setup script fails, routine doesn't start. Match by content (sed `/ppa.launchpadcontent.net/...`) is robust against filename variations.

   **Why apt update || true**: belt+suspenders. Even with PPAs disabled, occasional transient network failures shouldn't kill setup.

5. Save the environment.

### Known caveat from Anthropic docs

> "Both environment variables and setup scripts are stored in the environment configuration, **visible to anyone who can edit that environment**. If you need secrets in a cloud session, add them as environment variables with that visibility in mind."

On a personal account that's fine (only you can edit). On a team account, treat env vars as visible-to-teammates.

---

## Part 2 — Create the Routine (claude.ai/code/routines)

1. Open [claude.ai/code/routines](https://claude.ai/code/routines) → **New routine**.

2. **Name**: `youtube-radar-digest`

3. **Instructions** (the textarea): paste this **wrapper-pattern** prompt (not the whole orchestrator):
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

   **Why wrapper-pattern**: when you update logic in `.claude/orchestrator.md` and `git push`, the routine picks it up automatically on the next run. If you paste the full orchestrator into Instructions, it becomes stale and you have to remember to update both the file AND the UI. Bad.

4. **Model selector** (inside prompt input): keep Claude Opus 4.7 (1M context) or downgrade to Sonnet 4.7 — for our task Sonnet is enough and cheaper. Choose Sonnet for cost-effectiveness.

5. **Select repositories**: add your `youtube-radar` repo. Should appear in the list after the GitHub App is installed.

6. **Select an environment**: pick `youtube-radar` (created in Part 1).

7. **Select a trigger** → choose **Schedule**:
   - Daily preset, or custom cron `0 6 * * *` (06:00 UTC = customize for your morning)
   - Timezone — your local; auto-converted.

8. **Permissions tab** (at the bottom of the form): enable **"Allow unrestricted branch pushes"** for the repo.

   ⚠️ **Known to silently fail in research preview** — routine still pushes to `claude/*` despite toggle. Workaround is baked into orchestrator (auto-merge via `gh` + REST API branch delete). Toggle it ON anyway; if it ever starts working, branches will go straight to main.

9. **Connectors tab**: leave only what's actually needed. Default Connectors list may include Google Drive, Slack, etc. — remove them; we don't use them. GitHub access is handled separately via the App.

10. **Create**.

---

## Part 3 — Test run + verify

1. On the routine's page click **Run now**.

2. A session appears (or shows up in the sidebar). Click into it — you'll see live agent output.

3. What should happen (orchestrator-prompt step order):
   - Reads README.md, channels.yaml, seen.json
   - Walks through all active channels, runs yt-dlp watcher
   - Finds N new videos (on first run — up to 10 per channel × 7 channels, quota caps at 5)
   - For each: yt-dlp transcript → Extractor → Synthesizer → Telegram → seen.json append
   - End: `git add -A && git commit && git push origin main` (likely redirected to `claude/*`, then auto-merged via gh)

4. **Time for first run**: 15-20 minutes for 5 videos (varies by transcript length).

5. **What should arrive**:
   - 5 Telegram messages from your bot with TL;DR + 3 links (wiki / recommendations / YouTube)
   - New commit on main: `routine YYYYMMDD-HHMM: processed N videos`
   - Files `wiki/<base>.md`, `recommendations/<base>.md` for processed videos
   - Updated `STATUS.md` and entries in `logs/runs-YYYY-MM.jsonl`

---

## Part 4 — Refining the schedule (optional)

Current setting: `0 6 * * *` — once daily at 06:00 UTC (morning digest).

Per Anthropic docs: "*Pick the closest preset in the form, then run `/schedule update` in the CLI to set a specific cron expression. The minimum interval is one hour.*"

In Claude Code CLI:
```
/schedule update
```

Pick `youtube-radar-digest`. Change cron to your preference:
- `0 6 * * *` — daily morning (default, recommended)
- `0 6,18 * * *` — twice a day, morning + evening (use only if you really need faster latency)

If the `/schedule update` command isn't available in your Claude Code version, set it via the routine UI directly.

**Why daily by default**:
- Quota = 5 videos / run; daily × 5 = 35/week ≈ matches inflow (10-15/week typical)
- Less Telegram noise (1 batch in morning vs multiple random pushes)
- **More frequent runs trigger YouTube IP rate-limit** on Anthropic's shared cloud subnet — observed in production. Sub-12h cron is not recommended.
- Trade-off: new videos arrive within ≤24h instead of real-time. Acceptable for a digest workflow.

---

## If something fails

Open the failed session (routine page → click into the run).

Common errors and fixes:

| Error | Likely cause | Fix |
|---|---|---|
| `Setup script failed exit code 100` | broken PPAs in cloud env | Verify setup script in Part 1 disables them via sed BEFORE apt update |
| `Could not clone repository` | GitHub App not installed on repo | Re-install at [github.com/apps/claude](https://github.com/apps/claude) with access to your repo |
| `yt-dlp: command not found` | setup script didn't run | Verify setup script saved; one warm-up run may be needed to cache the env |
| `curl: ... blocked by proxy` / `api.telegram.org: connection refused` | Telegram domain missing from allowlist | Part 1, Custom Network Access → check `api.telegram.org` is in Allowed domains |
| `refusing to push to main` / `protected branch` | "Allow unrestricted branch pushes" not enabled | Part 2 step 8. Note: known to fail silently; orchestrator's auto-merge workaround handles it |
| `Telegram returned 401` | invalid TELEGRAM_BOT_TOKEN | Recheck token: no quotes, no whitespace; regenerate via @BotFather if needed |
| `Telegram returned 400 chat not found` | wrong chat_id or you never `/start`'d the bot | Open Telegram, find your bot, press Start |
| `Anthropic 401 invalid x-api-key` | API key revoked / wrong / has whitespace | Verify at [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys), regenerate if needed |
| All transcripts return 403 / "Sign in to confirm bot" | YouTube IP rate-limit | Wait 1-3 hours; if persistent, see README known limitations |

After fixing — **Run now** again. Sessions auto-pick up env changes; setup script may rebuild cache (~1 min on first new session).

---

## Sources

- [Automate work with routines — code.claude.com/docs/en/routines](https://code.claude.com/docs/en/routines)
- [Use Claude Code on the web — code.claude.com/docs/en/claude-code-on-the-web](https://code.claude.com/docs/en/claude-code-on-the-web)
