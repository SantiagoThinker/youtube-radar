#!/bin/bash
# setup.sh — interactive setup wizard for youtube-radar.
#
# Collects: profile, lenses, channels, Telegram bot, GitHub PAT, Anthropic auth.
# Outputs:
#   - me.md (from template) — committed to git
#   - channels.yaml — committed to git
#   - seen.json — committed to git
#   - ~/.config/youtube-radar/secrets.env — NOT committed (mode 600)
#
# Secrets are never written into the repo. The wizard prints the secrets.env
# path at the end so you can copy values into claude.ai routine UI.

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$HOME/.config/youtube-radar"
SECRETS_FILE="$SECRETS_DIR/secrets.env"
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

ask_secret() {
    # $1 = prompt. Reads without echoing.
    local prompt="$1"
    local result
    printf "${color_bold}%s${color_reset} ${color_dim}(hidden)${color_reset}: " "$prompt"
    read -rs result
    echo  # newline after hidden input
    echo "$result"
}

ask_multiline() {
    # $1 = prompt. Reads until line containing exactly "END" (sentinel).
    # Why a sentinel instead of empty-line: pasted multi-paragraph content
    # often has internal blank lines, which would prematurely end input.
    local prompt="$1"
    local result=""
    printf "${color_bold}%s${color_reset}\n" "$prompt"
    printf "${color_dim}Type or paste your text below. When you're done, type ${color_reset}${color_bold}END${color_reset}${color_dim} on its own line and press Enter.${color_reset}\n"
    printf "${color_dim}(blank lines inside your text are fine — they won't end input)${color_reset}\n"
    echo
    while IFS= read -r line; do
        [ "$line" = "END" ] && break
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

  This wizard asks 5 questions (~10 min total):
    Step 1 — Who you are (so AI tailors content to YOU)
    Step 2 — Your focus areas (so AI knows what to look for)
    Step 3 — Which channels to watch
    Step 4 — Three quick auth keys (Telegram, GitHub, Anthropic)
    Step 5 — Write everything to disk

  Secrets stay LOCAL ($SECRETS_FILE).
  Profile + channels go in the repo so the cloud routine can read them.

  Press Ctrl+C any time to abort and restart.

EOF

pause
clear

# ─── Step 1: profile ─────────────────────────────────────────────────────────

cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 1 of 5 — Tell us about you            (~2 minutes)            │
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
       3-5 sentences. Who are you professionally, what are you building,
       what's important RIGHT NOW. The AI uses this to filter relevance.

       Example of a useful background:

         "I'm a Product Manager at a B2B SaaS company (~500 employees).
          We're rolling out AI features and I'm evaluating whether to
          leave for a Head-of-Product role at an early-stage AI-first
          startup. Right now I'm tracking: how AI-first orgs structure
          PM work, what enterprise AI buyers actually pay for, and where
          AgentOps tooling is heading."

       That's specific enough for the AI to decide what's relevant. A
       background like "I work in tech" is too vague to be useful.

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
  │  Step 2 of 5 — Define your lenses           (~3 minutes)            │
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
  │  Step 3 of 5 — Choose channels              (~3 minutes)            │
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

# ─── Step 4: secrets ─────────────────────────────────────────────────────────

cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 4 of 5 — Auth keys (the boring part)  (~3 minutes)            │
  └─────────────────────────────────────────────────────────────────────┘

  Why we need these:

    The system runs in the cloud (Anthropic's infrastructure). To work
    on your behalf, it needs three keys:

      1) Telegram bot token — to send you the daily digest
      2) GitHub Personal Access Token — to commit results back to your repo
      3) Anthropic API key OR OAuth token — pays for Claude AI calls

    All three are stored LOCALLY here:
      $SECRETS_FILE
      (mode 600 — only your user can read it)

    NONE of them touch the git repo. After the wizard, you'll manually
    copy them into the claude.ai routine UI — this is the only place
    where secrets live in the cloud.

  If you DON'T have these keys yet, abort now (Ctrl+C) and follow
  QUICKSTART.md sections:
    • "Telegram bot setup"
    • "GitHub token setup"
    • "Anthropic auth"
  Then come back and re-run setup.sh.

  Have them ready? Continue.

EOF

pause
echo

# ─── 4.1 Telegram ─────
cat <<EOF
  ▸ Telegram bot token

    Where to get it:
      1. Open Telegram → search for @BotFather
      2. Send /newbot → give it any name and a unique handle
      3. @BotFather replies with a token like 1234567890:AAH_xxxx...
      4. Find your new bot in Telegram and send /start to activate it

    Why we need it: this is what sends you the daily digest message.

EOF
TELEGRAM_BOT_TOKEN=$(ask_secret "Paste TELEGRAM_BOT_TOKEN")

echo
cat <<EOF
  ▸ Telegram chat ID

    Where to get it:
      1. In Telegram, search for @userinfobot
      2. Send /start to it
      3. It replies with your numeric ID (8-10 digits)

    Why we need it: tells the bot WHICH user to send messages to. This
    is NOT a secret — your bot only sends to this ID, no one else's.

EOF
TELEGRAM_CHAT_ID=$(ask "Paste TELEGRAM_CHAT_ID")

echo
# ─── 4.2 GitHub PAT ─────
cat <<EOF
  ▸ GitHub Personal Access Token (PAT)

    Where to get it:
      1. Visit https://github.com/settings/tokens?type=beta
      2. "Generate new token (fine-grained)"
      3. Token name: youtube-radar-routine
      4. Expiration: 90 days (set a reminder to rotate)
      5. Repository access: Only select repositories → pick this repo
      6. Repository permissions:
           • Contents → Read and write
           • Pull requests → Read and write
           • Everything else → No access
      7. Generate token, copy (shown once)

    Why we need it: cloud routine pushes wiki/recommendations back to
    your repo. We use fine-grained scope so the token can ONLY touch
    this one repo, nothing else in your account.

EOF
GH_TOKEN=$(ask_secret "Paste GH_TOKEN")

echo
# ─── 4.3 Anthropic ─────
cat <<EOF
  ▸ Anthropic auth — pick one

    Two ways to pay for Claude AI calls:

    [A] API key — pay-as-you-go from your Anthropic API balance
        Get it: https://console.anthropic.com/settings/keys → Create Key
        Cost: ~\$3-5 per run of 5 videos at Sonnet prices
        Best if: you want predictable per-call billing

    [B] OAuth setup-token — uses your claude.ai subscription quota
        Get it: open terminal, run 'claude setup-token', browser opens,
                authorize, copy the sk-ant-oat-... token shown
        Cost: counts against your claude.ai subscription
        Best if: you already pay for claude.ai and have quota to spare

EOF
ANTHROPIC_CHOICE=$(ask "Choose [A/B]" "A")

if [[ "$ANTHROPIC_CHOICE" =~ ^[Aa]$ ]]; then
    echo
    ANTHROPIC_API_KEY=$(ask_secret "Paste ANTHROPIC_API_KEY (sk-ant-api03-...)")
    ANTHROPIC_TOKEN=""
else
    echo
    ANTHROPIC_TOKEN=$(ask_secret "Paste ANTHROPIC_TOKEN (sk-ant-oat-...)")
    ANTHROPIC_API_KEY=""
fi

clear

# ─── Step 5: write files ─────────────────────────────────────────────────────

cat <<EOF

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Step 5 of 5 — Writing files                (~30 seconds)           │
  └─────────────────────────────────────────────────────────────────────┘

  About to create:

    • me.md
      Your profile for the AI. Goes into the repo, committed to git.
      You can edit it any time.

    • channels.yaml
      Your channel list with priority. Goes into the repo.

    • seen.json
      Empty tracking file (filled as videos get processed). Goes in repo.

    • $SECRETS_FILE
      Your three auth keys. Mode 600 (only your user reads it).
      NEVER committed to git.

EOF

pause

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

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

# Write secrets.env
{
    echo "# youtube-radar secrets — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Copy these into the claude.ai routine env vars UI."
    echo "# DO NOT commit this file to git."
    echo ""
    echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN"
    echo "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID"
    echo "GH_TOKEN=$GH_TOKEN"
    [ -n "$ANTHROPIC_API_KEY" ] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
    [ -n "$ANTHROPIC_TOKEN" ] && echo "ANTHROPIC_TOKEN=$ANTHROPIC_TOKEN"
} > "$SECRETS_FILE"
chmod 600 "$SECRETS_FILE"

echo
ok "me.md          → $ME_TARGET"
ok "channels.yaml  → $CHANNELS_TARGET"
ok "seen.json      → $REPO_DIR/seen.json"
ok "secrets.env    → $SECRETS_FILE  (mode 600)"

cat <<EOF


  ┌─────────────────────────────────────────────────────────────────────┐
  │  Setup complete ✓                                                   │
  └─────────────────────────────────────────────────────────────────────┘

  What you have now:

    ✓ me.md with your profile and lenses
    ✓ channels.yaml with your channels
    ✓ secrets.env with your auth keys (NOT in repo)

  What still needs to happen (cloud setup, ~5 min):

    1. Review me.md — does it capture your context accurately?
       (cat me.md or open in any editor)

    2. Push to GitHub:

         git add me.md channels.yaml seen.json
         git commit -m "initial config from setup wizard"
         gh repo create youtube-radar --private --source=. --remote=origin
         git push -u origin main

    3. Install Claude GitHub App on your new repo:
         open https://github.com/apps/claude
       → Install → Only select repositories → youtube-radar

    4. Create cloud Environment on claude.ai/code:
       Follow .claude/setup-routine.md, Part 1
       Copy env vars from: $SECRETS_FILE

    5. Create Routine on claude.ai/code/routines:
       Follow .claude/setup-routine.md, Part 2

    6. From the routine page click "Run now".
       First digest in ~15-20 minutes.

  Full walkthrough: QUICKSTART.md

  Have a question? Open the file you're unsure about — README.md,
  QUICKSTART.md, CONFIGURATION.md, ARCHITECTURE.md cover everything.

EOF
