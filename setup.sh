#!/bin/bash
# setup.sh — interactive setup wizard for youtube-radar.
#
# Collects: profile, lenses, channels.
# Outputs (in repo, committed to git):
#   - me.md
#   - channels.yaml
#   - seen.json
#
# Secrets policy: the wizard NEVER touches secrets. They flow directly from
# their source (BotFather, GitHub, Anthropic) → your clipboard → claude.ai
# routine env-vars UI. No file, no terminal echo, no shell history risk.
# Final summary shows exactly where to get each secret and where to paste it.

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME_TEMPLATE="$REPO_DIR/me.template.md"
ME_TARGET="$REPO_DIR/me.md"
CHANNELS_TEMPLATE="$REPO_DIR/channels.template.yaml"
CHANNELS_TARGET="$REPO_DIR/channels.yaml"

# ─── Helpers ─────────────────────────────────────────────────────────────────

color_bold="\033[1m"
color_dim="\033[2m"
color_red="\033[31m"
color_green="\033[32m"
color_blue="\033[34m"
color_yellow="\033[33m"
color_reset="\033[0m"

say() {
    printf "${color_blue}▶${color_reset} ${color_bold}%s${color_reset}\n" "$1"
}

ok() {
    printf "${color_green}✓${color_reset} %s\n" "$1"
}

warn() {
    printf "${color_yellow}⚠${color_reset} %s\n" "$1"
}

note() {
    printf "${color_dim}%s${color_reset}\n" "$1"
}

ask() {
    # $1 = prompt, $2 = optional default
    local prompt="$1"
    local default="${2:-}"
    local result
    if [ -n "$default" ]; then
        printf "${color_bold}%s${color_reset} ${color_dim}[%s]${color_reset}: " "$prompt" "$default"
    else
        printf "${color_bold}%s${color_reset}: " "$prompt"
    fi
    read -r result
    echo "${result:-$default}"
}

ask_multiline() {
    # $1 = prompt. Reads until line containing exactly "END" (case-insensitive).
    # Why a sentinel instead of empty-line: pasted multi-paragraph content
    # often has internal blank lines, which would prematurely end input.
    local prompt="$1"
    local result=""
    local line_upper
    printf "\n${color_bold}%s${color_reset}\n" "$prompt"
    printf "${color_yellow}┌─────────────────────────────────────────────────────────────────────┐${color_reset}\n"
    printf "${color_yellow}│${color_reset}  ${color_bold}How to finish:${color_reset} type ${color_bold}END${color_reset} on its own line, then press Enter.        ${color_yellow}│${color_reset}\n"
    printf "${color_yellow}│${color_reset}  Case-insensitive — 'end', 'END', 'End' all work.                  ${color_yellow}│${color_reset}\n"
    printf "${color_yellow}│${color_reset}  Blank lines inside your text are fine — they don't end input.     ${color_yellow}│${color_reset}\n"
    printf "${color_yellow}└─────────────────────────────────────────────────────────────────────┘${color_reset}\n"
    echo
    while IFS= read -r line; do
        # Case-insensitive END check (works in bash 3.2 on Mac)
        line_upper=$(echo "$line" | tr '[:lower:]' '[:upper:]')
        [ "$line_upper" = "END" ] && break
        result+="$line"$'\n'
    done
    echo "$result"
}

pause() {
    printf "${color_dim}Press Enter to continue...${color_reset}"
    read -r
}

# ─── Header ──────────────────────────────────────────────────────────────────

clear
cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │                                                                     │
  │   youtube-radar — your personal AI video assistant                  │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘

  What you're setting up:

  A daily digest of YouTube content filtered specifically for YOU.
  Instead of spending hours watching hour-long interviews to find the
  3 minutes worth your time, you get a Telegram message every morning
  with:

    • Root tensions discussed in each video
    • The most contrarian / non-obvious idea
    • Bullets specifically relevant to YOUR focus areas
    • An honest "skip" when the video has nothing for you

  How it works:

  This wizard generates 3 config files (~7 min):
    Step 1 — Who you are (so AI tailors content to YOU)
    Step 2 — Your focus areas (so AI knows what to look for)
    Step 3 — Which channels to watch
    Step 4 — Save your answers to files (no more questions)

  Secrets (Telegram / GitHub / Anthropic tokens) are NEVER collected by
  this wizard. The final summary shows exactly where to get each one
  and where to paste it (claude.ai env-vars UI). They never touch this
  script, your shell history, or disk.

  Press Ctrl+C any time to abort and restart.

EOF

pause
clear

# ─── Step 1: profile ─────────────────────────────────────────────────────────

cat <<'EOF'

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 1 of 4 — Tell us about you            (~2 minutes)            │
  └─────────────────────────────────────────────────────────────────────┘

  Why this matters:

    The AI watching YouTube on your behalf has no idea who you are.
    Without context, it gives generic "this video is interesting"
    summaries. Boring. Useless.

    With context, it asks "would THIS PERSON find THIS video useful?" —
    and produces sharply targeted recommendations.

  Two questions coming up:

    1) Your first name
       Just used to personalize prompts. No surveillance.

    2) A short background paragraph
       3-5 sentences. Who are YOU professionally, what are YOU building,
       what's important to YOU right now. The AI uses this to filter
       relevance.

       ⚠️  WRITE YOUR OWN — don't copy the example below. The example is
       just to show the LEVEL of specificity that works well.

       Example of a useful (but FICTIONAL) background:

         "I'm Chief Product Officer at a Series B AI-first SaaS company
          (~150 people, $30M ARR). We ship agentic workflows for
          enterprise customers and I'm scaling product org from 8 to 20
          PMs over the next year. Right now I'm tracking: how to
          structure PM teams around AI capabilities (not features), how
          peer CPOs handle the quarterly model-shift cadence, and where
          enterprise buyers will pay premium for outcomes vs seats."

       Notice the example has: concrete role, company stage with numbers,
       active project, and three specific tracking topics. THAT level of
       specificity (about YOUR situation) is what the AI needs.

       A background like "I work in tech" is too vague — the AI will
       give you generic summaries.

EOF

NAME=$(ask "Your first name")
echo
say "Now your background paragraph (3-5 sentences):"
echo
BACKGROUND=$(ask_multiline "Paste your background paragraph")

if [ -z "$BACKGROUND" ]; then
    warn "Background is empty. The AI will produce generic recommendations."
    warn "Strongly recommend going back and adding context."
fi

clear

# ─── Step 2: lenses ──────────────────────────────────────────────────────────

cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 2 of 4 — Define your lenses           (~3 minutes)            │
  └─────────────────────────────────────────────────────────────────────┘

  Why lenses:

    The same video can be useful for completely different reasons.
    A CEO interview might be:
      • Career inspiration (if you're searching for a role)
      • Investment thesis (if you evaluate that company's space)
      • Leadership lessons (if you're growing your org)
      • Market signal (if you track that industry)

    Without lenses, the AI summarizes ALL these angles for every video.
    You waste time on dimensions you don't care about.

    WITH lenses, the AI produces a separate section per lens. If a video
    doesn't apply to one of yours, it honestly says "no insights here" —
    instead of writing fluff bullets you'll skim and forget.

  How to define a good lens:

    Each lens needs:
      • Short name (becomes section header in the digest)
      • Description: your specific goal + what counts as signal vs noise

    Examples of FOCUSED lenses (don't copy — make yours specific):

      ▸ Career — "I'm searching for a Head of Product role at AI-first
        B2B SaaS in EU/US. I care about: revenue-generating agents in
        core (not just features), owned P&L, meaningful equity, Series
        B+ traction. Signal = concrete numbers from CEOs, names of
        companies hiring, contrarian observations about AI-first org
        structure."

      ▸ Startup thesis — "I'm exploring an AgentOps governance startup
        for AI agents in enterprise. I care about: real customer pain
        in agent governance, unit economics, regulatory landscape,
        competitor moves. Signal = practitioners describing what's
        broken in production agent systems."

      ▸ Tech radar — "I track capability shifts in agentic systems.
        Signal = concrete benchmark numbers, new architectural patterns
        from researchers, production observations from practitioners.
        NOT signal = AGI timeline predictions, generic capability claims
        without evidence."

  Bad lens example: "Technology" — too broad, AI will refuse most bullets.
  Good lens example: "How AI-first product orgs structure their PM teams"
                     — specific enough that AI knows what to scan for.

  You can have 1-5 lenses. Most people start with 2-3.

EOF

pause
echo
say "Add your lenses one by one. Just press Enter on empty Lens name when you're done."

LENSES_MD=""
LENS_NUM=1
while true; do
    echo
    LENS_NAME=$(ask "Lens #$LENS_NUM name (or empty to finish)")
    [ -z "$LENS_NAME" ] && break
    echo
    note "Now describe lens '$LENS_NAME': your goal, active questions, what's signal vs noise."
    LENS_DESC=$(ask_multiline "Description")
    if [ -z "$LENS_DESC" ]; then
        warn "Empty description — skipping this lens."
        continue
    fi
    LENSES_MD+="### $LENS_NAME

$LENS_DESC
"
    LENS_NUM=$((LENS_NUM + 1))
    [ $LENS_NUM -gt 5 ] && { warn "Reached maximum of 5 lenses."; break; }
done

if [ -z "$LENSES_MD" ]; then
    warn "No lenses defined. At least one lens is required. Restart the wizard."
    exit 1
fi

clear

cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 2b — Stop-list (what you ALREADY know)                        │
  └─────────────────────────────────────────────────────────────────────┘

  Why this matters:

    Without a stop-list, the AI will keep surfacing the same well-known
    "insights" every day. You'll get tired of reading the same things
    you already know — and start ignoring the digests entirely.

    The stop-list explicitly tells the AI: "Don't bother me with this
    framing — I've heard it 100 times."

  Examples of items you might add:

    • "AI is changing everything" — generic framings
    • Basic RAG / fine-tuning / prompt engineering explanations
    • "Distribution beats technology" — startup truisms
    • Generic "how to be a great PM" advice (Lenny's-style)
    • AGI timeline predictions
    • Anything you've heard in 20+ podcasts already

  You can leave this empty and add to it over time as you notice
  patterns in your digest you want filtered out (edit me.md any time).

  One item per line.

EOF

STOPLIST=$(ask_multiline "Stop-list items (one per line)")

if [ -z "$STOPLIST" ]; then
    STOPLIST="(none yet — add patterns over time as the Synthesizer surfaces things you already know)"
fi

clear

# ─── Step 3: channels ────────────────────────────────────────────────────────

cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 3 of 4 — Choose channels              (~2 minutes)            │
  └─────────────────────────────────────────────────────────────────────┘

  Why channels matter:

    Quality of channels = quality of digest. The AI can only filter the
    raw signal that's already there. If you pick channels with low
    signal density, you'll get few useful recommendations.

    Pick channels that:
      • Have practitioners (not just analysts) sharing concrete numbers
      • Match your focus areas
      • Post regularly (otherwise watcher mostly does nothing)

  How to add:

    Paste @handles, one per line. Examples:
      @lexfridman
      @ycombinator
      @NoPriorsPodcast
      @aiDotEngineer

    Order = priority. If many channels post on the same day, top-of-list
    ones get processed first (quota is 5 videos per day).

    Tip: don't add too many right away. Start with 5-7 you actually
    follow. You can always add more later (edit channels.yaml).

  If you skip this step (just type END immediately), the wizard uses
  default channels: @aiDotEngineer, @sequoiacapital, @NoPriorsPodcast,
  @ycombinator, @LennysPodcast, @lexfridman, @allin.

EOF

HANDLES=$(ask_multiline "Your channels (one @handle per line)")

if [ -z "$HANDLES" ]; then
    note "No channels entered — using default set from channels.template.yaml"
    cp "$CHANNELS_TEMPLATE" "$CHANNELS_TARGET"
else
    note "Building channels.yaml with your priority order..."
    {
        echo "# Generated by setup.sh. Channels listed in priority order (top = highest)."
        echo ""
        echo "channels:"
        PRIO=1
        while IFS= read -r handle; do
            [ -z "$handle" ] && continue
            handle="${handle#@}"
            handle="@$handle"
            echo "  - handle: \"$handle\""
            echo "    priority: $PRIO"
            echo "    active: true"
            echo "    notes: \"\""
            echo ""
            PRIO=$((PRIO + 1))
        done <<< "$HANDLES"
    } > "$CHANNELS_TARGET"

    {
        echo "{"
        FIRST=1
        while IFS= read -r handle; do
            [ -z "$handle" ] && continue
            handle="${handle#@}"
            handle="@$handle"
            if [ $FIRST -eq 1 ]; then
                FIRST=0
            else
                echo ","
            fi
            printf "  \"%s\": []" "$handle"
        done <<< "$HANDLES"
        echo ""
        echo "}"
    } > "$REPO_DIR/seen.json"
fi

clear

# ─── Step 4: write files ─────────────────────────────────────────────────────

cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 4 of 4 — Saving your answers          (~30 seconds)           │
  └─────────────────────────────────────────────────────────────────────┘

  What this step is:

    Just the wizard finishing up. No more questions. Everything you
    entered in Steps 1-3 gets saved to the right files so the cloud
    routine can read them later.

  What gets created on disk:

    📄 me.md
       Your profile (name, background, lenses, stop-list). Goes into
       this folder, will be committed to git. The AI reads this before
       every video.

    📄 channels.yaml
       Your channel list with priority. Goes into the folder, committed.
       The watcher reads this to know what to check.

    📄 seen.json
       Tracking file (initially empty for each channel). Gets filled
       automatically as videos are processed.

  Reminder:

    No secrets get written. Auth keys (Telegram / GitHub / Anthropic)
    are handled directly via claude.ai env-vars UI — instructions for
    where to get each one are shown in the final summary, coming next.

  Press Enter to continue.

EOF

pause

# Build me.md from template
sed \
    -e "s|{{NAME}}|$NAME|g" \
    -e "s|{{BACKGROUND_PARAGRAPH}}|$BACKGROUND|g" \
    "$ME_TEMPLATE" > "$ME_TARGET.tmp"

python3 - <<PYEOF
import re
from pathlib import Path

content = Path("$ME_TARGET.tmp").read_text()
content = content.replace("{{LENSES}}", """$LENSES_MD""")
content = content.replace("{{STOPLIST}}", """$STOPLIST""")
Path("$ME_TARGET").write_text(content)
PYEOF

rm -f "$ME_TARGET.tmp"

echo
ok "me.md          → $ME_TARGET"
ok "channels.yaml  → $CHANNELS_TARGET"
ok "seen.json      → $REPO_DIR/seen.json"

# ─── Final instructions ──────────────────────────────────────────────────────

cat <<EOF


  ┌─────────────────────────────────────────────────────────────────────┐
  │  Setup complete ✓                                                   │
  └─────────────────────────────────────────────────────────────────────┘

  Wizard generated 3 config files. Now finish cloud setup (~10 min).

  Six steps below. Each one tells you exactly where to go and what to do.

  ───────────────────────────────────────────────────────────────────────

  ❶ Review and edit me.md (optional but recommended)

       cat me.md          # or open in your editor

     Does it capture your role / lenses / stop-list accurately? Tweak
     before committing — me.md is the AI's main input.

  ───────────────────────────────────────────────────────────────────────

  ❷ Push the config to GitHub

       git add me.md channels.yaml seen.json
       git commit -m "initial config from setup wizard"

     If this folder is not yet a GitHub repo:
       gh repo create youtube-radar --private --source=. --remote=origin
       git push -u origin main

     If it already is:
       git push

  ───────────────────────────────────────────────────────────────────────

  ❸ Install Claude GitHub App on your repo

     Open: https://github.com/apps/claude
     → Install → Only select repositories → youtube-radar

     Why: cloud routine needs to clone your repo and push results back.

  ───────────────────────────────────────────────────────────────────────

  ❹ Get your three secrets

     You'll paste these into the claude.ai env-vars UI in Step ❺.
     KEEP THEM in your password manager — never in repo, never in chat.

     ─── A) Telegram bot token ───
       1. Open Telegram, search @BotFather
       2. Send /newbot → name your bot
       3. Copy the token like 1234567890:AAH_xxxx
       4. Find your bot in Telegram, send /start to activate

     ─── B) Telegram chat ID ───
       1. In Telegram, search @userinfobot
       2. Send /start
       3. Copy the numeric ID (8-10 digits)

     ─── C) GitHub fine-grained PAT ───
       1. Open https://github.com/settings/tokens?type=beta
       2. Generate new token (fine-grained)
       3. Name: youtube-radar-routine, expiration: 90 days
       4. Repository access: Only select repositories → your repo
       5. Permissions:
            - Contents → Read and write
            - Pull requests → Read and write
            - everything else → No access
       6. Generate, copy (shown once)

     ─── D) Anthropic auth — pick one ───
       [Option A] API key (predictable per-call cost):
          Open https://console.anthropic.com/settings/keys → Create Key
          Copy the sk-ant-api03-... value
       [Option B] OAuth setup-token (uses claude.ai subscription quota):
          In terminal: claude setup-token
          Authorize in browser, copy the sk-ant-oat-... shown

  ───────────────────────────────────────────────────────────────────────

  ❺ Create cloud Environment on claude.ai/code

     Open: https://claude.ai/code

     Follow .claude/setup-routine.md, Part 1 (full walkthrough). Quick
     summary:

     1. Click environment selector → Add environment
     2. Name: youtube-radar
     3. Network access: Custom → check default list →
        add to Allowed domains:
          api.telegram.org
          youtube.com
          www.youtube.com
          m.youtube.com
          googlevideo.com
          *.googlevideo.com
          ytimg.com
          *.ytimg.com
          youtu.be
     4. Environment variables (paste your secrets from Step ❹):
          TELEGRAM_BOT_TOKEN=<from A>
          TELEGRAM_CHAT_ID=<from B>
          GH_TOKEN=<from C>
          ANTHROPIC_API_KEY=<from D, option A>
          OR
          ANTHROPIC_TOKEN=<from D, option B>
     5. Setup script (Bash):
          #!/bin/bash
          set -e
          pip install yt-dlp
          sed -i.bak '/ppa\\.launchpadcontent\\.net/s/^deb /# deb_disabled /' /etc/apt/sources.list.d/*.list 2>/dev/null || true
          apt-get update || true
          apt-get install -y gh
     6. Save

  ───────────────────────────────────────────────────────────────────────

  ❻ Create the Routine on claude.ai/code/routines

     Open: https://claude.ai/code/routines → New routine

     Follow .claude/setup-routine.md, Part 2. Key fields:
     - Name: youtube-radar-digest
     - Instructions: thin wrapper (paste from setup-routine.md Step 5)
     - Repositories: pick your youtube-radar repo
     - Environment: pick youtube-radar (from Step ❺)
     - Trigger: Schedule → 0 6 * * * (or your preferred cron)
     - Permissions tab: enable "Allow unrestricted branch pushes"

     Click Create. Then on the routine page → "Run now".

     First digest in ~15-20 minutes.

  ───────────────────────────────────────────────────────────────────────

  Lost or want to change anything in me.md / channels.yaml?
    Edit the files directly — they're just text. Or re-run ./setup.sh.

  Need more detail on any step?
    QUICKSTART.md            — full walkthrough
    .claude/setup-routine.md — claude.ai UI step-by-step
    CONFIGURATION.md         — every knob explained
    ARCHITECTURE.md          — how it works under the hood

EOF
