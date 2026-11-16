# Claude Code skills for incident investigation and Java / Spring Boot review

**raktim-skills** is an installable Claude Code plugin with 10 engineering skills. Investigate alerts with evidence, review backend changes with multiple reviewers, and map unfamiliar codebases.

- **On-call engineers:** correlate logs and traces, rank probable causes, and reconstruct cross-service flows.
- **Java backend developers:** review Spring Boot / Maven changes and plan upgrades.
- **Maintainers:** generate repository maps and project-specific CLAUDE.md instructions.

## Install

```bash
claude plugin marketplace add Rktmkalita/claude-skills
claude plugin install raktim-skills@raktim
```

Requires Claude Code. Open it in a repository you are authorized to analyze. Skills are available as `/raktim-skills:<skill-name>` and can also trigger from their descriptions.

## Start here

For a focused review of a local diff:

```text
/raktim-skills:secondary-pr-review
Review the current diff. Return only high-confidence findings as JSON.
```

For a Java / Spring Boot repository:

```text
/raktim-skills:repo-map
Map this repository and trace its API request flows.
```

For incident investigation, supply your service map and telemetry. The plugin does not grant access to monitoring systems. You can supply exported evidence when an MCP integration is unavailable.

## Skills

| Skill | What you get | Stack |
|---|---|---|
| [incident-investigation](skills/investigation/incident-investigation/SKILL.md) | Alert-to-evidence investigation with ranked causes, independent investigators, and skeptical review | Any |
| [flow-reconstruction](skills/investigation/flow-reconstruction/SKILL.md) | Time-ordered evidence for a multi-step flow without a single shared trace | Any |
| [living-flow-map](skills/investigation/living-flow-map/SKILL.md) | Cross-service flow documentation pinned to source locations and commits | Any |
| [pr-review](skills/review/pr-review/SKILL.md) | Multi-agent review covering production safety, design, adversarial analysis, and style | Java / Spring Boot / Maven |
| [secondary-pr-review](skills/review/secondary-pr-review/SKILL.md) | Single-pass review returning high-confidence findings as JSON | Any |
| [repo-map](skills/codebase/repo-map/SKILL.md) | REPO_MAP.md with structure, APIs, and request flows; incremental updates from a baseline commit | Java focus; configurable file globs |
| [claude-md-generator](skills/codebase/claude-md-generator/SKILL.md) | CLAUDE.md grounded in actual project commands and conventions | Java / Spring examples |
| [sql-migration-repo-explorer](skills/codebase/sql-migration-repo-explorer/SKILL.md) | Schema exploration across migration scripts and the live data dictionary | Oracle / PostgreSQL |
| [guided-implementation](skills/engineering/guided-implementation/SKILL.md) | Scope, challenge, implement, and review with human checkpoints | Any; Java examples |
| [springboot-upgrade](skills/engineering/springboot-upgrade/SKILL.md) | Upgrade planning across modules and deployment runtime constraints | Java / Spring Boot / Maven |

## See the investigation approach

**[Try the synthetic checkout incident](examples/incident-demo.md):** investigate a failure using supplied metrics, cross-service events, and recent changes. No live integrations are required. Includes a prompt, evidence bundle, illustrative answer key, and self-check.

Existing walkthroughs explain how to connect evidence across a flow:

- [Token-link flow](skills/investigation/flow-reconstruction/references/example-token-link-flow.md)
- [Mobile OAuth environment switch](skills/investigation/flow-reconstruction/references/example-mobile-oauth-env-switch.md)

## Tools and limitations

Claude Code built-in tools provide the baseline. Optional integrations include [Serena MCP](https://github.com/oraios/serena), SuperClaude commands, sequential-thinking MCP, and alerting/observability MCPs such as PagerDuty and Honeycomb. Without an integration, provide the equivalent evidence manually.

Review findings against source evidence. Multi-agent workflows can use more time and tokens than a single-pass review. Confidence scores are model judgments, not calibrated probabilities; no accuracy or incident-resolution benchmark is claimed.

Keep credentials, customer information, employer code, internal URLs, and production telemetry out of public issues and examples. Use fully synthetic reproductions.

## Feedback

See [CONTRIBUTING.md](CONTRIBUTING.md) for focused contribution ideas and validation guidance. Issue and PR templates help you share actionable, synthetic reproductions.

[Open an issue](https://github.com/Rktmkalita/claude-skills/issues/new) with the skill name, expected behavior, actual behavior, and a minimal synthetic reproduction. Installation reports should include Claude Code version and relevant tool setup. If a skill helps your workflow, a star helps others discover the project.

## Example global CLAUDE.md

[examples/CLAUDE.md](examples/CLAUDE.md) contains general working rules that complement these skills.

## License

[MIT](LICENSE)
