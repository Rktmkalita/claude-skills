---
name: flow-reconstruction
description: >
  Reconstruct one user's multi-step flow (login, token exchange, email link, environment or tenant
  switch, checkout, onboarding) from logs and spans when the steps are NOT stitched into a single
  trace. Use when asked to "reconstruct the flow", "prove these calls belong to the same user",
  "trace what this user did", "why is the user stuck after login", "the link didn't work", "reset
  never completed", "401/403 after switching", or to build a time-ordered evidence table for a
  support ticket or incident. Resolves linked identities, finds an anchor event, pivots on a
  secondary key (token suffix, egress IP, session id), separates MISSING from INVALID failures,
  anchors every step to the subject, checks fleet-wide for a systemic pattern, and maps symptoms
  to causes. Works with any log/trace backend (Honeycomb-style queries shown as examples) or with
  logs the user pastes. Confirms the environment (usually prod) before querying.
---

# Flow Reconstruction

Rebuild what one subject (a user, client, device or account) actually did across several services,
in time order, with every step provably tied to that subject — even though the telemetry was never
stitched into one trace.

Worked examples (fictional systems, read one before a first investigation):

- `references/example-token-link-flow.md` — request → emailed link → consume token.
- `references/example-mobile-oauth-env-switch.md` — browser login → native-app token mint →
  environment switch → scoped calls.

---

## Core principles (non-negotiable)

1. **Never conclude from a single signal.** Every step in the final table is backed by a specific
   log line, span or trace, and every conclusion by at least two independent signals (e.g. identity
   in body AND adjacency on a non-shared IP; failure reason AND status code of the cascade).
2. **"I could not find it" is not "it did not happen".** Say which query returned nothing, over
   which window, and why the step might be unlogged.
3. **Confirm the environment before the first query.** State "I will investigate in **prod**" (or
   the environment the user named) and wait for confirmation. Querying the wrong environment gives
   confident, wrong answers.
4. **The flow is several traces, not one.** Mobile and browser clients often start a new top-level
   trace per call. Correlate across traces by time and shared keys; do not wait for parent/child
   spans that were never propagated.
5. **Label provenance honestly.** A step tied only by IP + timing is *correlated*, not *verified*.
   The report must say which is which.
6. **Pick one attempt.** Users retry. Do not stitch step 1 from attempt A and step 3 from attempt C.
   Present the tightest single attempt and list the retries separately.

---

## Inputs to collect

| Input | Why | If missing |
|---|---|---|
| Subject identifier (user/client/account id, email hash) | Starting key | Ask; do not guess from partial ids |
| Reported symptom + rough time (with timezone) | Bounds the window | Ask; default to last 24h and say so |
| Environment | Principle 3 | Ask |
| Client surface (web, native app + version, admin tool) | Explains UA / IP differences between legs | Derive from the first request line |
| Observability access | How to query | See "Backends" below |

### Backends

- **Observability MCP available** (Honeycomb, Datadog, Grafana/Loki, Elastic, ...): run the
  queries yourself. Query blocks below use Honeycomb-style syntax as a neutral example; translate
  filters, breakdowns and time ranges to the backend in use.
- **No MCP / no access:** do not stop. Give the user the exact queries to run (filter, window,
  fields to show) and ask them to paste the raw results — log lines with timestamps, trace ids,
  status codes, IPs and user agents. Apply the same method to the pasted data and state in the
  report that the evidence was user-supplied.

---

## The method

### Step 0 — Confirm the environment

State the target environment (default: prod) and wait for the user to confirm. Do not run a
single query before that.

### Step 1 — Resolve linked identities

One person may have several identifiers: a primary id and a sandbox/demo id, a user id and an
account id, a login name and an internal id. Some steps log only one of them.

- Query the service that holds the mapping (profile / directory / identity) for the given id and
  record every partner id it returns.
- Confirm the subject matches the profile the investigation assumes (e.g. "has no primary accounts,
  sandbox only"). If it does not, say so — the flow and the expected failure may differ.

Record: `primaryId`, linked ids, any per-id resources (account ids, tenant ids).

### Step 2 — Find the anchor event

The anchor is the first step that (a) logs the subject id explicitly and (b) marks the start of an
attempt: a successful login, "reset requested", "order submitted".

```
service.name = <identity-service>
body contains "<primaryId>"
time: reported window (keep it tight)
breakdowns: trace.trace_id, http.route, http.status_code
```

Each hit is one attempt. Record every attempt's timestamp — they bound the per-attempt windows
in later steps. From the anchor's request/audit line capture: timestamp, trace id, source IP,
user agent.

### Step 3 — Pivot on a secondary key

Later steps usually do not log the subject id. Find the key that links them to the anchor:

| Secondary key | Where it appears | Strength |
|---|---|---|
| Token / link suffix (last N chars logged masked) | "token generated" line, then "token presented" line | Strong if unique and short-lived |
| Egress IP of the app leg | request lines of every call the device made | Strong for IPv6; weak for shared IPv4 (see lessons) |
| Session id / cookie hash / device id | request or audit lines | Strong |
| Trace id | same-trace sibling spans | Strongest |
| Correlation / request id header | gateway + downstream lines | Strong if propagated |

Note: the login leg and the app leg may come from **different IPs** (browser/web-view vs native
app, Wi-Fi vs carrier). Never IP-scope the whole flow to the anchor's IP; find the app-leg IP from
the first app-leg call that *does* carry the subject id (e.g. a token mint that resolves the user).

### Step 4 — Pull a tight time window

Around each attempt, query by the secondary key in a small window (typically anchor −1 min to
+4 min; for email links, generation time to token expiry).

```
service.name = <session-service>
body contains "<secondaryKey>"
time: [anchor - 1m, anchor + 4m]
breakdowns: http.route, http.status_code, trace.trace_id
include_samples: true
```

Read results in time order. List which expected steps appear, which are absent, and which
unexpected calls appear. Check absent steps against the service that actually owns that endpoint
(an endpoint that bypasses the gateway will not show in gateway logs).

### Step 5 — Distinguish MISSING from INVALID

Most auth/token failures have two distinct branches; find which one fired:

- **MISSING / ABSENT** — the credential/header/parameter was not sent at all. Fires before any
  validation. Points at the **caller** (client did not attach it).
- **INVALID / REJECTED / EXPIRED / MISMATCH** — something was sent and failed validation. Points
  at the **value** (wrong, expired, wrong issuer/scope, user typed the wrong answer).

Search for both reason strings in the window. A uniform MISSING across every attempt is proof the
value was never sent — not that it was wrong. Read the code or docs for the reason string if the
branch is ambiguous.

### Step 6 — Anchor each step to the subject

For every step that does not log the subject id, tie it by at least one of:

1. **Adjacency:** a subject-verified event on the **same non-shared key** (IPv6, session id)
   within seconds.
2. **Sibling spans:** a span in the **same trace** that carries a linked id (e.g. a downstream
   call with the sandbox id in its URL path). This is the strongest tie.
3. **Token continuity:** the same token suffix generated for the subject and later presented.

If a step can only be tied by shared IPv4 + timing, mark it "correlated only".

### Step 7 — Build the time-ordered proof table (the deliverable)

One attempt, in time order:

| # | Time (UTC, HH:MM:SS) | Call / event | Service | Trace | Result | Tied to subject by |
|---|---|---|---|---|---|---|
| 1 | … | anchor event | … | `<t1>` | success | subject id in body ✓ |
| 2 | … | … | … | `<t2>` | 200 | linked id via downstream lookup in same trace ✓ |
| 3 | … | failing step | … | `<t3>` | 401 `<REASON>` | same IPv6 as row 2, 2s later + linked id in sibling span ✓ |
| 4 | … | cascade calls | … | siblings of `<t3>` | 403 | linked id in URL ✓ |

State the total time span and say explicitly that these are separate traces correlated by time and
keys. If retries make the tightest attempt span minutes, say so and present it as a retry loop.

Links: give one shareable query/trace link per row, using the filter that actually works for that
service (see lesson 1). Result permalinks usually re-run when opened; for frozen evidence export
JSON or screenshot.

### Step 8 — Fleet-wide systemic check

Before blaming the subject's data, check whether the same failure signature hits others:

```
body contains "<REASON>"
time: same window (and a baseline window a week earlier)
breakdowns: client.ip, user_agent.version, http.route
calculations: COUNT, COUNT_DISTINCT(client.ip)
```

Many distinct IPs / users failing the same way in the same minutes, clustered on one app version
or release, means systemic (client release, config, deploy) — not a per-user problem.
Correlate with recent deploys of the involved services.

### Step 9 — Match against a symptom → cause table

Build (or reuse) a table for the flow and place the finding in it:

| Symptom | Likely cause | Distinguishing evidence |
|---|---|---|
| Anchor present, no later steps | User abandoned / link never clicked / app never resumed | No secondary-key hits in window |
| Later step fails with MISSING | Caller did not attach credential | MISSING reason, uniform across attempts |
| Later step fails with INVALID/EXPIRED | Wrong/stale value | INVALID reason; expiry timestamp before use |
| HTTP 200 but UI shows a generic error | Business failure in response body | Failure result string in body, status 200 |
| Many rapid anchor events | User/support retrying an unresolved problem | 5+ generations/attempts in minutes |
| Same failure across many IPs | Systemic (release / config) | Step 8 fleet query |
| No logs at all | Wrong environment, wrong window, or never triggered | Re-check Step 0 and timezone |

---

## Generic lessons (learned the hard way)

1. **Body-logged vs span-only services.** Some services write full request lines into a log body
   (so `body contains "<traceId>"` works); others emit only OTel spans (so the same filter returns
   **0 results** — filter by `service.name` + `trace.trace_id` instead). Build a per-service table
   of "logs to / how to filter / does body-contains-traceId work" before querying, and note it in
   the write-up so reviewers do not think a link is broken.
2. **Wide `body contains` searches time out.** Environment-wide `body contains "<id>"` over hours
   or days often times out. Scope by `service.name`, a tight window, and start from services that
   log the subject id explicitly.
3. **Do not AND two body-contains terms expecting one line** unless they genuinely co-occur (the
   subject id and the user agent are usually on different lines).
4. **IPv6 is a strong anchor; shared IPv4 is weak.** Mobile IPv6 addresses are effectively
   per-device. Carrier-grade NAT and corporate IPv4 egress are shared by many users — never tie a
   step to a subject on shared IPv4 alone.
5. **HTTP 200 with a failure body.** Many APIs return 200 for business failures and put the
   result in the body; the frontend may render that as a generic "technical error". Always read
   the body/result field, not just the status code. Severity is often INFO for business failures.
6. **Multiple rapid token generations** (several within seconds, or many in a week) mean the user
   or support is retrying — the real problem is upstream of the retries. Pick the generation whose
   token was actually presented.
7. **Absence of an optional parameter is not absence of the call.** A request line may legitimately
   carry an empty id for a subject that owns no resource of that kind.
8. **Time zones.** Convert user-reported times to UTC before building windows.

---

## Final report (prose, then the table)

1. **Subject** — ids resolved (and how), profile confirmed, client surface/version, environment.
2. **Sequence** — the Step 7 table for the tightest attempt, total time span, separate-traces note.
3. **Where it broke** — the failing step, MISSING vs INVALID, the cascade, links.
4. **Provenance** — which rows are subject-verified vs correlated only.
5. **Fleet context** — systemic or isolated, with the Step 8 counts.
6. **Cause and handoff** — the symptom → cause row that matches, and one sentence the owning team
   can act on, with the evidence that proves it.

Never present a correlated step as verified for this subject.
