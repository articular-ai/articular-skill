# Articular loop — Claude Code plugin

Keep a human **in the loop** while your coding agent works. This plugin lets an
agent open an [Articular](https://articular.ai) board, scribe its reasoning as
sticky notes that stream onto the canvas in real time, and hand you a URL to
watch, steer, and redirect it — without breaking your flow. Creativity in the
loop, not after the fact.

It's a single [Agent Skill](https://code.claude.com/docs/en/skills) plus a small
`curl` helper that talks to Articular's public REST API. No app code, no heavy
dependencies.

## Install

On Claude Code:

```
/plugin marketplace add articular-ai/articular-skill
/plugin install articular@articular
```

Claude loads the skill automatically when a task calls for laying out reasoning
on a shared canvas, or you can invoke it directly with `/articular:loop`.
Update later with `/plugin marketplace update`.

## Setup

1. **Create an API key.** Signed in to Articular, open
   [`/settings/api-keys`](https://articular.ai/settings/api-keys) and create one
   (it's shown once — copy it).
2. **Export it:**
   ```bash
   export ARTICULAR_API_KEY="art_…"
   # optional, for local/staging instances (defaults are production):
   # export ARTICULAR_API_URL="http://localhost:8080"
   # export ARTICULAR_WEB_URL="http://localhost:5173"
   ```
3. **Dependencies:** `curl` and `jq` (`brew install jq`).

## How it works

The agent drives a short, stable sequence over the API:

1. **Open a board**, seeded with the task it's working on, and share the URL so
   you're in the loop from the start.
2. **Scribe stickies** — one idea per note, categorized (`problem`, `request`,
   `insight`, `solution`, `brainstorm`) and grouped. Each one broadcasts live to
   anyone viewing the board.
3. **Optionally** let Articular's own canvas agent tidy the layout, and generate
   a themed summary.
4. **Hand off** the board URL and poll for when you've engaged.

See [`articular/skills/loop/SKILL.md`](articular/skills/loop/SKILL.md) for the
full workflow and
[`articular/skills/loop/examples/reasoning-board.md`](articular/skills/loop/examples/reasoning-board.md)
for a worked session.

## Use it from any agent (not just Claude Code)

The helper script is plain `curl` — call it directly, or read it as a spec for
your own integration. A first-party MCP server for cross-tool use (Cursor, etc.)
is planned. Full API reference: [articular.ai/docs](https://articular.ai/docs) ·
[llms.txt](https://articular.ai/llms.txt).

## License

[MIT](LICENSE) © Articular
