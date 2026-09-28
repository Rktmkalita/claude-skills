# Worked example — mobile OAuth login → token mint → environment switch

All services, endpoints, log strings, ids, app names and addresses below are **fictional**
(IPs are from the documentation ranges 198.51.100.0/24, 203.0.113.0/24 and 2001:db8::/32). The
example shows the flow-reconstruction method, not any real system.

## The system (fictional)

A native mobile app logs the user in through a browser/web-view (OAuth authorization-code flow),
then resumes and makes its own API calls. Users with a **sandbox** (practice) profile have two ids:
a primary id and a sandbox id.

| Service | Role | Logs to | `body contains "<traceId>"` works? |
|---|---|---|---|
| `identity-service` | Credential check for the browser login | OTel spans only | no — use `service.name` + `trace.trace_id` |
| `auth-server` | `/oauth2/authorize`, `/oauth2/token` | OTel spans only | no |
| `api-gateway` | Front door for the app; logs one request line per call | OTel spans (request line in span) | no |
| `profile-service` | Returns the user profile incl. linked sandbox id | spans; user id in span text | partial |
| `session-service` | Session reload, environment switch | body (request lines) | yes |
| `portfolio-service` | Sandbox-scoped data calls | spans | no |

Canonical flow (each step is its own top-level trace unless noted):

| # | Step | Service | Origin | Logs subject id? |
|---|---|---|---|---|
| 1 | `POST /v1/login` | identity-service | browser/web-view, browser UA | yes (primary) |
| 2 | `POST /oauth2/token/mobile` (code → JWT) | api-gateway → auth-server → profile-service | native app, `sample-app/7.1.0` UA | yes, via profile-service leg |
| 3 | `GET /v1/session` (reload) | session-service | native app | yes (primary) |
| 4 | `PUT /v1/session/workspace` (switch to sandbox) | session-service | native app | **no** |
| 5 | `GET /v1/portfolios/{sandboxId}/positions` etc. | portfolio-service | native app, sibling spans of step 4's trace | yes (sandbox id in path) |

Step 4 requires header `X-Session-Token` (the JWT). Failure reasons: `SESSION_TOKEN_ABSENT`
(header empty — fires before validation) or `SESSION_TOKEN_REJECTED` (sent, failed validation).

## The ticket

> User `p-58213` logs in on the phone, then is stuck; the sandbox never loads. Today ~09:40 UTC.

## Step 0 — Environment

"I will investigate in **prod**, window 09:00–10:30 UTC today. Confirm?" → confirmed.

## Step 1 — Linked identities

```
service.name = profile-service
body contains "userId=p-58213"
time: 09:00–10:30 UTC
```

A span shows `profile loaded userId=p-58213 primaryAccounts=[] sandboxId=s-77120`. Record primary
`p-58213`, sandbox `s-77120`. Profile matches "sandbox-only user" — the flow applies.

## Step 2 — Anchor (browser login attempts)

```
service.name = identity-service
body contains "login succeeded userId=p-58213"
breakdowns: trace.trace_id
```

Three successes: 09:38:04, 09:40:12, 09:41:55 (retries). Their audit spans give a browser UA and
IP `198.51.100.23` — a **shared carrier IPv4** (lesson: weak anchor, do not scope by it).

## Step 3 — Pivot to the app leg (find the egress IP)

The token mint is the first app-leg call that resolves the user:

```
service.name = profile-service
body contains "lookup userId=p-58213"
time: 09:40:12 ± 2m
breakdowns: trace.trace_id
```

Take the mint trace `tr-9f31` and read its gateway span:

```
service.name = api-gateway
trace.trace_id = tr-9f31
```

Request line: `route=/oauth2/token/{app} app=mobile ua="sample-app/7.1.0 (os=mobile)"
clientIp=2001:db8:4a1:7c00::1b status=200`. The **IPv6 app IP is the pivot key** (per-device,
strong anchor).

## Step 4 — Tight window on the app IP

```
service.name = session-service
body contains "2001:db8:4a1:7c00::1b"
time: [09:40:00, 09:44:00]
include_samples: true
```

In order:

```
09:40:15 request GET /v1/session ip=2001:db8:4a1:7c00::1b -> 200 session reloaded userId=p-58213
09:40:16 request PUT /v1/session/workspace ip=2001:db8:4a1:7c00::1b -> 401
09:40:16 auth failure scheme=SESSION_TOKEN reason=SESSION_TOKEN_ABSENT
09:40:19 request PUT /v1/session/workspace ip=2001:db8:4a1:7c00::1b -> 401
09:40:19 auth failure scheme=SESSION_TOKEN reason=SESSION_TOKEN_ABSENT
```

Also check `api-gateway` from the same IP for the token-refresh endpoint the app could have used
instead (`POST /v1/session/exchange`) — **absent**. Because `session-service` endpoints bypass the
gateway, confirm absence in `session-service` too — also absent.

## Step 5 — MISSING vs INVALID

```
service.name = session-service
body contains "2001:db8:4a1:7c00::1b"
body contains "SESSION_TOKEN"
```

Every switch attempt, across all three login retries, is `SESSION_TOKEN_ABSENT`; never
`SESSION_TOKEN_REJECTED`. The JWT exists (step 2 returned 200) but was **not attached** — a caller
defect, not a bad token.

## Step 6 — Anchoring the switch (which logs no user id)

1. **Adjacency:** the user-verified `GET /v1/session` (`userId=p-58213`) is on the same IPv6,
   1 second earlier.
2. **Sibling spans (strongest):** `get_trace` on the switch trace `tr-a20c` (root span
   `app.bootstrap`) shows siblings `GET /v1/portfolios/s-77120/positions → 403` and
   `GET /v1/portfolios/s-77120/alerts → 403`. The sandbox id sits inside the same trace as the
   failing switch.

## Step 7 — Proof table (tightest attempt: the 09:40:12 login)

| # | Time (UTC) | Call | Service | Trace | Result | Tied by |
|---|---|---|---|---|---|---|
| 1 | 09:40:12 | `POST /v1/login` | identity-service | `tr-81d2` | success | primary id in span ✓ |
| 2 | 09:40:14 | `POST /oauth2/token/mobile` | api-gateway / auth-server | `tr-9f31` | 200 | primary id via profile-service leg ✓ |
| 3 | 09:40:15 | `GET /v1/session` | session-service | `tr-9f77` | 200 | primary id in body ✓ |
| 4 | 09:40:16 | `PUT /v1/session/workspace` | session-service | `tr-a20c` | 401 `SESSION_TOKEN_ABSENT` | same IPv6 as row 3, 1 s later + sandbox id in sibling span ✓ |
| 5 | 09:40:16 | sandbox positions / alerts | portfolio-service | siblings of `tr-a20c` | 403 | sandbox id in path ✓ |

Login → failed switch in 4 seconds; separate traces correlated by IPv6, time and in-trace
siblings. The other two logins repeat the same pattern (retry loop).

Links: rows 1, 2, 5 are span-only — use `service.name` + `trace.trace_id` or the trace waterfall
(a `body contains` link would return 0, so note that). Rows 3–4 are body-logged. The waterfall of
`tr-a20c` is the single best artifact: 401 switch + 403 cascade + sandbox id in one view.

## Step 8 — Fleet check

```
service.name = session-service
body contains "SESSION_TOKEN_ABSENT"
time: 09:00–10:30 UTC, plus the same window last week
breakdowns: user_agent.version
calculations: COUNT, COUNT_DISTINCT(client.ip)
```

~140 distinct IPs (IPv4 and IPv6) in 90 minutes, all on `sample-app/7.1.0`; last week near zero.
7.1.0 was released yesterday → **systemic, release-related**.

## Step 9 — Symptom → cause

| Symptom | Likely cause |
|---|---|
| Login ok, mint ok, switch 401 `ABSENT`, cascade 403 | App did not attach the JWT to the switch call |
| Switch 401 `REJECTED` | Token sent but wrong issuer / scope / expired |
| No mint after login | App never resumed from the browser (redirect/deep-link issue) |
| Mint 4xx | Code exchange failed (PKCE / redirect URI / client config) |
| Switch ok, sandbox calls 403 | Sandbox id not linked or sandbox resources missing |
| Same signature across many IPs on one app version | Client release defect |

**Handoff:** "On `sample-app/7.1.0`, `PUT /v1/session/workspace` for sandbox-only users is sent
with an empty `X-Session-Token`; the JWT from `/oauth2/token/mobile` is not attached and
`/v1/session/exchange` is not called. Evidence: uniform `SESSION_TOKEN_ABSENT` (never `REJECTED`)
across all attempts and ~140 users since the release."
