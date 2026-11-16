# Synthetic incident demo: checkout failures after a deploy

Everything here is invented for this public exercise: services, identifiers, timestamps, metrics, events, and change descriptions. No employer material or production data was used. This is a static evidence exercise, not a running system or a benchmark.

## Try it

Install the plugin using the repository README. Save this file locally. In Claude Code, invoke `/raktim-skills:incident-investigation`, then paste the prompt below and the Evidence bundle section only. Keep the answer key out of the initial context for a less leading exercise. No MCP, credentials, or external service access is needed. A Claude Code subscription or API usage may still incur cost.

```text
Investigate DEMO-001 using only the supplied synthetic evidence. The confirmed environment is demo, never production. Treat the tables below as manually supplied exports and service map; do not query external systems or change files. Use evidence IDs in place of query links. Do not invent commits, URLs, agent runs, or missing telemetry. Rank causes, challenge the obvious deployment explanation, and state the cheapest next check. If independent agents are unavailable, say so and provide one analysis rather than claiming a council ran.
```

## Evidence bundle

### Service map and alert

- Team: Fictional Checkout Demo
- Environment: demo (explicitly confirmed)
- Alert source: supplied static alert A1; no live integration
- Observability: supplied tables H1, L1-L6; no live backend or query links
- Health reference: H1; all timestamps UTC on 2026-01-15
- Code host: supplied change descriptions C1-C2; no live repository
- Wiki/runbooks/known incidents: none supplied
- Entry point: checkout-gateway; owns HTTP response
- State owner: orders-service; owns order transitions
- Dependency: inventory-service; stock reservations
- Sources: each named service uses its matching service name in L1-L6
- IDs: customer DEMO-CUST-001; order DEMO-ORDER-001; trace DEMO-TRACE-001 (teaching labels, not W3C trace IDs)

| ID | Time | Alert |
|---|---|---|
| A1 | 10:06 | checkout-gateway 5xx above 10% for five minutes; sample order DEMO-ORDER-001 |

### Health export

H1: five-minute windows; 1,000 gateway requests in each window. These are aggregate teaching data, not calculated from the handful of sample events below.

| Service | Window | HTTP 5xx | CPU | Connection pool active/max | Restarts | GC max pause |
|---|---|---|---|---|---|---|
| checkout-gateway | 09:55-10:00 | 1% | 28% | 4/30 | 0 | 12 ms |
| checkout-gateway | 10:01-10:06 | 18% | 30% | 5/30 | 0 | 14 ms |
| orders-service | 09:55-10:00 | 1% | 33% | 8/20 | 0 | 18 ms |
| orders-service | 10:01-10:06 | 18% | 35% | 20/20 | 0 | 20 ms |
| inventory-service | 09:55-10:00 | 0% | 21% | 3/20 | 0 | 9 ms |
| inventory-service | 10:01-10:06 | 0% | 22% | 3/20 | 0 | 10 ms |

### Sample events

All rows are supplied demo exports. L2-L5 are the complete supplied search result for DEMO-TRACE-001 across all three service sources. L1 is a separate state-worker event found by order ID. No other events or orphaned-event counts are available.

| ID | Time | Service | Event |
|---|---|---|---|
| L1 | 10:00:59 | orders-service | worker=batch-export acquired 20 connections; order=DEMO-ORDER-001; transaction still open at 10:01:20 |
| L2 | 10:01:00.000 | checkout-gateway | customer=DEMO-CUST-001 order=DEMO-ORDER-001 trace=DEMO-TRACE-001 POST /checkout accepted |
| L3 | 10:01:00.010 | inventory-service | order=DEMO-ORDER-001 trace=DEMO-TRACE-001 reserve status=200 duration=8ms |
| L4 | 10:01:01.020 | orders-service | order=DEMO-ORDER-001 trace=DEMO-TRACE-001 connection acquisition timeout after 1000ms; active=20 max=20; HTTP 503 |
| L5 | 10:01:01.030 | checkout-gateway | order=DEMO-ORDER-001 trace=DEMO-TRACE-001 downstream orders-service=503; response=502 |
| L6 | 10:01:01.040 | orders-service | order=DEMO-ORDER-001 state=PENDING; no transition to CONFIRMED recorded in supplied window |

### Recent changes

These are fictional change descriptions, not Git commits or verified diffs.

| ID | Time | Change |
|---|---|---|
| C1 | 09:58 | checkout-gateway deploy changes access-log formatting; no supplied evidence of routing or timeout changes |
| C2 | 10:00 | orders-service configuration enables a batch export worker with concurrency=20; HTTP traffic and worker share the max=20 database pool |

## Answer key: illustrative report

This is a hand-authored explanation of the fixture, not captured model output. No agents were executed to produce it and no success rate is claimed.

**Observed failure:** the order request cannot acquire a database connection (L4); the gateway translates the downstream 503 to 502 (L5). Pool occupancy reaches 20/20 while CPU and GC remain near baseline (H1). The state owner records PENDING (L6); the fixture does not prove the order never completed later.

**Leading hypothesis:** the newly enabled batch worker contends with request traffic for the shared pool. C2 describes capacity equal to the whole pool; L1 records the worker holding all 20 connections across the failed request. H1 and L4 independently support pool saturation as the immediate failure mechanism. The fixture strongly supports worker contention, but does not contain a controlled rollback or a full database investigation proving the ultimate cause.

**Weaker alternatives:** slow database queries or locks could explain why worker transactions stay open; no query durations or lock data are supplied. Inventory failure is weaker because the sample reservation succeeds quickly (L3), and its aggregate health is steady (H1). A gateway regression remains possible, but C1 is temporal correlation and does not explain L1/L4 as directly as C2 does.

**Cheapest next check:** in an authorized demo environment, inspect transaction duration and connection ownership for the batch worker. A separately approved concurrency reduction followed by recovery would strengthen causality. No mitigation was executed here.

## Self-check

A useful answer cites H1, L1, L4, and C2; traces L2-L5; checks the separate order-state evidence L6; challenges C1; and preserves the missing DB evidence. It must not invent a successful rollback, claim the order was permanently lost, or present a numeric confidence score as measured accuracy. Different wording or rankings are not automatically failures.
