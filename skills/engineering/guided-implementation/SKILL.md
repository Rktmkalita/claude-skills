---
name: guided-implementation
description: >
  Structured 4-phase implementation workflow (SCOPE → CHALLENGE → IMPLEMENT → REVIEW)
  with stop-and-wait checkpoints. Use when the user asks to implement a feature or fix
  "guided", "step by step", "with checkpoints", or wants analysis and a design
  cross-check before any code is written.
---

# Guided Implementation Skill

A structured 4-phase implementation workflow that ensures thorough analysis before coding.

**Pattern**: SCOPE → CHALLENGE → IMPLEMENT → REVIEW

This skill prevents Claude from jumping to implementation and ensures steering happens during scoping, not just review.

---

## Tooling (optional integrations)

Everything in this skill works with built-in Claude Code tools (Glob, Grep, Read, Edit, Write, Bash, Agent, AskUserQuestion, TodoWrite). Optional integrations, used only if installed:

- **SuperClaude** (`/sc:*` commands): may replace the plain instructions noted at each step.
- **Serena MCP** (`write_memory`, `read_memory`, `think_about_*`): may replace the task file and self-checks.
- **sequential-thinking MCP**: may be used for flow tracing.

**Default persistence (no Serena):** keep requirements, SCOPE output and challenge decisions in `.claude/guided-implementation/<task>.md` in the repo, and track progress with TodoWrite.

---

## Activation

When the user invokes this skill, follow this exact workflow.

---

## PHASE 0: REQUIREMENTS GATHERING

Before starting any phase, gather requirements from the user using AskUserQuestion:

### Required Information

Ask the user for:

1. **Task Description**: What feature/fix/change needs to be implemented?
2. **Success Criteria**: How will we know it's done correctly?
3. **Constraints**: Any specific requirements (backward compatibility, no breaking changes, specific patterns to follow)?
4. **Test Expectations**: Should existing tests pass? New tests required?

### Template Question

```
Before we begin, I need some details:

1. **What are you implementing?**
   (e.g., "Add API key authentication", "Fix N+1 query in OrderService")

2. **What are the success criteria?**
   (e.g., "All endpoints except /actuator/health require X-API-Key header")

3. **Any constraints I should know?**
   (e.g., "Must be backward compatible", "Follow CustomerController patterns")

4. **Test expectations?**
   - [ ] All existing tests must pass
   - [ ] New tests required for new functionality
   - [ ] Specific test scenarios needed
```

### Store Context

After gathering requirements, persist the task context in `.claude/guided-implementation/<task>.md` under a `current_task_requirements` heading:

```
current_task_requirements: { description, success_criteria, constraints, test_expectations }
```

(Optional: if Serena MCP is available, you may instead use `write_memory` with key `current_task_requirements`.)

---

## PHASE 1: SCOPE (Analysis Before Implementation)

**Goal**: Understand the codebase state and identify implementation options. NO CODE CHANGES.

### Actions

1. **Analyze the current state**: read the relevant files and summarise their architecture, responsibilities and dependencies.
   (Optional: if SuperClaude is installed you may use `/sc:analyze [relevant-files] --focus architecture --depth deep`.)

2. **Identify affected files** using Glob/Grep:
   - Controllers, Services, Repositories touched
   - DTOs that need changes
   - Configuration files
   - Test files that exist

3. **Map the current flow** step by step, tracing:
   ```
   - Entry point (Controller)
   - Service layer logic
   - Repository/External calls
   - Response construction
   ```
   (Optional: if the sequential-thinking MCP is available you may use it for this trace.)

4. **Identify implementation options** (at least 2-3 approaches)

5. **Check for existing patterns** in reference modules (e.g., CustomerController)

### Output Format

```markdown
## SCOPE ANALYSIS

### Current State
- [File]: [Current behavior]
- [File]: [Current behavior]

### Files Requiring Changes
| File | Change Type | Reason |
|------|-------------|--------|
| ... | Add/Modify/Delete | ... |

### Implementation Options

**Option A: [Name]**
- Approach: ...
- Pros: ...
- Cons: ...

**Option B: [Name]**
- Approach: ...
- Pros: ...
- Cons: ...

### Recommended Approach
[Option X] because [reasoning]

### Open Questions for User
1. [Question about approach]
2. [Question about edge case]
```

### STOP AND WAIT

After presenting the scope analysis:
- **DO NOT proceed to implementation**
- **ASK the user**: "Do you want me to proceed with [recommended approach], or do you have questions about the analysis?"

---

## PHASE 2: CHALLENGE (Cross-Check Agent Generates Questions)

**Goal**: Validate the proposed approach by having a SEPARATE AGENT cross-check the SCOPE output and generate probing questions.

### Why a Separate Agent?

- **Fresh perspective**: The Challenge Agent didn't create the SCOPE analysis, so it reviews with unbiased eyes
- **Better questions**: Questions are dynamically generated based on the SPECIFIC approach proposed, not generic templates
- **Simulates peer review**: Like having a colleague review your design before implementation

### Trigger

After Phase 1 SCOPE completes and user acknowledges the analysis, spawn the Challenge Generator Agent.

### Challenge Generator Agent

**Spawn using the Agent tool:**

```
Agent tool:
  subagent_type: "general-purpose"  # or "self-review" / "root-cause-analyst" if SuperClaude agents are installed
  description: "Generate challenge questions for SCOPE"
  prompt: [See CHALLENGE_AGENT_PROMPT below]
```

### CHALLENGE_AGENT_PROMPT

```
You are a Challenge Generator Agent. Your role is to CROSS-CHECK a proposed
implementation approach and generate probing questions.

You did NOT create this analysis. Review it critically as a skeptical peer reviewer.

## Original Task

{task_description}

## Success Criteria

{success_criteria}

## Constraints

{constraints}

## SCOPE Analysis to Cross-Check

{scope_output}

---

## Your Tasks

1. **Validate the Recommended Approach**
   - Is the reasoning sound?
   - Are there hidden assumptions?
   - What's missing from the analysis?

2. **Generate 5-8 Challenge Questions**

   For each question:
   - Target a specific aspect of the proposed approach
   - Probe edge cases, error handling, or consistency
   - Ask "why X over Y" for key decisions
   - Include at least one security/performance question if relevant

   Question Categories to Cover:
   - **Core Approach**: Why this solution over alternatives?
   - **Edge Cases**: What happens when [unusual input]?
   - **Error Handling**: What if [failure scenario]?
   - **Consistency**: Does this match [reference pattern]?
   - **Testing**: How will we verify [specific behavior]?
   - **Backward Compatibility**: What breaks for existing callers?
   - **Security** (if applicable): What's the attack surface?
   - **Performance** (if applicable): What's the scaling concern?

3. **Identify Risks**
   - What could go wrong with this approach?
   - What's the hardest part to get right?

4. **Suggest Clarifications**
   - What should the user clarify before proceeding?

## Output Format

Return in this exact format:

```markdown
## CHALLENGE QUESTIONS

Cross-check by Challenge Agent | {timestamp}

### Approach Validation

**Recommended approach**: {summarize the recommendation}

**Assessment**: [SOUND / NEEDS CLARIFICATION / CONCERNS]

**Reasoning check**: {1-2 sentences on whether reasoning is solid}

---

### Questions for User

Answer these before proceeding to implementation:

1. **[Category: Core Approach]**
   {Specific question about the main decision}
   _Why this matters: {brief explanation}_

2. **[Category: Edge Case]**
   {Question about unusual/boundary input}
   _Why this matters: {brief explanation}_

3. **[Category: Error Handling]**
   {Question about failure scenario}
   _Why this matters: {brief explanation}_

4. **[Category: Consistency]**
   {Question comparing to reference pattern}
   _Why this matters: {brief explanation}_

5. **[Category: Testing]**
   {Question about how to verify behavior}
   _Why this matters: {brief explanation}_

[Add 2-3 more questions based on task type]

---

### Identified Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| {risk 1} | LOW/MED/HIGH | {impact} | {how to mitigate} |
| {risk 2} | LOW/MED/HIGH | {impact} | {how to mitigate} |

---

### Clarifications Needed

Before implementing, clarify:
- [ ] {Clarification 1}
- [ ] {Clarification 2}
```
```

### After Agent Returns

1. **Present the Challenge Questions to User**

   Display the full output from the Challenge Agent.

2. **Collect User Responses**

   Use AskUserQuestion or wait for user's text responses to each question.

3. **Document Decisions**

   After user answers, summarize:
   ```markdown
   ## Design Decisions (from Challenge Phase)

   | Question | User Decision |
   |----------|---------------|
   | {Q1} | {Answer/Decision} |
   | {Q2} | {Answer/Decision} |
   ...
   ```

4. **Persist the decisions**
   Append to `.claude/guided-implementation/<task>.md` under a `challenge_decisions` heading:
   ```
   challenge_decisions: { questions, answers, risks_accepted }
   ```
   (Optional: if Serena MCP is available, you may instead use `write_memory` with key `challenge_decisions`.)

### STOP AND WAIT

After presenting Challenge Agent's questions:

- **DO NOT proceed until user answers the questions**
- If user's answers reveal concerns, **update the approach** and optionally re-run SCOPE
- Once user confirms all questions addressed: proceed to IMPLEMENT

### Fallback: Manual Challenge Questions

If the Agent tool is unavailable, use these templates based on task type:

**For Security/Auth tasks:**
- What HTTP status code? 401 vs 403?
- Is sensitive data logged anywhere?
- What happens if configuration is missing?
- How do we test authenticated endpoints?

**For Database/Migration tasks:**
- What's the storage type trade-off (ENUM vs VARCHAR vs INT)?
- What's the migration path for future changes?
- Is the default value applied in both migration AND entity?
- What happens with invalid input values?

**For Performance tasks:**
- Is this the root cause or a symptom?
- Why isn't the existing optimized method being used?
- What's the impact on other callers?
- Should we keep backward compatibility?

**For Feature Addition tasks:**
- Does this follow existing patterns (reference module)?
- What validation is needed?
- What happens in edge cases (null, empty, invalid)?
- Are all DTOs updated consistently?
- Can the tests be written without reflection? (If not, refactor the design)

---

## PHASE 3: IMPLEMENT (Incremental with Checkpoints)

**Goal**: Implement in small, verifiable steps. Show diff at each checkpoint.

### Checkpoint Structure

Break implementation into 3-6 checkpoints based on task complexity:

**Typical Checkpoint Flow:**

| Checkpoint | Focus | Deliverable |
|------------|-------|-------------|
| A | Configuration/Setup | Config file changes only |
| B | Core Logic | Main implementation (filter, service, entity) |
| C | Integration | Wire components together (controller, security config) |
| D | Existing Tests | Run tests, show failures |
| E | Fix Tests | Update existing tests |
| F | New Tests | Add tests for new functionality |

### At Each Checkpoint

1. **Announce the checkpoint**:
   ```
   ## Checkpoint [X]: [Focus]

   Implementing: [specific change]
   ```

2. **Make the changes** for this checkpoint only, keeping them minimal and safe, with tests where the checkpoint calls for them.
   (Optional: if SuperClaude is installed you may use `/sc:implement [specific-component] --safe --with-tests`.)

3. **Show the diff**:
   ```
   Show git diff for just this checkpoint's changes
   ```

4. **Validate against requirements**: re-read `current_task_requirements` in the task file and verify the changes align with them.
   (Optional: if Serena MCP is available you may use `think_about_collected_information`.)

5. **STOP AND WAIT**:
   ```
   Checkpoint [X] complete.
   - Changes: [summary]
   - Next: [what's coming in checkpoint X+1]

   Proceed to next checkpoint? [Y/n]
   ```

### Test Checkpoint (Critical)

After implementation checkpoints, ALWAYS:

1. **Run tests**:
   ```bash
   # select the project's JDK/toolchain first if needed, then run the project's test command, e.g.
   mvn test
   ```
   (Optional: if SuperClaude is installed you may use `/sc:test`.)

2. **Show failures clearly**:
   ```
   ## Test Results

   Failing tests: X
   - [TestClass.testMethod]: [reason]
   - [TestClass.testMethod]: [reason]

   Cause: [explanation - is the test wrong or implementation wrong?]
   ```

3. **Fix tests** in dedicated checkpoint (don't mix with implementation)

### Use TodoWrite

Track progress with TodoWrite throughout:

```
TodoWrite:
- [ ] Checkpoint A: Configuration
- [x] Checkpoint B: Core Logic (in_progress)
- [ ] Checkpoint C: Integration
- [ ] Checkpoint D: Run tests
- [ ] Checkpoint E: Fix failing tests
- [ ] Checkpoint F: Add new tests
```

---

## PHASE 4: REVIEW (Final Verification)

**Goal**: Verify the complete implementation matches requirements.

### Actions

1. **Show complete diff**:
   ```bash
   git diff
   ```

2. **Walk through each file**:
   ```markdown
   ## Review: [filename]

   ### Changes
   - Line X: [what changed]
   - Line Y: [what changed]

   ### Why Necessary
   [Explanation tied to requirements]
   ```

3. **Validate completion**:
   ```
   - Check all requirements in the task file are met
   - Verify no unintended changes
   ```
   (Optional: if Serena MCP is available you may use `think_about_whether_you_are_done`; if SuperClaude is installed, `/sc:reflect --type completion`.)

4. **Run final tests**:
   ```bash
   mvn test
   ```

5. **Check against success criteria**:
   ```markdown
   ## Success Criteria Verification

   | Criteria | Status | Evidence |
   |----------|--------|----------|
   | [Criterion 1] | PASS/FAIL | [How verified] |
   | [Criterion 2] | PASS/FAIL | [How verified] |
   ```

### Final Challenge Questions

Present these before completion:

```markdown
## Final Verification

- [ ] No endpoint accidentally left unprotected?
- [ ] Error responses match existing pattern (GlobalExceptionHandler)?
- [ ] No sensitive data logged?
- [ ] All DTOs updated consistently?
- [ ] Tests cover happy path AND error cases?
- [ ] No reflection used in tests (ReflectionTestUtils, setAccessible, etc.)?
- [ ] CLAUDE.md updated if new patterns introduced?
```

### Commit Prompt

If all checks pass:

```markdown
## Ready to Commit

All verification checks passed. Suggested commit:

\`\`\`bash
git add <files touched>
git commit -m "Task [N]: [description]

- [Change 1]
- [Change 2]
- [Change 3]"
\`\`\`

Commit now, or will you commit manually? (Optional: if SuperClaude is installed, `/sc:git` can be used.)
```

---

## WORKFLOW COMMANDS INTEGRATION

Default tools per phase. The SuperClaude column is optional and applies only if SuperClaude is installed:

| Phase | Default (built-in) | Optional SuperClaude | Purpose |
|-------|--------------------|----------------------|---------|
| SCOPE | Glob / Grep / Read | `/sc:analyze` | Understand current state |
| SCOPE | AskUserQuestion | `/sc:brainstorm` | Requirements discovery (if ambiguous) |
| CHALLENGE | **Agent (general-purpose)** | `self-review` agent | Cross-check SCOPE, generate questions |
| CHALLENGE | AskUserQuestion | – | Collect user decisions |
| IMPLEMENT | Edit / Write | `/sc:implement --safe` | Safe implementation |
| IMPLEMENT | Bash (project test command) | `/sc:test` | Run tests |
| REVIEW | Re-read task file + `git diff` | `/sc:reflect --type completion` | Verify done |
| REVIEW | Bash (`git add <files touched>`, `git commit`) | `/sc:git` | Commit changes |

### Challenge Agent Configuration

```
Agent tool parameters:
  subagent_type: "general-purpose"  # Default - always available
  # Optional (SuperClaude agents, if installed): "self-review" (validation focused),
  #   "root-cause-analyst" (deeper probing), "quality-engineer" (test-focused challenges)
  model: "sonnet"                   # Fast enough for question generation
  description: "Cross-check SCOPE analysis"
```

---

## PERSISTENCE (task file by default; Serena optional)

Default: keep one task file, `.claude/guided-implementation/<task>.md`, and track progress with TodoWrite. If Serena MCP is available, the matching Serena operation may be used instead:

| Default action | Optional Serena operation | When | Purpose |
|----------------|---------------------------|------|---------|
| Write `current_task_requirements` to task file | `write_memory` | Phase 0 | Persist task requirements |
| Write `scope_analysis` to task file | `write_memory` | Phase 1 | Persist SCOPE output |
| Write `challenge_decisions` to task file | `write_memory` | Phase 2 | Persist challenge Q&A |
| Re-read requirements, compare with diff | `think_about_collected_information` | Phase 3 | Verify each checkpoint |
| Re-read requirements, check each is met | `think_about_whether_you_are_done` | Phase 4 | Completion validation |
| Read the task file | `read_memory` | Session start | Restore context if resuming |

### Task File Keys

```yaml
current_task_requirements:
  description: "Task description from user"
  success_criteria: ["criterion 1", "criterion 2"]
  constraints: ["constraint 1"]
  test_expectations: "All tests pass, new tests for new functionality"

scope_analysis:
  current_state: {...}
  files_to_change: [...]
  recommended_approach: "Option A"
  reasoning: "..."

challenge_decisions:
  questions_asked: [...]
  user_answers: [...]
  risks_accepted: [...]
  clarifications: {...}
```

---

## CRITICAL RULES

1. **NEVER skip SCOPE phase** - Analysis before implementation
2. **NEVER proceed without user confirmation** at each phase boundary
3. **ALWAYS show diffs** before moving to next checkpoint
4. **ALWAYS run tests** before declaring implementation complete
5. **NEVER combine multiple checkpoints** - One focus per checkpoint
6. **CHALLENGE your own recommendations** - Present trade-offs honestly
7. **If tests fail, ASK** - Is the test wrong or the implementation?
8. **NEVER use reflection in tests** - No `ReflectionTestUtils`, `Field.setAccessible()`, or similar reflection hacks. If you need reflection to test something, the design is wrong. Refactor to use constructor injection, package-private access, or proper test doubles instead.

---

## EXAMPLE SESSION FLOW

```
User: [Invokes skill]

Claude: "Before we begin, I need some details..."
User: [Provides requirements]

Claude: "## SCOPE ANALYSIS
        [Analysis of current state, options, recommendation]

        Do you want me to proceed with Option A, or do you have questions?"
User: "Looks good, proceed"

Claude: "Spawning Challenge Generator Agent to cross-check the SCOPE analysis..."

        [Agent tool spawns general-purpose agent with SCOPE output]

Challenge Agent Returns:
        "## CHALLENGE QUESTIONS

        Cross-check by Challenge Agent | 2024-01-15T10:30:00Z

        ### Approach Validation
        Recommended approach: OncePerRequestFilter for API key auth
        Assessment: SOUND
        Reasoning check: Filter chain approach is correct for stateless API.

        ### Questions for User

        1. [Core Approach] Why OncePerRequestFilter over HandlerInterceptor?
           Why this matters: Interceptors run after Spring Security...

        2. [Edge Case] What if X-API-Key header is present but empty string?
           Why this matters: Empty vs missing may need different handling...

        3. [Error Handling] If application.yml has no keys, fail-fast or allow all?
           Why this matters: Fail-fast prevents insecure deployment...

        4. [Consistency] How does this match CustomerController's error response format?
           Why this matters: Consistent error responses for API consumers...

        5. [Testing] How will existing @WebMvcTest classes get API keys?
           Why this matters: All tests will fail without this...

        ### Identified Risks
        | Risk | Likelihood | Impact | Mitigation |
        | Tests break without key header | HIGH | All tests fail | Add test API key to test yml |

        ### Clarifications Needed
        - [ ] Support multiple named keys for audit logging?
        - [ ] Header name case sensitivity?"

User: "1. Filter runs before Spring Security which is what we want.
       2. Treat empty same as missing - reject.
       3. Fail-fast on startup.
       4. Use ErrorResponse format with ObjectMapper.
       5. Add test key to application-test.yml.
       Yes to multiple named keys. Header should be case-insensitive."

Claude: "## Design Decisions Captured

        | Question | Decision |
        |----------|----------|
        | Filter vs Interceptor | Filter - runs before Spring Security |
        | Empty header handling | Treat as missing, reject |
        | Missing config | Fail-fast on startup |
        | Error format | Match ErrorResponse via ObjectMapper |
        | Test strategy | Add key to application-test.yml |
        | Multiple keys | Yes, named map for audit logging |
        | Case sensitivity | Case-insensitive header matching |

        Proceeding to implementation..."

Claude: "## Checkpoint A: Configuration
        [Shows yml changes]

        Proceed to Checkpoint B?"
User: "Yes"

Claude: "## Checkpoint B: Core Logic
        [Shows filter implementation]

        Proceed to Checkpoint C?"
...

Claude: "## REVIEW
        [Complete diff, verification checklist]

        All checks pass. Ready to commit?"
User: "Commit it"

Claude: [Runs git add <files touched> and git commit]
```

---

## BOUNDARIES

**Will:**
- Guide implementation through structured phases
- Stop and wait for user confirmation at each phase
- Show diffs and run tests at checkpoints
- Optionally integrate with SuperClaude and Serena, if installed, for enhanced workflow

**Will Not:**
- Skip directly to implementation without analysis
- Proceed to next phase without user approval
- Combine multiple unrelated changes in one checkpoint
- Declare completion without running tests
- Make assumptions about ambiguous requirements
