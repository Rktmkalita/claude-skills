---
name: living-flow-map
description: >
  Maintain and consult a living cross-service flow map: one project-local knowledge base for a
  single end-to-end flow (login, checkout, sign-up, passkey enrolment, payment, ...) that spans
  several services or repos, updated with verified file:line findings from whichever repo you are
  in. Use when investigating an incident or bug in a multi-service flow, when the user says "flow
  map", "trace this flow across services", "which service owns this step", "update the flow map",
  "record what we found", or "add this service to the map".
---

# Living Cross-Service Flow Map

A flow that crosses several services is rarely documented in one place, and each repo only shows
its own slice. This skill keeps **one Markdown map per flow** that you both **read to trace the
flow** and **update with verified findings** from whichever repo you are currently in, so the full
cross-service path stays traceable over time.

The skill itself holds no service knowledge. It ships with an **empty** registry and a per-service
template. The map belongs to the project.

## Where the map lives

- Store it in the project, e.g. `docs/flows/<flow-name>.md` (kebab-case flow name). Never write it
  inside this skill's folder.
- If several repos share the flow, keep the map in the repo the user nominates (or a shared docs
  repo) and link to it from the others. Ask the user if it is unclear; do not create duplicates.
- Before creating a map, search for an existing one: `docs/flows/`, `docs/`, and `*flow*.md`.

## When investigating an incident

1. Open the map for the flow. If none exists, ask the user whether to create one (see skeleton
   below) and continue the investigation either way.
2. Use the **Service Registry** and **Cross-Service Flow** to find which service owns the failing
   step.
3. Jump to that service's `## Service:` section for endpoints, `file:line` anchors, data stores
   and its debugging checklist. Work the checklist before improvising.
4. Check the section's **Verified** stamp. If the repo has moved on since that commit, re-verify
   every anchor you rely on (`git log <commit>..HEAD -- <file>`, then re-read the lines) before
   treating it as fact.
5. If the service you need is not documented, investigate the current repo and add a section from
   the template.

## When you learn something new (in any repo)

- Update the matching `## Service:` section, or add one from the template.
- **Pin every claim** to a `file:line`, config key, endpoint, message channel or table name. Record
  only what you confirmed in code or config. Anything inferred goes under **Open questions**, not
  in the body.
- **Stamp** the section with the date, repo and commit you verified against
  (`git rev-parse --short HEAD`). When you re-verify an existing section, update the stamp.
- Update the **Service Registry** and **Cross-Service Flow** whenever a service is added or its
  role changes. Keep the hop between services explicit: who calls whom, synchronously or via an
  event, and on which channel.
- **Resolve Open questions** as answers turn up (move the answer into the body with its anchor);
  add new ones you uncover.
- Do not record secrets, credentials, customer identifiers or personal data. Name the config key,
  never its value.
- Show the user the diff of the map after each update.

## Map skeleton (for a new map)

~~~markdown
# Flow: <flow-name>

**Scope:** <where the flow starts and where it ends>
**Last reviewed:** <date>

## Service Registry
| Service | Repo | Role in this flow | Section verified |
|---------|------|-------------------|------------------|

## Cross-Service Flow
```
<actor / client>
  → <service A: endpoint>
    → <service B: call or event, channel>
      → <data store>
```

## Open questions (cross-service)
- <unknowns that span more than one service>

<!-- one "## Service:" section per service, from the template below -->
~~~

## Per-service section template

~~~markdown
## Service: <service-name>

**Repo:** `<repo>` · **Verified:** <date> (commit `<short-sha>`)
**One-line role:** <what this service does in the flow>

### Responsibilities in this flow
- Owns which steps? <create / verify / store / forward / read-only / none>
- Key libraries: <library names relevant to the flow>

### Where the flow appears
| Location (file:line / config key / endpoint) | What it is |
|----------------------------------------------|------------|
| | |

### Flow (entry point → downstream)
```
<endpoint / consumer / scheduled job>
  → <Class.method  file:line>
    → <downstream service / data store / message channel>
```

### Data / integration touchpoints
- Data stores, message channels and external calls involved (names, not credentials)

### Debugging checklist
- <symptom> → <what to check, with file:line>

### Open questions
- <unknowns to resolve>
~~~

## References

- `references/webauthn-debugging.md` — example domain appendix: generic WebAuthn / passkey
  debugging knowledge. Use it as a model for writing a domain appendix for your own flow, and
  consult it when the flow involves passkeys.
