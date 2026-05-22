#!/bin/bash
# setup.sh — interactive setup wizard for youtube-radar.
#
# Collects: profile, lenses, channels, Telegram bot, GitHub PAT, Anthropic auth.
# Outputs:
#   - me.md (from template)
#   - channels.yaml (with user's channels + priority)
#   - ~/.config/youtube-radar/secrets.env (mode 600, NOT committed)
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
color_reset="\033[0m"

say() {
    printf "${color_blue}▶${color_reset} %s\n" "$1"
}

ok() {
    printf "${color_green}✓${color_reset} %s\n" "$1"
}

warn() {
    printf "${color_red}⚠${color_reset} %s\n" "$1"
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
    # $1 = prompt. Reads until empty line.
    local prompt="$1"
    local result=""
    printf "${color_bold}%s${color_reset} ${color_dim}(empty line to finish)${color_reset}:\n" "$prompt"
    while IFS= read -r line; do
        [ -z "$line" ] && break
        result+="$line"$'\n'
    done
    echo "$result"
}

# ─── Header ──────────────────────────────────────────────────────────────────

clear
cat <<EOF
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   youtube-radar setup wizard                                        │
│                                                                     │
│   This collects your profile, lenses, channels, and secrets.        │
│   Secrets go to ~/.config/youtube-radar/secrets.env (mode 600).     │
│   Repo files: me.md, channels.yaml (no secrets in either).          │
│                                                                     │
│   Press Ctrl+C any time to abort and start over.                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

EOF

# ─── Step 1: profile ─────────────────────────────────────────────────────────

say "Step 1 of 5 — Your profile"
echo

NAME=$(ask "Your name (used in me.md)")
echo
echo "Background paragraph: 3-5 sentences about your role, company, what you build."
echo "Synthesizer uses this to filter relevance."
BACKGROUND=$(ask_multiline "Paste paragraph(s) — empty line when done")

# ─── Step 2: lenses ──────────────────────────────────────────────────────────

echo
say "Step 2 of 5 — Lenses"
echo
cat <<EOF
Lenses are focus areas the Synthesizer projects each video through.
Each lens becomes a section in your daily digest with 2-5 bullets,
or an honest "no insights here, because <reason>" refusal.

Examples of useful lenses:
  • Career — "I'm searching for a Head of Product role in AI-first B2B"
  • Startup — "I'm exploring an AgentOps governance startup"
  • Tech radar — "I want to track capability shifts in agentic systems"
  • Investment thesis — "I evaluate Series A AI companies"
  • Skill — "I'm learning RL fine-tuning"
  • Industry — "I track competitive moves in fintech"

Define 1-5 lenses. For each: short name + 2-4 sentence description with
your specific goal, active questions, examples of signal vs noise.

EOF

LENSES_MD=""
LENS_NUM=1
while true; do
    echo
    LENS_NAME=$(ask "Lens #$LENS_NUM name (empty to finish)")
    [ -z "$LENS_NAME" ] && break
    LENS_DESC=$(ask_multiline "Description for lens '$LENS_NAME'")
    LENSES_MD+="### $LENS_NAME

$LENS_DESC
"
    LENS_NUM=$((LENS_NUM + 1))
    [ $LENS_NUM -gt 5 ] && break
done

if [ -z "$LENSES_MD" ]; then
    warn "No lenses defined. At least one lens is required — try again."
    exit 1
fi

echo
echo "Stop-list — patterns of 'insight' you already know and don't want repeated."
echo "Common examples:"
echo "  - Generic AI-changes-everything statements"
echo "  - Basics of RAG / fine-tuning / prompt engineering"
echo "  - 'Distribution beats technology'"
echo "  - AGI timeline claims"
echo
STOPLIST=$(ask_multiline "Paste your stop-list (one item per line)")

if [ -z "$STOPLIST" ]; then
    STOPLIST="(none yet — add patterns over time as you notice the Synthesizer surfacing things you already know)"
fi

# ─── Step 3: channels ────────────────────────────────────────────────────────

echo
say "Step 3 of 5 — YouTube channels to monitor"
echo
echo "Paste @handles, one per line. Order = priority (first = highest)."
echo "Examples: @lexfridman, @ycombinator, @NoPriorsPodcast, @aiDotEngineer"
echo
HANDLES=$(ask_multiline "Channels — empty line to finish")

if [ -z "$HANDLES" ]; then
    warn "No channels — using defaults from channels.template.yaml."
    cp "$CHANNELS_TEMPLATE" "$CHANNELS_TARGET"
else
    # Build channels.yaml from handles
    {
        echo "# Generated by setup.sh. Channels listed in priority order (top = highest)."
        echo ""
        echo "channels:"
        PRIO=1
        while IFS= read -r handle; do
            [ -z "$handle" ] && continue
            # Normalize: ensure starts with @
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

    # Build initial seen.json from same handles
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

# ─── Step 4: secrets ─────────────────────────────────────────────────────────

echo
say "Step 4 of 5 — Secrets"
echo
cat <<EOF
The wizard stores all secrets in $SECRETS_FILE
(mode 600 — only your user can read).

You'll later copy these into the claude.ai routine UI's env vars field.
Secrets are NEVER written into the repo.

EOF

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

echo "▶ Telegram bot token (from @BotFather → /newbot → API Token)"
TELEGRAM_BOT_TOKEN=$(ask_secret "Paste TELEGRAM_BOT_TOKEN")

echo
echo "▶ Telegram chat_id (from @userinfobot → /start → numeric ID, 8-10 digits)"
TELEGRAM_CHAT_ID=$(ask "Paste TELEGRAM_CHAT_ID")

echo
echo "▶ GitHub fine-grained PAT (from github.com/settings/tokens?type=beta)"
echo "  Required permissions: Contents Read+Write, Pull requests Read+Write, on this repo only."
GH_TOKEN=$(ask_secret "Paste GH_TOKEN")

echo
echo "▶ Anthropic auth — pick A or B:"
echo "  A) API key from console.anthropic.com (pay-as-you-go)"
echo "  B) OAuth setup-token from 'claude setup-token' (uses claude.ai subscription)"
ANTHROPIC_CHOICE=$(ask "Choose [A/B]" "A")

if [[ "$ANTHROPIC_CHOICE" =~ ^[Aa]$ ]]; then
    ANTHROPIC_API_KEY=$(ask_secret "Paste ANTHROPIC_API_KEY (sk-ant-api03-...)")
    ANTHROPIC_TOKEN=""
else
    ANTHROPIC_TOKEN=$(ask_secret "Paste ANTHROPIC_TOKEN (sk-ant-oat-...)")
    ANTHROPIC_API_KEY=""
fi

# ─── Step 5: write files ─────────────────────────────────────────────────────

echo
say "Step 5 of 5 — Writing files"

# Build me.md from template
sed \
    -e "s|{{NAME}}|$NAME|g" \
    -e "s|{{BACKGROUND_PARAGRAPH}}|$BACKGROUND|g" \
    "$ME_TEMPLATE" > "$ME_TARGET.tmp"

# Inject lenses + stoplist via Python (sed is awkward with multiline replacements)
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

ok "me.md          → $ME_TARGET"
ok "channels.yaml  → $CHANNELS_TARGET"
ok "seen.json      → $REPO_DIR/seen.json"
ok "secrets.env    → $SECRETS_FILE (mode 600)"

# ─── Final instructions ──────────────────────────────────────────────────────

cat <<EOF

┌─────────────────────────────────────────────────────────────────────┐
│  Setup complete ✓                                                   │
└─────────────────────────────────────────────────────────────────────┘

Next steps:

  1. Review me.md and channels.yaml — edit if anything looks wrong.

  2. Commit and push to GitHub:
       git add me.md channels.yaml seen.json
       git commit -m "initial config from setup wizard"
       git push -u origin main

  3. Install Claude GitHub App on your repo:
       open https://github.com/apps/claude
     → Install → Only select repositories → youtube-radar

  4. Create cloud Environment on claude.ai/code:
       Open: https://claude.ai/code
     Follow:  .claude/setup-routine.md  Part 1
     Env vars: copy each line from $SECRETS_FILE

  5. Create Routine on claude.ai/code/routines:
       Follow: .claude/setup-routine.md  Part 2

  6. Run now from the routine page. First digest in ~15-20 min.

For full walkthrough see QUICKSTART.md.

EOF
