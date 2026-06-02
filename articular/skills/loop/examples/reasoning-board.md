# Worked example — debugging on a board

A run through the skill on a real-shaped task: _"Intermittent 504s on the
checkout endpoint under load."_ The agent narrates its reasoning onto an
Articular board while a human watches.

## 1. Open the board, seeded with the problem

```bash
$ scripts/articular.sh create-board "Checkout 504s under load" \
    --context "Checkout endpoint returns intermittent 504s when traffic spikes. Find the bottleneck and propose a fix."
Board ready — open it to watch your reasoning appear live:
  https://articular.ai/b/k3p9qz/checkout-504s-under-load
{"projectId":42,"boardId":318,"shortcode":"k3p9qz","slug":"checkout-504s-under-load","url":"https://articular.ai/b/k3p9qz/checkout-504s-under-load"}
```

The agent immediately shares that URL with the human: _"Tracking this on a board —
watch here, jump in anytime."_ The human opens it before the next step, so every
sticky streams in live.

## 2. Scribe the reasoning, one sticky per thought

```bash
$ scripts/articular.sh add-sticky 318 "504s only fire when concurrent checkouts > ~200/s" --category problem --group "Symptoms"
sticky #901 added [problem]
$ scripts/articular.sh add-sticky 318 "API logs show the request waiting, not erroring — it's a timeout, not a crash" --category insight --group "Symptoms"
sticky #902 added [insight]
$ scripts/articular.sh add-sticky 318 "Hypothesis: connection pool exhaustion on the payments DB" --category insight --group "Hypotheses"
sticky #903 added [insight]
$ scripts/articular.sh add-sticky 318 "Pool max is 20; each checkout holds a conn across the 3rd-party charge call (~800ms)" --category problem --group "Hypotheses"
sticky #904 added [problem]
$ scripts/articular.sh add-sticky 318 "Release the DB conn BEFORE the external charge, re-acquire after" --category solution
sticky #905 added [solution]
$ scripts/articular.sh add-sticky 318 "Also: bump pool to 50 and add a queue-depth metric" --category solution
sticky #906 added [solution]
```

The human, watching live, drags sticky #905 next to #904 and adds their own:
_"We tried pool=50 last quarter, hit Postgres max_connections — coordinate with
infra."_ The agent sees the new context on its next `status` poll and adjusts.

## 3. Tidy and summarize

```bash
$ scripts/articular.sh organize 318
canvas agent started — it will rearrange stickies live on the board

$ scripts/articular.sh summarize 318 --wait
summary generation started
## Checkout 504s under load

**Root cause.** Under load (>200 checkouts/s), the payments DB connection pool
(max 20) is exhausted because each request holds a connection across an ~800ms
third-party charge call…

**Recommended fix.** Release the DB connection before the external charge and
re-acquire after; add a queue-depth metric. Raising the pool size needs infra
sign-off (prior attempt hit Postgres `max_connections`).
```

## 4. Hand off

```bash
$ scripts/articular.sh status 318
in_progress      # the human is actively editing — keep watching
```

The board is the shared artifact: the agent's reasoning, the human's correction,
and the resulting plan all live on one canvas the team can revisit.
