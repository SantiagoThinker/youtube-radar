# {{NAME}} — profile for Synthesizer

This file is read by the Synthesizer agent before every output. It defines:
- **Who you are** (context for relevance filtering)
- **Your lenses** (what makes content useful to you)
- **Your stop-list** (what you already know — filter as noise)
- **Output format** (how Synthesizer should structure recommendations)

Edit freely. The Synthesizer adapts to whatever you write here.

---

## Background

{{BACKGROUND_PARAGRAPH}}

---

## Communication style

Direct, structured delivery. Honest probabilistic estimates. Skip basics — surface non-obvious and contested points only. If unsure whether something is banal, prefer to skip.

---

## Lenses

The Synthesizer produces one section per lens for every video. Each lens can refuse cleanly (with a one-sentence reason) if the content doesn't apply — that's preferred to filler bullets.

Define your lenses below. Each `### LensName` becomes a section header in the output. Write 2-5 paragraphs per lens covering: your specific goal, your active open questions, and concrete examples of what counts as a "signal" vs noise.

{{LENSES}}

---

## What to NOT tell me (stop-list)

The Synthesizer must filter the following kinds of "insight" as already-known noise. Add to this list over time as you notice patterns:

{{STOPLIST}}

What **does** count as a valuable insight:
- Concrete numbers (revenue, conversion, latency, cost, headcount) from practitioners — not analysts
- Names of companies / people you should subscribe to, contact, or watch as competitors
- Counter-intuitive observations backed by specific evidence in the video
- Tactical playbooks ("how exactly to do X") — not "what to do"
- Early-market signals — what emerged / grew / got funded in the last 3 months

When in doubt — skip the bullet, don't stretch.

---

## Recommendations file format

Synthesizer writes to `recommendations/<base>.md`. Structure is enforced:

```markdown
---
video_id: <id>
wiki: wiki/<base>.md
processed_at: <YYYY-MM-DD>
---

# {{Russian-or-English title}}

[Wiki](../wiki/<base>.md) · [YouTube](<url>)

## TL;DR

🧩 **Root tensions:**
• <short heading from wiki, 6-12 words>
• ...

💡 **Most original idea:** <one contrarian idea from the wiki, with speaker name>

## <LensName1>
- 2-5 bullets OR honest refusal with one-sentence reason

## <LensName2>
- ...

## Ignored (optional, 1-2 bullets)
- What sounded important but is not applicable / already known
```

The **TL;DR block** is what gets sent to Telegram. Lenses provide depth — clicked through from the Telegram link.

**Empty lens section is a valid result** — refuse with a one-sentence reason rather than stretching content into bullets.

---

## Output language

`en` — all wiki, recommendations, and Telegram messages should be in English.

(If you want a different language, change this and Extractor/Synthesizer will follow. Tested with `en` and `ru`.)
