---
name: repo-map
description: Generate or incrementally update a REPO_MAP.md with the full project structure, shared components, an exhaustive API inventory, and chunked request-flow tracing for each API. Tracks a baseline_commit so later runs only re-document what changed. Works out of the box for Java/Kotlin Spring, JAX-RS and GraphQL; other stacks via the file-glob parameter. Trigger on phrases like "create a repo map", "generate REPO_MAP", "update the repo map", "scan the workspace", "document this codebase", "map all APIs", "trace request flows", or "build an API inventory".
---

# Repo Map Generator

A deterministic static code analysis engine that generates and incrementally maintains a REPO_MAP.md file documenting the complete project structure, shared components, and all APIs with their request flows.

Your role: a deterministic static code analysis engine. Operate ONLY on the real files in the workspace. Never guess, infer, or hallucinate.

## When to Use This Skill

Use this skill when:
- Scanning a Java/Spring/JAX-RS/GraphQL codebase for complete API documentation
- Creating a REPO_MAP.md that doesn't exist
- Updating REPO_MAP.md after code changes (incremental, based on `baseline_commit`)
- Generating exhaustive API inventory with request-flow tracing
- Documenting complex multi-service request flows
- Building project documentation for onboarding or architecture reference

## Parameters

Resolve these once at the start and reuse them in every command below.

**DEFAULT_BRANCH** — never hardcode `main`:
```bash
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
```

**FILE_GLOBS** — the files whose changes affect the map. Pick per stack; the default is the Java/Kotlin set:

| Stack | FILE_GLOBS |
|-------|------------|
| Java / Kotlin (default) | `FILE_GLOBS=('*.java' '*.kt' '*.xml' '*.yml' '*.yaml' '*.properties')` |
| Other | Ask the user, or derive from the build files (source extensions + config extensions) |

The same globs define which source files are scanned in STEP 2.

## Core Workflow

This skill operates as a deterministic state machine following exactly these steps in order. **Do not deviate from this sequence.**

---

## STEP 1: Regeneration Decision

**1.1 Check if REPO_MAP.md exists.**
If REPO_MAP.md does not exist in the workspace root → FULL REGENERATION (STEP 2 onwards).

**1.2 Extract the baseline commit from the existing REPO_MAP.md.**
Read the first 10 lines and extract the `baseline_commit` value:
```bash
grep "baseline_commit:" REPO_MAP.md | head -1 | awk '{print $2}'
```

**1.3 Determine the update mode.**
```bash
# Current default-branch commit
CURRENT_COMMIT=$(git rev-parse "$DEFAULT_BRANCH")

# Baseline commit from REPO_MAP.md (extracted in 1.2)
BASELINE_COMMIT=<extracted value>

# Check if baseline exists and is valid
if [ -z "$BASELINE_COMMIT" ] || ! git cat-file -e "$BASELINE_COMMIT" 2>/dev/null; then
    echo "FULL_REGEN: Invalid or missing baseline commit"
else
    # Files changed since baseline
    CHANGED_FILES=$(git diff --name-only "$BASELINE_COMMIT".."$DEFAULT_BRANCH" -- "${FILE_GLOBS[@]}")

    if [ -z "$CHANGED_FILES" ]; then
        echo "NO_CHANGES: Repo map is up to date"
    else
        echo "INCREMENTAL: $(echo "$CHANGED_FILES" | wc -l) files changed"
    fi
fi
```

**DECISION MATRIX:**

| Condition | Action |
|-----------|--------|
| REPO_MAP.md missing | FULL REGENERATION (STEP 2 onwards) |
| baseline_commit missing/invalid | FULL REGENERATION (STEP 2 onwards) |
| No files changed since baseline | Ask user: "No changes since baseline `<sha>`. Regenerate REPO_MAP.md anyway?" — YES → FULL REGENERATION, NO → exit gracefully |
| Files changed since baseline | INCREMENTAL UPDATE (STEP 1A) |
| User requests full regen | FULL REGENERATION (STEP 2 onwards) |

---

## STEP 1A: Incremental Update Workflow

Use this workflow when REPO_MAP.md exists AND has a valid baseline_commit AND files have changed.

1. **Identify Changed Files:**
   ```bash
   git diff --name-only "$BASELINE_COMMIT".."$DEFAULT_BRANCH" -- "${FILE_GLOBS[@]}"
   ```

2. **Categorize Changes:**
   - Controller files changed → Re-document affected APIs
   - Service/Repository files changed → Update flows that reference them
   - DTO files changed → Update DTO documentation in affected APIs
   - Config files changed → Update SHARED COMPONENTS if needed

3. **Identify Affected APIs:**
   For each changed controller file:
   - Extract all mapping-annotated methods (see STEP 2, Pass 3)
   - These APIs need re-documentation

   For each changed service/repository:
   - Search REPO_MAP.md for APIs that reference this class
   - These APIs need flow re-documentation

4. **Update Process:**
   - Read the existing REPO_MAP.md
   - For each affected API, re-document it with fresh analysis (STEP 4 rules) and replace its old section in place with the Edit tool
   - Update SHARED COMPONENTS with the Edit tool if needed
   - Update `baseline_commit` to `CURRENT_COMMIT` (`git rev-parse "$DEFAULT_BRANCH"`), `generated_at` and `total_apis` in the METADATA HEADER with the Edit tool

5. **Output:**
   ```
   INCREMENTAL UPDATE COMPLETE:
   - Baseline: <old_commit> → <new_commit>
   - Files changed: X
   - APIs updated: Y
   - APIs unchanged: Z
   ```

**WHEN TO FALL BACK TO FULL REGEN:**
- More than 50% of APIs affected
- Core shared components changed (affects most APIs)
- Package structure changed
- User explicitly requests full regen

---

## STEP 2: Complete API Discovery (Mandatory Multi-Pass Scan)

**NEVER START DOCUMENTATION UNTIL ALL APIs ARE DISCOVERED.**

**Output tracking:** As you work, maintain a discovery log showing:
```
API DISCOVERY IN PROGRESS:
- Pass 1: Scanning for controller files...
- Pass 2: Reading controller file contents...
- Pass 3: Extracting method signatures...
- Pass 4: Identifying mapping annotations...
```

### Pass 1: Find All Controller Files
Search the workspace recursively (every source file matching FILE_GLOBS) for files containing ANY of:
- `@RestController`
- `@Controller`
- `@RequestMapping` (at class level)
- JAX-RS `@Path` (at class level)
- Any Spring/JAX-RS controller annotations

**Output:** List all controller files found with paths

### Pass 2: Open and Read Each Controller File
For EACH controller file identified in Pass 1:
- Open the complete file
- Read all content
- Do NOT skip any file

### Pass 3: Extract All Methods with Mapping Annotations
From each controller file, extract ALL methods with:
- `@GetMapping`, `@PostMapping`, `@PutMapping`, `@DeleteMapping`, `@PatchMapping`
- `@RequestMapping` (with or without method specification)
- JAX-RS: `@GET`, `@POST`, `@PUT`, `@DELETE`, `@PATCH`, `@Path`
- GraphQL: `@QueryMapping`, `@MutationMapping`, `@SchemaMapping`
- Any custom routing annotations

For each method, capture:
- Full method signature (including annotations)
- File path and line number
- HTTP method and path (combining class-level + method-level mappings)

Rules:
- Do NOT assume similar endpoints — each must be documented
- Do NOT skip versioned endpoints (v1, v2, v3, v4)
- Do NOT skip similar-looking methods

### Pass 4: Build Complete API Inventory

**Output API Discovery Results:**
```
API DISCOVERY COMPLETE:
- Total Controller Files: [X]
- Total API Endpoints Found: [Y]
- Controller Files Scanned: [list all paths]
- APIs by Controller: [count per file]
- Complete API List:
  * [HTTP_METHOD] [FULL_PATH] (File: ..., Line: ...)
  * [HTTP_METHOD] [FULL_PATH] (File: ..., Line: ...)
  * ... (all APIs)
```

### Pass 5: Verification
- **COUNT CHECK:** If the API count looks low relative to the controller files found (e.g. a controller with no extracted endpoints, or far fewer endpoints than mapping annotations in the file), output `"Low API count detected. Rescanning..."` and repeat Pass 1-4
- **Versioning CHECK:** Verify all versioned endpoints included (v1/v2/v3/v4 if present)
- **HTTP Methods CHECK:** Verify all HTTP methods represented (GET/POST/PUT/DELETE/PATCH if used)

**CRITICAL:** Do NOT proceed to STEP 3 until all APIs are discovered and verified.

---

## STEP 3: Write Metadata, Project Structure & Shared Components

The sections of REPO_MAP.md are always written in this canonical order:

1. METADATA HEADER
2. PROJECT STRUCTURE
3. SHARED COMPONENTS
4. APIs (one section per API)

### Section 3A: METADATA HEADER (MANDATORY)
The FIRST content in REPO_MAP.md must be the metadata block:

```markdown
---
baseline_commit: <full 40-char SHA from `git rev-parse "$DEFAULT_BRANCH"`>
generated_at: <ISO 8601 timestamp>
default_branch: <DEFAULT_BRANCH>
total_apis: <count>
last_updated_by: claude-code
---
```

**Example:**
```markdown
---
baseline_commit: 04af7fdd8abc123def456789abcdef1234567890
generated_at: 2025-05-25T10:30:00Z
default_branch: main
total_apis: 47
last_updated_by: claude-code
---
```

This metadata enables:
- Incremental updates (compare against baseline_commit)
- Staleness detection (compare generated_at with last commit date)
- API count verification

**ACTION:** Write REPO_MAP.md (create new file, overwrite if exists) with the Write tool
- Confirm: "METADATA HEADER written to REPO_MAP.md"

### Section 3B: PROJECT STRUCTURE
Generate complete directory tree of the workspace:
- Full directory structure
- Use absolute paths
- Include ALL files
- Organize hierarchically

**ACTION:** Append to REPO_MAP.md with the Edit tool
- Confirm: "PROJECT STRUCTURE appended to REPO_MAP.md"

### Section 3C: SHARED COMPONENTS
Scan workspace for and list:
- All service classes (`*Service`, `*Manager`)
- All repository classes (`*Repository`, `*Dao`)
- All utility classes (`*Util`, `*Helper`)
- All model/DTO classes
- All configuration classes
- All interceptors/filters

For each component, include:
- Full class name
- File path
- Brief purpose (if obvious from name/annotations)

**ACTION:** Append to REPO_MAP.md with the Edit tool
- Confirm: "SHARED COMPONENTS appended to REPO_MAP.md"

---

## STEP 4: Document All APIs (Automatic Continuation)

**State tracking:** Maintain progress counter: "API [X of Y]: [METHOD] [PATH]"

For EACH API in the inventory (in discovery order):

### Per-API Documentation Structure

API heading format: `## [HTTP_METHOD] [PATH]`

For API [X of Y], document:

#### 1. Entry Point
- File path and line number
- Full controller method signature with all annotations
- HTTP method and path

#### 2. Request Flow (Chunked Recursive Tracing)
Follow the **Chunked Flow Tracing Engine** below. Document each step with file + line references.

#### 3. DTO Documentation
- Input/request DTO (if applicable)
- Output/response DTO
- Field mappings

#### 4. Dependencies
- Services called
- Repositories accessed
- External clients used

#### 5. Database Operations
- Query types (SELECT, INSERT, UPDATE, DELETE)
- Tables affected
- Transaction scope

#### 6. External Calls
- HTTP calls to other services
- RPC/gRPC calls
- Third-party integrations

#### 7. Error Handling
- Exception types caught
- Error responses returned
- Fallback logic

#### 8. Success and Failure Paths
- Happy path flow
- All failure scenarios documented

### After Documenting Each API
**ACTION:** Append to REPO_MAP.md with the Edit tool
- Confirm: "API [X of Y]: [METHOD] [PATH] appended to REPO_MAP.md"
- Automatically proceed to the next API (see "Continuation Policy" below)

### Error Recovery
- If documentation of one API fails: Log error with API details
- Continue immediately to next API
- After all APIs processed, list any failed APIs and offer retry

---

## Chunked Recursive Call Flow Tracing Engine

For each API, trace the complete request flow through all downstream classes.

### Tracing Rules

**RULE A:** Process maximum 3 downstream classes per chunk
**RULE B:** After 3 classes, write the current chunk's results
**RULE C:** Then continue automatically with the next chunk (see "Continuation Policy")
**RULE D:** Stop only when no further calls exist for current API

### Continuation Policy

Chunks keep each step small; they are not a reason to stop. After each chunk (and after each API), continue automatically with the next chunk or API **unless the context budget is running low**. Only in that case:
1. Write everything documented so far to REPO_MAP.md
2. Output "Continue this API flow" together with the "Next Classes to Process" list
3. Wait for the user's "Continue", then resume exactly where the previous chunk ended

### Recursive Class Loading Process

For each downstream class identified:

1. **Open the file** for that class
2. **Locate the method** using full-text search
3. **Extract:**
   - Exact method signature
   - File path and line numbers
   - ALL direct method calls inside the method body
4. **Treat each direct method call** as a new downstream step
5. **Include in output** for next chunk

### Chunk Output Format

```
### Request Flow - Chunk [N]

**Processing Classes:** [Class 1], [Class 2], [Class 3]

**Class 1: [ClassName]**
- Method: [methodName] (File: path/to/File.java, Line: XX)
- Method Signature: [full signature]
- Calls: [method1], [method2], [method3]
- Details: [what this method does]

**Class 2: [ClassName]**
- Method: [methodName] (File: path/to/File.java, Line: XX)
- Method Signature: [full signature]
- Calls: [method1], [method2], [method3]
- Details: [what this method does]

**Class 3: [ClassName]**
- Method: [methodName] (File: path/to/File.java, Line: XX)
- Method Signature: [full signature]
- Calls: [method1], [method2], [method3]
- Details: [what this method does]

**Next Classes to Process:** [Class A], [Class B], [Class C], [Class D]...

**Status:**
- If more calls exist: next chunk follows (or "Continue this API flow" if the context budget is low)
- If complete: "Request flow complete for this API"
```

### Continuation Handling

When resuming after "Continue this API flow":
1. Preserve all context from previous chunk
2. Load previous chunk's "Next Classes to Process" list
3. Resume exactly where you left off
4. Process next 3 classes
5. Repeat until all reachable logic is exhausted

### Continuation Recursion Depth

Never stop recursion after scanning a controller. Continue through:
1. Service classes
2. Manager classes
3. Helper classes
4. Utility classes
5. Repository classes
6. Client classes

Until all reachable logic for current API is exhausted.

---

## STEP 5: Verification & Completion

After documenting all APIs:

**Verification Checklist:**
- [ ] Total APIs documented matches discovery count
- [ ] `total_apis` in the METADATA HEADER matches the documented count
- [ ] All controller files represented
- [ ] All HTTP methods included
- [ ] All versioned endpoints included
- [ ] No APIs skipped

**Output completion message:**
```
ALL APIS DOCUMENTED:
- Total APIs: [Y]
- All [Y] APIs written to REPO_MAP.md
- Baseline commit: [sha]
- File location: [path to REPO_MAP.md]
```

If mismatch found:
- Output: "WARNING: Expected Y APIs, documented X APIs"
- List undocumented APIs
- Offer to continue with remaining APIs

---

## File Writing Rules (Mandatory)

**CRITICAL:** All output must be written to REPO_MAP.md, not just printed to console.

### File Operations

One method only:
- **Write tool** — creates/overwrites REPO_MAP.md with the METADATA HEADER (STEP 3A). Used once per full regeneration.
- **Edit tool** — every later change: appending PROJECT STRUCTURE, SHARED COMPONENTS and each API section (append after the current last line), and, during incremental updates, replacing individual API sections and metadata fields in place.

Do NOT write REPO_MAP.md with shell commands (`cat`, `echo`, `tee`, heredocs).

After each write, confirm in conversation.

---

## Output Confirmation Messages

Throughout execution, output these confirmations:

- "METADATA HEADER written to REPO_MAP.md"
- "PROJECT STRUCTURE appended to REPO_MAP.md"
- "SHARED COMPONENTS appended to REPO_MAP.md"
- "API [X of Y]: [METHOD] [PATH] appended to REPO_MAP.md"
- "All [N] APIs written to REPO_MAP.md"

---

## Verification-First Rule

Always search files before answering.
- Positive match → return exact file + line.
- Negative match → list searched files + confirm absence.

---

## Framework Support

This skill supports:
- **Spring Framework:** @GetMapping, @PostMapping, @RequestMapping, etc.
- **JAX-RS:** @GET, @POST, @PUT, @DELETE, @PATCH, @Path
- **GraphQL:** @QueryMapping, @MutationMapping, @SchemaMapping
- **Custom annotations:** Any routing annotations detected in workspace

---

## Important Notes

- **Deterministic:** This skill operates based only on real files in workspace. Never guess, infer, or hallucinate.
- **Exhaustive:** Every source file matching FILE_GLOBS is scanned. No files skipped.
- **Incremental:** REPO_MAP.md builds section by section, and later runs only re-document what changed since `baseline_commit`.
- **Resilient:** Errors in one API don't stop the entire process.
- **Traceable:** Complete request flows traced through all downstream classes.
