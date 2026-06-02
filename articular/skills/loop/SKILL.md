---
name: loop
description: >-
  Keep a human in the loop: open an Articular board and externalize your
  reasoning as live sticky notes on a shared canvas they can watch, steer, and
  redirect in real time. Use when working through a complex, open-ended problem —
  planning a feature, debugging a gnarly issue, mapping a system design,
  synthesizing research — and you want to show your work and hand a teammate a
  URL to review or redirect you. Not for quick lookups, single-file edits, or
  tasks with one obvious answer.
---

# Articular loop

Articular is a sticky-note canvas. This skill keeps a **human in the loop** while
you work: you write your reasoning as categorized stickies, and a person watching
the board sees each one appear **live** (every create broadcasts over WebSocket),
so they can steer or redirect you mid-flight. When you're done, you hand them a
URL to keep shaping the work.

The helper script is at `${CLAUDE_SKILL_DIR}/scripts/articular.sh` — that
variable resolves to this skill's directory wherever it's installed, so the
commands below work from any working directory.

## Setup (one-time)

The skill calls the Articular API with an API key. The user provides it:

1. Signed in, they create a key at `https://articular.ai/settings/api-keys`.
2. They export it (and, for local/staging, the API/web origins):
   ```bash
   export ARTICULAR_API_KEY="art_…"
   # optional overrides (defaults are production):
   # export ARTICULAR_API_URL="http://localhost:8080"
   # export ARTICULAR_WEB_URL="http://localhost:5173"
   ```

The script needs `curl` and `jq`.

## Workflow

1. **Open a board, seeded with the task.** A board can't be empty, so seed it
   with the problem you're working on — that becomes the board's source material.
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/articular.sh create-board "Checkout flow rework" \
     --context "Users abandon at the address step; figure out why and propose fixes."
   ```
   This prints the board's `url`. **Share that URL with the human right away** so
   they're in the loop while you think.

2. **Scribe your reasoning as stickies.** As you reason, post one sticky per
   discrete thought. Pick a category so the canvas stays legible. Group related
   stickies with `--group`. Coordinates are auto-placed on a grid if you omit them.
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/articular.sh add-sticky <boardId> "Address autocomplete fails on long street names" --category problem --group "Friction"
   ${CLAUDE_SKILL_DIR}/scripts/articular.sh add-sticky <boardId> "Hypothesis: validation fires before the field blurs" --category insight --group "Friction"
   ${CLAUDE_SKILL_DIR}/scripts/articular.sh add-sticky <boardId> "Defer validation to onBlur + debounce" --category solution
   ```
   Categories: `problem`, `request`, `insight`, `solution`, `brainstorm`.

   To add several at once, pipe markdown where each sticky is an `## N. Title`
   heading (a single `# Title` line is read as the board title, not a sticky),
   optionally followed by a `` `category` `` line:
   ```bash
   printf '## 1. Defer validation to onBlur\n`solution`\n## 2. Debounce the field\n`solution`\n' \
     | ${CLAUDE_SKILL_DIR}/scripts/articular.sh add-stickies-md <boardId> -   # or pass a file path
   ```

3. **(Optional) Tidy and summarize.**
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/articular.sh organize <boardId>        # Articular's canvas agent rearranges the layout
   ${CLAUDE_SKILL_DIR}/scripts/articular.sh summarize <boardId> --wait # themed summary (needs >=1 sticky); --wait prints it
   ```

4. **Hand off and check back.** Give the human the board URL and let them steer
   (move, edit, add stickies). Poll status to see when they've engaged:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/articular.sh status <boardId>   # empty | in_progress | ready
   ```

## When to reach for this

- A problem with several moving parts where seeing the pieces laid out helps.
- Work a human should be able to **redirect mid-flight** — the canvas is the
  steering wheel that keeps them in the loop.
- Anything you'd otherwise explain in a long wall of text: a board is more
  scannable and the human can react to individual points.

Skip it for trivial, single-answer tasks — the board overhead isn't worth it.

## Etiquette

- One idea per sticky; keep content to a sentence or two. Use `--group` to cluster.
- Lead with `problem`/`request` stickies (what you're solving), then
  `insight`/`brainstorm` (what you're learning), then `solution` (what you'll do).
- The default API key allows ~1000 requests/hour — plenty, but batch with
  `add-stickies-md` rather than firing hundreds of `add-sticky` calls.
- The board belongs to the user's own account; treat it like shared workspace,
  not a sandbox to wipe.

See `${CLAUDE_SKILL_DIR}/examples/reasoning-board.md` for a full worked session,
and the plugin README for install details. Full API reference:
`https://articular.ai/docs` and `https://articular.ai/llms.txt`.
