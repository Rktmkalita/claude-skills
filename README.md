# raktim-skills

Engineering skills for [Claude Code](https://claude.com/claude-code), packaged as an installable plugin.

> **Stack focus:** most of these skills are written for **Java / Spring / Spring Boot / Maven** projects. Their checks, examples and commands assume that stack (`pom.xml`, `@ControllerAdvice`, JaCoCo, Surefire/Failsafe, JUnit 5 + Mockito + AssertJ). The investigation skills, `secondary-pr-review` and `sql-migration-repo-explorer` work with any stack.
>
> | Scope | Skills |
> |---|---|
> | Java / Spring Boot / Maven | `pr-review`, `springboot-upgrade`, `repo-map` (other stacks via its file-glob parameter), `claude-md-generator` (Java/Spring examples) |
> | Any stack, Java examples | `guided-implementation` |
> | Any stack | `secondary-pr-review`, `sql-migration-repo-explorer` (Oracle / PostgreSQL), `incident-investigation`, `flow-reconstruction`, `living-flow-map` |

## Install

```bash
claude plugin marketplace add Rktmkalita/claude-skills
claude plugin install raktim-skills@raktim
```

Skills are then available as `/raktim-skills:<skill-name>`, and also trigger automatically from their descriptions.

## Skills

### Review

| Skill | What it does | Try |
|---|---|---|
| [`pr-review`](skills/review/pr-review/SKILL.md) | Multi-agent PR review for Java / Spring Boot / Maven. It profiles the repo, checks dependency changes, then runs four reviewers with different jobs: production safety, design, devil's advocate and code style. A consensus and arbitration step follows, then an evidence-chain validation sweep. Output is a Markdown report plus paste-ready inline comments. | "review this PR" |
| [`secondary-pr-review`](skills/review/secondary-pr-review/SKILL.md) | Single-pass review for any language. Outputs a machine-readable JSON array, reporting only findings it is at least 80% confident about. | "quick review", "JSON review" |

### Codebase

| Skill | What it does | Try |
|---|---|---|
| [`repo-map`](skills/codebase/repo-map/SKILL.md) | Builds `REPO_MAP.md`: project structure, shared components, a full API inventory and request-flow traces for each API. It records a `baseline_commit`, so later runs re-document only what changed. | "generate a repo map" |
| [`claude-md-generator`](skills/codebase/claude-md-generator/SKILL.md) | Writes a project `CLAUDE.md` from actual code analysis: stack, commands, architecture and conventions, each with a reference file. | "generate a CLAUDE.md" |
| [`sql-migration-repo-explorer`](skills/codebase/sql-migration-repo-explorer/SKILL.md) | A method for exploring a database repo whose schema is spread across incremental migration scripts, checked against the live data dictionary. Covers Oracle and PostgreSQL. | "which stored procedure writes this table?" |

### Engineering

| Skill | What it does | Try |
|---|---|---|
| [`guided-implementation`](skills/engineering/guided-implementation/SKILL.md) | Works in four phases (SCOPE → CHALLENGE → IMPLEMENT → REVIEW) and stops for your go-ahead at each checkpoint. A separate agent challenges the design before any code is written. | "implement this, guided" |
| [`springboot-upgrade`](skills/engineering/springboot-upgrade/SKILL.md) | Upgrades Spring Boot and Java across every module and deployment target, with checkpoints. It finds each target's runtime constraints before choosing the versions. | "upgrade to Spring Boot 4" |

### Investigation

| Skill | What it does | Try |
|---|---|---|
| [`incident-investigation`](skills/investigation/incident-investigation/SKILL.md) | Takes an alert through to a ranked list of probable causes: environment check, health check, logs, environment-wide trace correlation and recent changes. A three-agent council produces the ranking, and a skeptic can veto. You provide a service map for your own services. | "investigate incident #123" |
| [`flow-reconstruction`](skills/investigation/flow-reconstruction/SKILL.md) | Reconstructs one user's multi-step flow from logs and spans when the steps are not joined in a single trace. The result is a time-ordered evidence table, where each row says how it was linked to that user. | "prove these calls belong to the same user" |
| [`living-flow-map`](skills/investigation/living-flow-map/SKILL.md) | Keeps a flow map inside your project for one end-to-end flow that crosses several services. You update it from whichever repo you're in, and every finding is pinned to a file:line and commit. | "update the flow map" |

## Optional tools

The skills only need Claude Code's built-in tools. If any of these are installed, the skills use them and otherwise fall back to built-in tools:

- [Serena MCP](https://github.com/oraios/serena): semantic code navigation and memories
- SuperClaude `/sc:*` commands
- Sequential-thinking MCP
- An observability MCP (e.g. Honeycomb) and an alerting MCP (e.g. PagerDuty), used by the investigation skills

## Example global CLAUDE.md

[`examples/CLAUDE.md`](examples/CLAUDE.md) is a set of general working rules that go well with these skills.

## License

[MIT](LICENSE)
