---
name: incident-investigation
description: "End-to-end investigation of an alert or incident assigned to your team. Use this skill whenever the user references an incident (by ID, number, URL, or \"the incident assigned to us / our team\"), or asks to investigate a login, auth, session, MFA, token, checkout, or other request failure that originated from an alert. Pulls the incident from the alerting tool (or asks the user to paste it), extracts the identifiers, checks service health then logs, correlates traces environment-wide, inspects recent code changes, and convenes a 3-agent council to produce ranked probable causes. Never concludes from a single signal; always asks before treating prod as the investigation target."
---

# Incident Investigation Skill

## Service map (fill in once per team / organisation)

This skill is generic. Everything specific to your organisation lives in a **service map** that you
fill in once. Keep it at the top of this file, or in the project as `service-map.md` (the skill reads
`service-map.md` from the current repo first, if present). If neither is filled in, ask the user for
the missing rows before Phase 0 — do not guess service names, datasets or ID formats.

The rows below are **fictional placeholders**. Replace them.

```markdown
## Service map

- **Team:** <your team name>                      e.g. Checkout Platform
- **Alert source:** <tool + service / escalation IDs + region/host>
                                                  e.g. PagerDuty, service PXXXXXX, escalation PYYYYYY
- **Observability backend + org/team:** <tool + region + org slug + environments>
                                                  e.g. Honeycomb EU, org acme-shop, envs prod / uat
- **Shareable query-link format:** <URL template> e.g. https://ui.<region>.honeycomb.io/<org>/environments/{env}/result/{run_pk}
- **Health reference:** <metrics dataset + standing board/dashboard id>
                                                  e.g. dataset metrics, board "service-health"
- **Code host:** <GitLab / GitHub + how project ids are passed to the MCP/CLI>
- **Wiki / runbooks:** <Confluence space or other, optional>

### Services

| Service              | Role in flow                          | Dataset / log source | Repo (namespace/path)        |
|----------------------|---------------------------------------|----------------------|------------------------------|
| checkout-gateway     | Entry point for all checkout requests | checkout-gateway     | acme/checkout/gateway        |
| orders-service       | Owns order state transitions          | orders               | acme/checkout/orders-service |
| payments-adapter     | Downstream dependency                 | payments             | acme/checkout/payments       |

- **Entry-point service(s):** <the gateway every request passes through>   e.g. checkout-gateway
- **State-owning service(s):** <emits the status transitions that prove the outcome> e.g. orders-service

### Identifier formats

| Identifier  | Format                        | Example (fictional) |
|-------------|-------------------------------|---------------------|
| customerId  | <e.g. 8-digit number>         | 12345678            |
| orderId     | <e.g. ORD- + 10 alphanumerics>| ORD-A1B2C3D4E5      |

### Known-incident links (for the Historian agent)

| Pattern / signature                   | Link to postmortem / ticket |
|---------------------------------------|-----------------------------|
| <e.g. connection-pool exhaustion>     | <link>                      |

### Sub-skill routing

| Incident type                                   | Route to                                   |
|-------------------------------------------------|--------------------------------------------|
| A known multi-step user flow (e.g. reset link)  | `/raktim-skills:flow-reconstruction`       |
```

**Tools are optional.** This skill works best with MCP servers for the alert source (e.g. PagerDuty),
the observability backend (e.g. Honeycomb), the code host (GitLab or GitHub) and the wiki (e.g.
Confluence). If one is not connected, say so, and ask the user to paste the equivalent material: the
alert payload, the log lines / query results, or the commit list and diffs. Continue with whatever
is available; a missing tool is a gap to note, not a reason to stop.

---

## Core principles (non-negotiable)

1. **Never assume.** Every conclusion must be backed by a log line, a metric, a trace, or a diff. Absence of evidence is "I could not find it", not "it did not happen".
2. **The application named in the incident is a starting point, not the culprit.** Requests almost always flow through the **entry-point service** from the service map (the gateway for all requests of that kind) even when another service raised the alert. Always investigate the entry-point service in addition to the named service.
3. **Always check the state-owning service in parallel with the entry-point service.** Status transitions (e.g. an account or order moving to `Suspended` / `Active`, `UPDATED_STATUS`-style events) are often emitted by a different service from the gateway and do NOT reliably surface in an entry-point `body contains <traceId>` correlation — they must be queried directly per identifier. A state change frequently presents as "works on one client but fails on another": one client rides an existing session while the other performs a fresh request that trips the new state. The state change itself is only provable in the state-owning service.
4. **Prod is the default investigation target, but confirm first.** Before running any prod query, ask the user to confirm prod (vs UAT/demo). Do not proceed until confirmed.
5. **Related identifiers co-occur.** The primary and secondary identifiers (see the service map's identifier formats) appear together in at least one log line of a trace. If only one is provided, find the other before going wide.
6. **Trace correlation is always `body contains <traceId>` environment-wide.** Never conclude from a span list, stack frames, or a single trace view alone.
7. **Recent code changes are candidate causes, never certainties.** Present them as "possible cause + reason", with a confidence level.
8. **Do not stop to ask for information you can retrieve yourself.** Once you have an identifier and the environment is confirmed, you MUST run the health check (Phase 2), the log/trace investigation (Phase 5), and the code change review (Phase 6) before reporting back — even if some inputs are missing. Specifically:
  - A missing secondary identifier is resolved via Phase 3 (body contains "{knownId}"), never by asking the user first.
  - A missing incident payload does NOT block the investigation: proceed from the identifier. Bound the time range from whatever is known (incident time, or a user-given approximate time, or a widened default window) rather than pausing.
  - A missing/blocked wiki doc, a missing alert ID, or a missing downstream repo path are NOT reasons to stop. Note the gap, do the queries you can, and only ask the user for the specific thing that is genuinely unobtainable AFTER observability and the code host have been checked.
  - Asking the user is the LAST step, not the first. Never end a turn with "give me X and I'll run it" when X is derivable from logs, the code host, or a trace correlation you have not yet run. (Exception: if a tool is not connected at all, ask the user to paste its output — see "Tools are optional".)
9. **DO NOT MAKE ANY CHANGES TO ACTUAL CODE.** Never make any code changes without the user's confirmation. Suggest changes at the end of investigation only after confirmation.

---

## Phase 0 — Get the incident from the alert source

Use the team, service and escalation IDs from the service map.

- If the user gives an incident ID/number/URL → fetch that specific incident.
- If the user says "our incidents" / "what's assigned to us" → list incidents filtered by the team/service from the service map, then ask the user which one (or take the one they name).
- If no alert-source MCP is connected → ask the user to paste the alert (title, body, custom details, trigger time).
- Read/GET operations run **without confirmation**. Any write (acknowledge, resolve, add note) requires **explicit user confirmation first** — never auto-ack or auto-resolve.

From the incident payload, extract and record:
- The **identifiers** (check title, body, custom details, alert payload, linked runbook; match against the formats in the service map).
- Timestamp / trigger time → this bounds the query time range.
- The **named application/service** (record it, but do not treat it as the sole suspect).
- Alert summary, severity, any embedded traceId, and links.

If no identifier is present, note it and ask the user, or derive it from the alert body.

---

## Phase 1 — Confirm environment

State the intended target (**prod**) and ask the user to confirm before any query:

> "I'll investigate this in **prod**. Confirm, or tell me the environment (UAT / demo)?"

Do not run queries until confirmed.

---

## Phase 2 — Health check (are the apps even healthy?)

Before diving into logs, check metrics to rule in/out a platform-level problem. Use the metrics dataset and standing board from the service map as reference for panels: JVM/runtime, HTTP error rate, CPU, threads, GC, connection pools.

Check health for **both** the named service **and** the entry-point service **and** the state-owning service (plus any obvious dependency listed in the service map).

For each service, over the incident window ± a sensible buffer:
- HTTP 5xx / error rate spike
- CPU / thread saturation (compare against any matching pattern in the known-incident links)
- GC pauses / heap pressure
- Connection pool exhaustion / connection wait
- Instance restarts / pod churn

Record whether each service was **healthy** or **degraded** during the window. A degraded dependency reframes the whole investigation.

---

## Phase 3 — Resolve linked identifiers

If only one identifier was provided, find the other. Run an environment-wide query and read the trace bodies — the two IDs appear together in at least one log line:

```
environment_wide_query: true
filter: body contains "{knownId}"
time: [incident_time ± buffer]
breakdowns: body, trace.trace_id, service.name, http.url, http.status_code
include_samples: true
```

Read log bodies in **time order**. Extract the paired id and every relevant `trace.trace_id`.

---

## Phase 4 — Route to the right sub-investigation

- **Known multi-step user flow** (the incident type appears in the service map's sub-skill routing table, e.g. a reset-link or token-exchange flow) → **defer to the `flow-reconstruction` skill** (`/raktim-skills:flow-reconstruction`) and run it for the identifier. Bring its findings back into the council.
- **All other** incidents → query the **entry-point service and the state-owning service in parallel** as the entry point, then fan out to the named service and dependencies. The entry-point service holds the request flow and failure codes; the state-owning service holds the resulting status transitions. Correlate the two on identifier and traceId.

Do not skip the entry-point or state-owning service even if the incident named a different service.

---

## Phase 5 — Log investigation (per identifier)

Search the entry-point and state-owning services first, in parallel, then the named service and dependencies. Use the datasets listed in the service map, plus the named service's dataset. If no observability MCP is connected, ask the user to run the queries below and paste the results.

> **The state-owning service must be queried directly per identifier** (`body contains "{id}"`), not relied upon to appear in a traceId correlation. Its status events are how you prove whether the entity changed state and whether/when it changed back — this is often the actual answer for "locked out" / "works on one platform but not another" reports.

Per-identifier query:
```
dataset: {service}
filter: body contains "{identifier}"   (repeat for each linked identifier)
time: [incident_time ± buffer]
breakdowns: body, trace.trace_id, http.url, http.method, http.status_code, severity
include_samples: true
```

Read every body/sample in time order. Collect all `trace.trace_id` values seen.

### Trace correlation (mandatory for every traceId)
For each traceId, run the environment-wide full-trace query so **all** datasets are covered:
```
environment_wide_query: true
filter: body contains "{traceId}"
time: [trace_time ± 1hr]
include_samples: true
calculations: COUNT
```
- Read **every** log body/sample in time order — never conclude from the span list or a single trace view alone.
- If `orphaned_events > 0`, **fetch orphaned events separately** and read them too.
- Capture the shareable link in the format from the service map.
  Always the environment-wide `body contains <traceId>` link — never a dataset-specific or trace-viewer link.

Note error signatures, status codes, business-failure messages (200 with a failure body is common), and where in the flow the request broke.

---

## Phase 6 — Recent code changes (candidate causes only)

Once logs point at one or more services, check the code host (repos from the service map) for recent changes that plausibly explain the failure. Do **not** assume a change is the cause. If no code-host MCP or CLI is available, ask the user to paste the recent commits / merged PRs and relevant diffs.

For each implicated repo:
- Recent commits / merged MRs/PRs on the default branch around and before the incident time.
- Diffs touching the failing endpoint, filter/validator, config (`application.yml` or equivalent), dependency versions, or serialization (typical patterns: framework version skew → cache/session deserialization failures; a major framework upgrade removing an API; token issuer/key mismatch; a new validator rejecting a valid path).
- Match the change to the observed log signature. If it matches → candidate cause with reasoning. If it doesn't → note and move on.

Also consult **REPO_MAP.md** (if the repo has one) before reasoning about endpoints, request flows, or architecture.

---

## Phase 7 — The Council (3 agents, 3 models, 3 personalities)

Convene three independent investigator agents. Each receives the **same evidence bundle** (incident metadata, health findings, log/trace findings, code-change candidates) and produces its own ranked list of probable causes with reasons and a confidence score. Agents run independently — no cross-talk until the verdict step.

Spawn each agent as a sub-agent with a distinct persona. Where model selection is available, give each a different model tier (e.g. the most capable model for the Skeptic, a balanced model for the Systems Thinker, a fast model for the Historian); otherwise use the same capable model with the distinct personas.

| Agent | Model | Persona | Bias / lens |
|---|---|---|---|
| **A — The Skeptic** | most capable available (e.g. Opus tier) | Adversarial, evidence-first, distrusts correlation | Demands a log/trace/diff for every claim; attacks weak inferences; flags "assumption" wherever it sees one |
| **B — The Systems Thinker** | balanced (e.g. Sonnet tier) | Calm, holistic, dependency-aware | Reasons about cross-service flow, timing, and upstream/downstream effects; weights the health check heavily |
| **C — The Historian** | fast (e.g. Haiku tier) | Fast, pattern-matching, recall-driven | Matches against the known-incident links in the service map and the common patterns in Phase 6; proposes analogues |

Each agent must return strict JSON:
```json
{
  "causes": [
    {
      "cause": "…",
      "reason": "backed by <specific log/trace/metric/diff>",
      "confidence": 0-100,
      "evidence_refs": ["traceId / query_url / commit sha / metric"],
      "assumptions_flagged": ["…"]
    }
  ]
}
```

### Council verdict
Aggregate the three JSON outputs:
- **Consensus causes** (flagged by ≥2 agents) rank highest.
- Reconcile confidence (mean, but the Skeptic can veto a cause that has no evidence ref → drop or downgrade).
- Preserve dissent: if one agent strongly disagrees, surface it as an alternative hypothesis.
- Any cause without an `evidence_refs` entry is downgraded to "speculative — needs verification" and must not be presented as probable.

---

## Phase 8 — Final report

Deliver, in prose (not a wall of bullets):

1. **Incident** — id, service named, identifiers, time, environment (confirmed).
2. **Health verdict** — which services were healthy/degraded during the window.
3. **What the traces show** — the failure point, with environment-wide query links per traceId.
4. **Probable causes (ranked)** — each with its reason, confidence, evidence refs, and any code change implicated (as *possible*, not certain).
5. **Alternative hypotheses** — dissenting council views worth ruling out.
6. **Open assumptions** — anything not yet backed by evidence, explicitly labelled.
7. **Suggested next step** — the single cheapest query/diff that would confirm the top cause.

Never present a cause as certain. Never auto-write to the alert source — offer to add an investigation note and wait for confirmation.

---

## Standing tool conventions (reference)

- **Observability backend**: region/org from the service map. Before any conclusion: `environment_wide_query=true`, `body contains <traceId>`, `include_samples=true`, read every body/sample in time order; fetch orphaned events when `orphaned_events > 0`. Links always environment-wide `body contains` form. (Honeycomb: `update_board` must re-pass full `preset_filters` every call or they are wiped.)
- **Alert source**: team/service/escalation from the service map. Reads run freely; writes need explicit confirmation.
- **Code host** (GitLab or GitHub): pass project ids in the form recorded in the service map.
- **REPO_MAP.md**: consult, if present, before any endpoint/flow/architecture reasoning.
- **Council agents**: each agent gets the same evidence bundle and returns strict JSON only.
- **Missing tool**: ask the user to paste the alert / logs / commits and continue.
