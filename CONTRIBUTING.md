# Contributing

Small, focused improvements are welcome. Start with one skill or one reproducible example.

## Useful first contributions

- Try [the synthetic incident exercise](examples/incident-demo.md) and report where instructions are unclear.
- Add a second fully invented scenario with a different failure mechanism and evidence-linked answer key.
- Improve installation troubleshooting with your Claude Code version and a reproducible fix.
- Clarify a skill instruction that produces a missed finding or false positive. Include a before/after synthetic example.

These are suggestions, not assigned tasks. Open an issue before a large redesign so scope can be discussed.

## Report a problem

Include the skill name, plugin version or commit, Claude Code version/model, optional MCP tools, minimal prompt, expected behavior, actual behavior, and a synthetic reproduction. State whether you ran the workflow or only reviewed its instructions. Model outputs can vary; one successful run is not an accuracy benchmark.

## Submit a pull request

1. Create a branch and make one focused change.
2. Explain the concrete problem and resulting behavior.
3. Check Markdown links and referenced paths. For plugin metadata edits, parse both JSON manifests and verify every registered skill path exists.
4. If changing skill behavior, try it on a synthetic fixture and record the model, prompt, result, and limitations. Do not claim a run you did not perform.
5. Run `bash scripts/scrub-check.sh` from the repository root and manually review the diff for confidential content. Automated checks cannot guarantee confidentiality.

No automated test suite or CI success is implied by this checklist. If you cannot run a check, say which one and why.

## Public-data boundary

Use newly invented examples. Never contribute employer source code, incident exports, production logs, credentials, customer information, internal names, private repository paths, or internal URLs. Renaming a real incident does not make it suitable for publication. Do not publish a security-sensitive reproduction in a public issue; use GitHub private vulnerability reporting if enabled.

Contributions should be compatible with the repository MIT license.
