# Worked example — request → emailed link → consume token

All services, endpoints, log strings, ids and addresses below are **fictional**. The example shows
the flow-reconstruction method, not any real system.

## The system (fictional)

| Service | Role | Logs to |
|---|---|---|
| `web-frontend` | "Forgot password" page and the page the emailed link opens | body (request lines) |
| `support-console` | Support agents trigger a reset on a user's behalf | body |
| `identity-service` | Issues the reset token, builds the link, verifies the second factor, sets the password | body |
| `notification-service` | Sends the email from a queued message | body |

Two entry points reach `identity-service`:

- **Self-service:** `web-frontend` → `POST /v1/users/{id}/recovery-requests`
- **Support-initiated:** `support-console` → `POST /v1/users/{id}/recovery-requests/assisted`

The user then clicks `https://app.example.test/recover?t=***<suffix>` and submits a new password
plus the last four digits of their registered phone number → `PUT /v1/recovery/complete`.

Token validity: 60 minutes. The response to `PUT /v1/recovery/complete` is **always HTTP 200**;
the outcome is in the body field `result`.

## The ticket

> User `u-100482` says the reset link "shows a technical error". Happened yesterday afternoon
> (user is in UTC+2).

## Step 0 — Environment

"I will investigate in **prod**, window yesterday 11:00–17:00 UTC. Confirm?" → confirmed.

## Step 1 — Linked identities

Only one id is involved here (`u-100482`); `identity-service` logs it directly. No partner ids.

## Step 2 — Anchor event (was a token issued?)

```
service.name = identity-service
body contains "u-100482"
time: yesterday 11:00–17:00 UTC
breakdowns: http.route, http.status_code, trace.trace_id
include_samples: true
```

Relevant lines (fictional format):

```
13:02:11 recovery requested userId=u-100482 channel=self-service
13:02:11 recovery token issued userId=u-100482 token=***Q4XK9TRM expiresAt=14:02:11Z
13:02:12 recovery message queued type=RECOVERY_LINK userId=u-100482
13:05:40 recovery token issued userId=u-100482 token=***H7PL2ZWA expiresAt=14:05:40Z
13:05:41 recovery message queued type=RECOVERY_LINK userId=u-100482
13:05:58 recovery token issued userId=u-100482 token=***M3DN8YQC expiresAt=14:05:58Z
13:05:59 recovery message queued type=RECOVERY_LINK userId=u-100482
```

- Route is `/recovery-requests` (not `/assisted`) → self-service. `support-console` shows nothing
  for this user in the window, which agrees.
- **Three tokens in under four minutes** (lesson: multiple rapid generations) → the user retried.
  The real question is which token was actually presented.

Confirm dispatch in `notification-service`:

```
service.name = notification-service
body contains "u-100482"
time: 13:00–13:10 UTC
```

Three `email accepted by relay type=RECOVERY_LINK` lines at 13:02:13, 13:05:43, 13:06:01 → the
emails left the system.

## Step 3 — Pivot on the secondary key (token suffix)

`PUT /v1/recovery/complete` does not log the user id until the token is resolved; it logs the
masked token. Search each suffix:

```
service.name = identity-service
body contains "M3DN8YQC"          # repeat for Q4XK9TRM, H7PL2ZWA
time: [issue time, expiry]
include_samples: true
```

Only `M3DN8YQC` (the newest) has hits. `Q4XK9TRM` and `H7PL2ZWA` have zero — never presented.

## Step 4 — Tight window around the presentation

```
13:09:02 recovery token lookup token=***M3DN8YQC
13:09:02 recovery token resolved token=***M3DN8YQC userId=u-100482 expiresAt=14:05:58Z
13:09:31 recovery completion attempted token=***M3DN8YQC
13:09:31 recovery completion result=FACTOR_MISMATCH userId=u-100482
13:10:15 recovery completion attempted token=***M3DN8YQC
13:10:15 recovery completion result=FACTOR_MISMATCH userId=u-100482
```

`web-frontend` for the same minutes (body-logged, filter by the two trace ids) shows
`PUT /v1/recovery/complete → 200` both times, then the page rendered its generic
"technical error" template.

## Step 5 — MISSING vs INVALID

- Token: resolved, used at 13:09 with expiry 14:05 → **not expired, not missing**.
- Factor: `FACTOR_MISMATCH` means a value was sent and did not match (INVALID branch). A missing
  value would log `result=FACTOR_ABSENT`. So the user entered the wrong phone digits.
- **HTTP 200 with a failure body** (lesson): the status code alone says "success".

## Step 6 — Anchoring

| Step | Tie |
|---|---|
| Token issued | user id in body ✓ |
| Email sent | user id in body ✓ |
| Token presented / completion | token suffix continuity + `userId` in the "resolved" line ✓ |
| Frontend error page | same trace id as the completion call ✓ |

Every row is subject-verified; nothing rests on IP.

## Step 7 — Proof table

| # | Time (UTC) | Event | Service | Result | Tied by |
|---|---|---|---|---|---|
| 1 | 13:05:58 | token `***M3DN8YQC` issued (3rd of 3) | identity-service | ok | user id in body |
| 2 | 13:06:01 | email accepted by relay | notification-service | ok | user id in body |
| 3 | 13:09:02 | link opened, token resolved | identity-service | valid, expires 14:05:58 | suffix + user id |
| 4 | 13:09:31 | completion #1 | identity-service | 200, `FACTOR_MISMATCH` | suffix |
| 5 | 13:10:15 | completion #2 | identity-service | 200, `FACTOR_MISMATCH` | suffix |
| 6 | 13:10:15 | generic error page | web-frontend | rendered | same trace as row 5 |

Span: 4 min 17 s, one token, one user. Earlier tokens were issued but never presented.

## Step 8 — Fleet check

```
service.name = identity-service
body contains "result=FACTOR_MISMATCH"
time: yesterday, and same weekday one week earlier
calculations: COUNT, COUNT_DISTINCT(userId)
```

Rate is flat versus the baseline and spread across many users → no systemic defect.

## Step 9 — Symptom → cause

| Symptom | Likely cause |
|---|---|
| Token issued, email accepted, no presentation | Link never clicked / spam folder / expired before click |
| Presented after `expiresAt` | Expired; user needs a new link |
| 200 + `FACTOR_MISMATCH`, UI "technical error" | Wrong second-factor value; UI shows a generic error |
| 200 + `FACTOR_ABSENT` | Frontend did not send the factor field (caller bug) |
| Only `/assisted` route hits | Support-initiated, user did not request it |
| Many rapid issuances | Retrying an unresolved problem — find the one token presented |
| Nothing in identity-service | Wrong environment/window, or reset never triggered |

**Conclusion:** the user entered the wrong phone digits twice; the frontend maps the 200 +
`FACTOR_MISMATCH` response to a generic error. Handoff: the page should show a specific
"details don't match" message; the user should check the phone number on record.
