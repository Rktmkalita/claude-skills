---
name: claude-md-generator
description: Generate a project CLAUDE.md from real codebase analysis - tech stack and versions, build/test commands, module layout, architecture, coding and testing conventions with reference files, error handling, key flows, configuration and known tech debt. Uses Serena MCP semantic tools when available, otherwise Glob/Grep/Read; uses an existing REPO_MAP.md if present. Trigger on phrases like "generate a CLAUDE.md", "create CLAUDE.md", "write CLAUDE.md for this repo", "update CLAUDE.md", "document project conventions for Claude", or "onboard Claude to this codebase".
---

# CLAUDE.md Generation Skill (Serena-Enhanced, Serena optional)

When asked to generate a CLAUDE.md file for a project, follow this comprehensive workflow for deep codebase analysis. It leverages Serena MCP's semantic code intelligence when available and falls back to built-in tools otherwise.

---

## Tooling

- **If Serena MCP is available**, use `find_symbol` / `get_symbols_overview` / `find_referencing_symbols` / `find_implementations` for analysis and `write_memory` / `read_memory` / `list_memories` for persistence.
- **Otherwise**, use Glob + Grep + Read for analysis, and persist notes to `docs/claude-notes/*.md` with Write (read them back with Read).
- Every `Serena MCP:` block below is paired with a **Fallback (no Serena)** line that gives the built-in equivalent.
- **REPO_MAP.md is optional input.** If it is missing and the user wants one, it can be generated first with `/raktim-skills:repo-map`.

---

## PHASE 0: Prerequisites Check

### Step 1: Check for REPO_MAP.md (optional)

REPO_MAP.md is optional. If it exists, use it as input. If it does not, continue without it, or offer to generate it first with `/raktim-skills:repo-map`.

```bash
ls -la REPO_MAP.md 2>/dev/null || echo "REPO_MAP.md not found"
```

### Step 2: Initialize Serena (if available)

**Preferred (Serena):** Call `mcp__serena__initial_instructions` first to ensure Serena is ready.
**Fallback (no Serena):** Skip initialization; use Glob + Grep + Read throughout.

Then check for existing Serena memories (or notes):

**Preferred (Serena):**
```
Serena MCP: list_memories
```
**Fallback (no Serena):** Glob `docs/claude-notes/*.md` and Read any notes found.

If memories (or notes) exist with names like `architecture`, `conventions`, `patterns`:
- Read them to understand previously discovered patterns
- Use them as baseline, verify they're still accurate

### Decision Matrix

| REPO_MAP.md | Serena Memories / notes | Action |
|-------------|-----------------|--------|
| Exists | Any | Use REPO_MAP + Serena symbolic validation (fallback: Grep/Read spot checks) |
| Missing | Exist | Use Serena memories / notes + refresh with symbolic analysis (fallback: Grep/Read) |
| Missing | Missing | Full Serena-powered analysis (fallback: full Glob/Grep/Read analysis) |

### Step 3: Ask User for Guidance

```
Before generating CLAUDE.md, I have some options:

1. **Quick Generation** - Use existing REPO_MAP.md/memories + spot checks
2. **Deep Analysis** - Full Serena symbolic indexing, or full Glob/Grep/Read scan (more comprehensive but slower)
3. **Hybrid** - REPO_MAP for structure, Serena (or Grep/Read) for pattern extraction

Which approach do you prefer?
```

---

## PHASE 1: Codebase Indexing with Serena (or Glob/Grep/Read)

Use Serena's semantic tools (or the built-in fallbacks) to build a comprehensive understanding of the codebase.

### Step 1.1: Identify Key Directories

Use Glob to find the main source directories, then use Serena (or Grep/Read) for analysis:

```
Glob: **/src/main/java/**/*Controller.java
Glob: **/src/main/java/**/*Service.java
Glob: **/src/main/java/**/*Repository.java
Glob: **/src/test/**/*Test.java
```

### Step 1.2: Symbol Overview of Key Files

For each key file category, use Serena's `get_symbols_overview` (or Read/Grep):

**Preferred (Serena):**
```
Serena MCP: get_symbols_overview
- relative_path: "app/src/main/java/.../SomeController.java"
- depth: 1
```
**Fallback (no Serena):** Read the file, or Grep `-n` for `class |interface |enum |record |public |@` in it to list declarations with line numbers.

This returns:
- All classes, interfaces, enums
- All methods with visibility
- All fields
- Grouped by symbol kind

### Step 1.3: Extract Reference Implementations

Once you identify the "cleanest" files (most methods, best structure), extract full symbol bodies:

**Preferred (Serena):**
```
Serena MCP: find_symbol
- name_path_pattern: "CustomerDetailsService"
- include_body: true
- depth: 1
```
**Fallback (no Serena):** Grep `-n` for `class CustomerDetailsService`, then Read the file (offset/limit around the hit) for the full body.

This gives you:
- Full class structure
- All method implementations
- Annotations used
- Exact line numbers

### Step 1.4: Map Symbol Relationships

For key patterns, trace relationships:

**Preferred (Serena):**
```
Serena MCP: find_referencing_symbols
- name_path: "CustomerDetailsService/getCustomerDetails"
- relative_path: "app/src/main/java/.../CustomerDetailsService.java"
```
**Fallback (no Serena):** Grep `-rn` for `getCustomerDetails(` across the source roots to find callers.

This reveals:
- Which controllers call this service
- How it's injected (constructor vs field)
- Usage patterns across codebase

### Step 1.5: Find Interface Implementations

For architecture patterns like Repository interfaces:

**Preferred (Serena):**
```
Serena MCP: find_implementations
- name_path: "OAuth2AuthorizationService"
- relative_path: "app/src/main/java/.../OAuth2AuthorizationService.java"
- include_info: true
```
**Fallback (no Serena):** Grep `-rn` for `implements .*OAuth2AuthorizationService` across the source roots.

This maps:
- All implementations of an interface
- Where custom implementations exist
- Inheritance hierarchies

---

## PHASE 2: Pattern Extraction

Using Serena's semantic data (or Grep/Read results), extract patterns algorithmically.

### 2.1: Annotation Pattern Detection

**Preferred (Serena):**
```
Serena MCP: find_symbol
- name_path_pattern: "*Service"
- substring_matching: true
- include_body: false
- depth: 0
```
**Fallback (no Serena):** Glob `**/*Service.java`, then Grep `-n` for `^@` in those files to collect class-level annotations.

From results, extract common annotations:
- `@Service`, `@Component`, `@Repository`
- `@RequiredArgsConstructor`, `@Slf4j`
- `@CircuitBreaker`, `@Bulkhead`
- `@Transactional`

### 2.2: Injection Style Detection

Use `find_symbol` on multiple services with `include_body: true`:

Check for:
- `@RequiredArgsConstructor` + final fields = Constructor injection
- `@Autowired` on fields = Field injection
- `@Autowired` on constructor = Explicit constructor injection

### 2.3: Return Type Patterns

From method signatures extracted via `find_symbol`:
- `Optional<T>` returns = Null-safe pattern
- Direct entity returns = Legacy pattern
- `ResponseEntity<T>` = Explicit HTTP responses

### 2.4: Exception Handling Pattern

**Preferred (Serena):**
```
Serena MCP: find_symbol
- name_path_pattern: "*Exception"
- substring_matching: true
```
**Fallback (no Serena):** Glob `**/*Exception.java` to list the custom exceptions.

Then:
**Preferred (Serena):**
```
Serena MCP: find_referencing_symbols
- name_path: "CustomException"
- relative_path: "<path-to-exception>"
```
**Fallback (no Serena):** Grep `-rn` for `new CustomException\|throws CustomException\|CustomException.class` across the source roots.

This reveals:
- Where exceptions are thrown
- How they're caught
- Global handler patterns

### 2.5: Test Pattern Detection

**Preferred (Serena):**
```
Serena MCP: get_symbols_overview
- relative_path: "app/src/test/unit/.../*Test.java"
- depth: 1
```
**Fallback (no Serena):** Grep `-n` for `@Test` (with `-A 1` for the method name) and `@BeforeEach` in the test files.

Extract:
- Test method naming (`should*`, `test*`, `*_when_*`)
- Setup methods (`@BeforeEach` patterns)
- Assertion styles (AssertJ vs JUnit assertions)

---

## PHASE 3: Consistency Validation

Use Serena (or Grep/Read) to verify patterns are followed consistently.

### 3.1: Service Layer Consistency

For each service file:
**Preferred (Serena):**
```
Serena MCP: get_symbols_overview
- relative_path: "<service-file>"
- depth: 1
```
**Fallback (no Serena):** Read the service file, or Grep `-n` for `^@\|class \|public ` in it.

Validate:
- [ ] Has `@Slf4j` annotation
- [ ] Has `@Service` or `@Component`
- [ ] Has `@RequiredArgsConstructor`
- [ ] Methods return `Optional<T>` for nullable results

### 3.2: Controller Layer Consistency

For each controller:
**Preferred (Serena):**
```
Serena MCP: find_symbol
- name_path_pattern: "*Controller"
- include_body: true
```
**Fallback (no Serena):** Glob `**/*Controller.java` and Read each controller.

Validate:
- [ ] Thin controllers (< 10 lines per method typically)
- [ ] Delegates to service layer
- [ ] No business logic in controllers

### 3.3: Repository Layer Consistency

**Preferred (Serena):**
```
Serena MCP: find_symbol
- name_path_pattern: "*Repository"
- include_body: true
- depth: 1
```
**Fallback (no Serena):** Glob `**/*Repository.java` and Read each repository.

Validate:
- [ ] Uses `DynamoDbTemplate` or `JpaRepository`
- [ ] Returns `Optional<Entity>` for single lookups
- [ ] Query building extracted to private methods

### 3.4: Document Inconsistencies

Track files that DON'T follow patterns for "Known Issues" section:
- Missing annotations
- Different injection styles
- Direct null returns instead of Optional
- Mixed naming conventions

---

## PHASE 4: Memory Persistence

Store discovered patterns in Serena memories (fallback: `docs/claude-notes/*.md`) for future reference.

### 4.1: Write Architecture Memory

**Preferred (Serena):**
```
Serena MCP: write_memory
- memory_name: "architecture/layers"
- content: |
    # Architecture Layers

    ## Controller Layer
    - Location: `app/src/main/java/.../controller/`
    - Annotations: @RestController, @RequestMapping
    - Pattern: Thin controllers, delegate to services
    - Reference: `ClientController.java`

    ## Service Layer
    - Location: `app/src/main/java/.../service/`
    - Annotations: @Service, @Slf4j, @RequiredArgsConstructor
    - Pattern: Business logic, @CircuitBreaker for external calls
    - Reference: `CustomerDetailsService.java`

    ## Repository Layer
    - Location: `app/src/main/java/.../repository/`
    - Annotations: @Component, @RequiredArgsConstructor
    - Pattern: DynamoDB operations, return Optional<Entity>
    - Reference: `AuthorizationRepository.java`
```
**Fallback (no Serena):** Write the same content to `docs/claude-notes/architecture-layers.md`.

### 4.2: Write Conventions Memory

**Preferred (Serena):**
```
Serena MCP: write_memory
- memory_name: "conventions/coding"
- content: |
    # Coding Conventions

    ## Injection
    - Style: Constructor injection via @RequiredArgsConstructor
    - Fields: private final
    - Never: @Autowired on fields

    ## Null Handling
    - Return: Optional<T> for nullable results
    - Never: Return raw null from public methods

    ## Logging
    - Annotation: @Slf4j
    - Info: Successful operations
    - Warn: Fallback scenarios
    - Error: Unexpected failures with stack trace

    ## Error Handling
    - Throw: Custom *Exception from services
    - Catch: GlobalExceptionHandler maps to HTTP
    - Never: Try-catch in controllers
```
**Fallback (no Serena):** Write the same content to `docs/claude-notes/conventions-coding.md`.

### 4.3: Write Testing Memory

**Preferred (Serena):**
```
Serena MCP: write_memory
- memory_name: "conventions/testing"
- content: |
    # Testing Conventions

    ## Unit Tests
    - Location: `src/test/unit/`
    - Annotation: @ExtendWith(MockitoExtension.class)
    - Naming: shouldDoSomething or methodName_scenario
    - Structure: // given, // when, // then

    ## Mocking
    - Framework: Mockito with BDDMockito
    - Style: given(...).willReturn(...) not when().thenReturn()
    - Annotation: @Mock for dependencies

    ## Assertions
    - Framework: AssertJ
    - Style: assertThat(result).isPresent().contains(expected)
    - Never: assertEquals, assertTrue (JUnit style)

    ## Component Tests
    - Location: `src/test/functional/`
    - Annotation: @SpringBootTest + @AutoConfigureMockMvc
    - Mocking: @MockitoBean for external services
```
**Fallback (no Serena):** Write the same content to `docs/claude-notes/conventions-testing.md`.

---

## PHASE 5: Generate CLAUDE.md

Using all collected data, generate the CLAUDE.md file.

### Required Sections (Enhanced with Serena Data or Grep/Read results)

#### 1. Project Overview
- One paragraph describing the project purpose
- Key technologies and integrations
- Source: README.md + pom.xml analysis

#### 2. Tech Stack and Versions
Extract from dependency files using Serena symbol analysis where applicable (fallback: Read):
```
Serena MCP: get_symbols_overview on pom.xml (if XML parsing supported)
OR traditional Read for pom.xml
```

Include:
- Language version (Java 21, Python 3.12, etc.)
- Framework version (Spring Boot 3.3.4, FastAPI 0.100, etc.)
- Major libraries with versions
- Build tool version

#### 3. Build and Test Commands
Document all commands with actual working syntax:
```bash
# Setup (if required)
sdk use java 21   # or set JAVA_HOME to the project JDK

# Build
mvn clean install

# Test (all)
mvn clean verify -DrunSlowTests

# Test (single class)
mvn test -pl app -Dtest=ClassName

# Test (single method)
mvn test -pl app -Dtest=ClassName#methodName

# Start locally
docker-compose up -d
mvn spring-boot:run -pl app -Dspring.profiles.active=dev
```

#### 4. Module Structure
From REPO_MAP.md (if present) or Serena / Glob analysis:
- List each module with purpose
- Entry point locations
- Test source layouts
- Configuration file locations

#### 5. Architecture Pattern
**This section is enhanced by Serena's relationship mapping:**

Use `find_referencing_symbols` (fallback: Grep for call sites, then Read) to trace a complete flow:
```
Controller.method()
  └── Service.businessLogic()
        └── Repository.getData()
              └── ExternalClient.call()
```

Document with actual file paths and line numbers from Serena (or Grep `-n`).

#### 6. Coding Conventions
**This section is enhanced by Serena's pattern extraction:**

For each convention, include:
- The rule
- Code example (from `find_symbol` with `include_body: true`, or Read of the reference file)
- Reference file location

Example format:
```java
// Service Layer Pattern
@Slf4j
@Service
@RequiredArgsConstructor
public class CustomerDetailsService {

    private final CustomerDetailsServiceClient client;

    @CircuitBreaker(name = "customerDetails", fallbackMethod = "fallback")
    public Optional<CustomerDetails> getDetails(String id) {
        return Optional.ofNullable(client.getDetails(id));
    }

    public Optional<CustomerDetails> fallback(Exception e) {
        log.warn("Fallback: {}", e.getMessage());
        return Optional.empty();
    }
}
```

Rules:
- Always use `@Slf4j`, `@Service`, `@RequiredArgsConstructor`
- Wrap external calls with `@CircuitBreaker`
- Return `Optional<T>` for nullable results
- Fallback methods return `Optional.empty()` (services)

#### 7. Testing Conventions
**This section is enhanced by Serena's test analysis:**

Extract actual test patterns:
```java
@ExtendWith(MockitoExtension.class)
class CustomerDetailsServiceTest {

    @Mock
    private CustomerDetailsServiceClient client;

    private CustomerDetailsService service;

    @BeforeEach
    void setUp() {
        service = new CustomerDetailsService(client);
    }

    @Test
    void shouldReturnDetailsWhenClientReturnsData() {
        // given
        var expected = CustomerDetails.builder().build();
        given(client.getDetails(ID)).willReturn(expected);

        // when
        var result = service.getDetails(ID);

        // then
        assertThat(result).isPresent().contains(expected);
    }
}
```

Rules:
- Use `@ExtendWith(MockitoExtension.class)`, not `@RunWith`
- Test constants as `private static final`
- BDDMockito: `given(...).willReturn(...)`
- AssertJ: `assertThat(result).isPresent()`
- Structure: `// given`, `// when`, `// then`

#### 8. Error Handling Pattern
Use `find_symbol` and `find_referencing_symbols` (fallback: Glob + Grep) to map:
- Custom exception hierarchy
- Where exceptions are thrown
- GlobalExceptionHandler behavior
- Response formats

#### 9. Key Flows / APIs
**Optional but valuable - extracted from Serena relationship mapping:**

Document 2-3 key flows with:
- Entry point (Controller method)
- Service layer logic
- Repository/External calls
- DTOs involved
- Error scenarios

#### 10. Configuration
- Profiles available (dev, test, prod, etc.)
- Key configuration properties
- Environment variables required
- Secrets management approach

#### 11. Known Issues / Technical Debt
**This section is enhanced by Serena's consistency validation:**

From Phase 3 validation, list:
- Modules that don't follow conventions
- Legacy patterns still in use
- Areas needing refactoring

Format:
```
- **Order module**: Uses field injection instead of constructor injection
- **LegacyService**: Returns null instead of Optional
- **OldController**: Contains business logic (should be in service)
```

---

## PHASE 6: Quality Validation

### Actionability Check

Every line must be actionable. Run this validation:

**Bad (vague):**
- "Follow clean code principles"
- "Write good tests"
- "Handle errors properly"

**Good (specific):**
- "Controllers are thin, delegate to services. No business logic in controllers."
- "Use @MockBean for service dependencies. Test naming: shouldDoSomething"
- "Throw AppException from services. GlobalExceptionHandler maps to HTTP. No try-catch in controllers."

### Completeness Check

Ensure CLAUDE.md contains:
- [ ] Project overview
- [ ] Tech stack with exact versions
- [ ] All build/test commands with working syntax
- [ ] Module structure
- [ ] Architecture pattern with actual code examples
- [ ] Coding conventions with reference files
- [ ] Testing conventions with examples
- [ ] Error handling pattern
- [ ] At least 1 key flow documented
- [ ] Configuration overview
- [ ] Known issues (if any)

### Verification with Serena (or notes)

**Preferred (Serena):**
```
Serena MCP: read_memory
- memory_name: "conventions/coding"
```
**Fallback (no Serena):** Read `docs/claude-notes/conventions-coding.md`.

Verify CLAUDE.md content matches stored patterns.

---

## Execution Workflow Summary

```
1. PREREQUISITES
   ├── Check REPO_MAP.md (optional)
   ├── Initialize Serena (initial_instructions) if available
   ├── List Serena memories (fallback: docs/claude-notes/)
   └── Ask user for approach preference

2. CODEBASE INDEXING
   ├── Glob for key file patterns
   ├── get_symbols_overview for each key file (fallback: Read/Grep)
   ├── find_symbol for reference implementations (fallback: Grep + Read)
   ├── find_referencing_symbols for relationships (fallback: Grep call sites)
   └── find_implementations for interfaces (fallback: Grep "implements")

3. PATTERN EXTRACTION
   ├── Annotation patterns
   ├── Injection style
   ├── Return type patterns
   ├── Exception handling
   └── Test patterns

4. CONSISTENCY VALIDATION
   ├── Service layer validation
   ├── Controller layer validation
   ├── Repository layer validation
   └── Document inconsistencies

5. MEMORY PERSISTENCE
   ├── Write architecture memory (fallback: docs/claude-notes/)
   ├── Write conventions memory (fallback: docs/claude-notes/)
   └── Write testing memory (fallback: docs/claude-notes/)

6. GENERATE CLAUDE.MD
   ├── Write all required sections
   ├── Include code examples from Serena (or Read)
   ├── Reference actual file locations
   └── Document known issues

7. QUALITY VALIDATION
   ├── Actionability check
   ├── Completeness check
   └── Verify against Serena memories (or notes)
```

---

## Serena Tool Reference

| Tool | Purpose in CLAUDE.md Generation | Fallback (no Serena) |
|------|--------------------------------|----------------------|
| `get_symbols_overview` | Quick file structure analysis | Read / Grep declarations |
| `find_symbol` | Extract reference implementations | Grep `-n` + Read with offset/limit |
| `find_referencing_symbols` | Map how components are used | Grep call sites |
| `find_implementations` | Map interface hierarchies | Grep `implements` / `extends` |
| `get_diagnostics_for_file` | Identify code issues | Build/compile output via Bash |
| `write_memory` | Persist discovered patterns | Write `docs/claude-notes/*.md` |
| `read_memory` | Retrieve previous analysis | Read `docs/claude-notes/*.md` |
| `list_memories` | Check for existing knowledge | Glob `docs/claude-notes/*.md` |

---

## Integration with REPO_MAP.md

REPO_MAP.md is optional; generate it with `/raktim-skills:repo-map` if wanted. When REPO_MAP.md exists, use it for:
- **PROJECT STRUCTURE** → Module layout
- **API DOCUMENTATION** → Reference flows
- **SHARED COMPONENTS** → Dependency list

Enhance with Serena (or Grep/Read) for:
- **Symbol bodies** → Actual code examples
- **Relationships** → Cross-file dependencies
- **Consistency** → Pattern validation
- **Persistence** → Memory storage

This hybrid approach provides:
1. Fast generation from REPO_MAP.md
2. Deep accuracy from Serena (or targeted Grep/Read)
3. Future-proofing via Serena memories (or `docs/claude-notes/`)

---

## Example Output Quality

### Before (Generic)

```markdown
## Testing
Write good tests using Mockito.
```

### After (Serena-Enhanced)

```markdown
## Testing Conventions

### Unit Tests

Located in `src/test/unit/`. Use this pattern:

\`\`\`java
@ExtendWith(MockitoExtension.class)
class CustomerDetailsServiceTest {

    private static final String TEST_CUSTOMER_ID = "test-customer";

    @Mock
    private CustomerDetailsServiceClient client;

    private CustomerDetailsService service;

    @BeforeEach
    void setUp() {
        service = new CustomerDetailsService(client);
    }

    @Test
    void shouldReturnCustomerDetailsWhenFound() {
        // given
        var expected = CustomerDetailsResponse.builder().build();
        given(client.getDetails(TEST_CUSTOMER_ID)).willReturn(expected);

        // when
        var result = service.getDetails(TEST_CUSTOMER_ID);

        // then
        assertThat(result).isPresent().contains(expected);
    }
}
\`\`\`

Rules:
- Use `@ExtendWith(MockitoExtension.class)`, not `@RunWith`
- Test constants as `private static final` at class top
- Create subject manually in `@BeforeEach` OR use `@InjectMocks`
- BDDMockito: `given(...).willReturn(...)`
- AssertJ: `assertThat(result).isPresent()`
- Structure: `// given`, `// when`, `// then`
- Naming: `shouldDoSomething` or `methodName_scenario`

Reference: `CustomerDetailsServiceTest.java:15-45`
```
