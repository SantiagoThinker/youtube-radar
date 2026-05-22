#!/bin/bash
# scripts/utils.sh — shared bash helpers for the orchestrator routine.
# Usage: source scripts/utils.sh
#
# Functions:
#   slug "Title with spaces and Punctuation!"  → "title-with-spaces-and-punctuation"
#   clean_vtt input.vtt output.txt             → strip VTT to clean text (dedupes rolling-subtitle blocks)
#   build_base "20260505" "@handle" "Title" "videoId" → "2026-05-05_handle_title_videoId"
#   current_log_file                           → "logs/runs-YYYY-MM.jsonl"
#
# Why this file exists:
#   - DRY: single source of truth for slug / VTT cleanup / filename logic
#   - README, orchestrator.md, manual debug — all point here
#   - Easier to test: source the file and call functions directly
#
# Also supports CLI dispatch — see end of file:
#   bash scripts/utils.sh slug "Some Title"
#   bash scripts/utils.sh build_base "20260505" "@handle" "Title" "videoId"

slug() {
    # $1 = title (raw, may contain Russian / punctuation / Unicode)
    # → ASCII-only, lowercase, dash-separated, max 60 chars
    local s="$1"
    s=$(echo "$s" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]')
    s=$(echo "$s" | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    if [ ${#s} -gt 60 ]; then
        s=$(echo "$s" | cut -c1-60 | sed 's/-[^-]*$//')
    fi
    echo "$s"
}

clean_vtt() {
    # $1 = path to .en.vtt
    # $2 = path to output .txt
    # Drops VTT headers, timestamps, inline tags. Dedupes "rolling subtitle" blocks
    # by taking only the LAST line of each cue (the new line, not the carry-over).
    awk '
        function clean(s) {
            gsub(/<[^>]*>/, "", s)
            gsub(/&gt;/, ">", s); gsub(/&lt;/, "<", s); gsub(/&amp;/, "\\&", s)
            gsub(/&#39;/, "\x27", s); gsub(/&quot;/, "\"", s)
            sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
            return s
        }
        function flush() {
            if (n > 0) {
                line = clean(lines[n])
                if (line != "" && line != last) { print line; last = line }
                n = 0
            }
        }
        /^WEBVTT/||/^Kind:/||/^Language:/ {next}
        /-->/ {flush(); next}
        /^[[:space:]]*$/ {flush(); next}
        {lines[++n] = $0}
        END {flush()}
    ' "$1" > "$2"
}

build_base() {
    # $1 = upload_date (YYYYMMDD or "NA")
    # $2 = handle (@something)
    # $3 = title (raw)
    # $4 = video_id (YouTube 11-char)
    # → "<YYYY-MM-DD>_<channel-slug>_<title-slug>_<video-id>"
    local date_str channel_slug title_slug
    if [ "$1" = "NA" ] || [ -z "$1" ]; then
        date_str=$(date -u +%Y-%m-%d)
    else
        date_str=$(echo "$1" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})$/\1-\2-\3/')
    fi
    channel_slug=$(echo "$2" | sed 's/^@//' | tr '[:upper:]' '[:lower:]')
    title_slug=$(slug "$3")
    echo "${date_str}_${channel_slug}_${title_slug}_$4"
}

current_log_file() {
    # Returns the current month's runs JSONL path: logs/runs-YYYY-MM.jsonl
    # Used for log rotation (orchestrator appends here, gen_status reads all matching files).
    echo "logs/runs-$(date -u +%Y-%m).jsonl"
}

# CLI dispatcher — call as a standalone script, without source.
# Use when you need a one-off call within a single Bash invocation.
#
# Examples:
#   bash scripts/utils.sh slug "Some Title"
#   bash scripts/utils.sh build_base "20260505" "@handle" "Title" "videoId"
#   bash scripts/utils.sh clean_vtt input.vtt output.txt
#   bash scripts/utils.sh current_log_file
#
# If you need multiple calls in one Bash script — prefer source pattern:
#   source scripts/utils.sh && slug "X" && slug "Y" && ...
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ $# -gt 0 ]; then
    fn="$1"; shift
    "$fn" "$@"
fi
