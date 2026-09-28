---
name: springboot-upgrade
description: >
  Structured, checkpoint-driven Spring Boot + Java upgrade workflow for Maven
  multi-module Java/Kotlin/Spring services. Activate when the user asks to
  upgrade/migrate Spring Boot (e.g. 2.x→3.x, 3.x→4.x) and/or the Java version.
  Takes current + target versions as input (with analysis-based suggestions),
  discovers per-deployment runtime constraints FIRST, researches breaking
  changes, then executes stop-and-wait checkpoints across every module and every
  deployment target (e.g. Nomad, on-prem servers, AWS), including CI pipeline
  YAML and per-environment properties files.
---

# Spring Boot / Java Upgrade Skill

A deterministic, checkpoint-driven upgrade workflow. It exists to prevent the
single most expensive mistake in these migrations: **picking a Java/Boot target
before knowing what each deployment environment can actually run.** Establish the
runtime constraints first; everything else follows.

Follow the numbered phases in order. Announce each phase and each checkpoint.
STOP and get user approval at every checkpoint boundary (guided-implementation style).
Never guess versions or runtime facts — verify against the repo, the running
instances, and official migration guides.

---

## CORE PRINCIPLES (read first — these are hard-won)

1. **Runtime-first, not build-first.** For EVERY deployment target, determine the
   actual **JRE version** and **servlet-container version** the app runs on BEFORE
   choosing the Java/Boot target. Skipping this causes repeated flip-flops.
2. **The Java target is a floor problem.** The chosen Java version must
   simultaneously satisfy: (a) the target Boot baseline, (b) the LOWEST JRE across
   all in-scope deployment targets, and (c) any dependency shipped as Java-N
   bytecode (an internal lib compiled for Java 21 forces Java 21 minimum). Pick the
   lowest version that satisfies all — bytecode of a lower Java runs on higher JREs,
   never the reverse.
3. **Servlet spec gates the container.** Boot version → Servlet spec → minimum
   container. If a deployment target's container can't meet it, that target is
   **out of scope** until the platform is upgraded (say so explicitly; don't try to
   force it). Reference: Boot 3.x = Servlet 6.0 = Tomcat 10.1; Boot 4.x = Servlet
   6.1 = Tomcat 11; `javax.*`→`jakarta.*` at the Boot 2→3 boundary.
4. **Verify with facts, not assumptions.** Use `ps aux | grep java` on the running
   instance, the Tomcat `VersionLoggerListener` startup lines, and the compiled
   class-file major version (`od -An -tu1 -j6 -N2 X.class` → major−44 = Java
   version) to confirm reality.
5. **Every module is its own problem.** Enumerate all Maven modules and check each
   for version-pinned deps, its own starters, test frameworks, and deployment role.
6. **One checkpoint at a time.** Make the change, show `git diff`, verify, STOP.
   Never batch checkpoints. If a test fails, diagnose the root cause before moving.
7. **Env-config must match the build.** Per-environment descriptors that pin the
   JVM (e.g. a per-environment properties file that selects the host JDK) MUST be
   updated to the build's Java target, or the deployed JVM won't match the bytecode.
8. **Keep a living plan/progress file.** Create ONE plan `.md` in the repo at the
   very start (Phase 2) and UPDATE it after every checkpoint and every decision —
   it is the single source of truth that survives context resets. Never track
   progress only in your head or in chat. Details in the "PLAN / PROGRESS FILE"
   section below.

Also honor the repo's own conventions (e.g. whether you may commit, the
commit-message format, no explanatory comments in code/config).

---

## PHASE 0 — Inputs & Version Analysis

### 0.1 Analyze the repo first (facts before asking)
- Detect current versions: root `pom.xml` `<spring-boot.version>`, `<java.version>`,
  `<kotlin.version>`, kotlin `<jvmTarget>`, parent POM/BOM, and every explicitly
  versioned dependency NOT managed by the Boot BOM.
- Enumerate all modules (`<module>` list) and their roles (war/app, local-runner,
  acceptance-test, api-tests, resource, etc.).
- **Enumerate every deployment target and its runtime image.** For each target,
  record: the deployment descriptor(s), the CI job/pipeline file that builds and
  ships it, the base image or host runtime (JRE + container), and any
  per-environment config that pins the JVM. Examples of what to look for:
  - Container scheduler (e.g. Nomad): job specs and variable files (`*.nomad`,
    `*.vars`), the CI pipeline file for that target, Jib/Docker image config.
  - On-prem / VM / external servlet container: the CI pipeline file for that
    target, per-environment JVM descriptors, external-Tomcat config
    (`catalina.properties`), any deploy-script variables.
  - AWS: `Dockerfile`, `buildspec.yml`, `appspec.yml`, ECS task defs, CDK/Terraform,
    AWS stages in the CI pipeline.
- Detect the CI build image pattern (e.g. an image name or tag that encodes the
  Java version) and any `JDK_VERSION`-style variable.

### 0.2 Ask the user (AskUserQuestion) — with YOUR analysis-based suggestions
Present a recommended value as the first option for each, derived from 0.1 + web
research (0.3 below). Ask:
1. **Target Spring Boot version** — suggest the latest GA of the requested line, and
   note EOL (e.g. Boot 4.0.x EOL 2026-12-31 → suggest planning a minor bump). If
   they said "latest", still name the exact patch.
2. **Java target** — suggest the version from the floor analysis (Principle 2). If a
   dependency or a deployment JRE constrains it, say so.
3. **Deployment scope** — which of the targets found in 0.1 are in scope (one, some,
   or all). This drives Phase 4's packaging + CI + env-file changes.
4. **Jackson / other majors** (only if the target bumps them, e.g. Boot 4 → Jackson 3)
   — offer compat-module-first (lower risk) vs full migration.

### 0.3 Version compatibility research (do BEFORE finalizing suggestions)
Use web search / official sources. Confirm, for the target Boot:
- Boot GA + patch, its **Spring Framework**, **Spring Security**, **Tomcat**, **Jackson**
  versions, **Java baseline + max**, and **minimum Kotlin** version.
- Read the official migration guide (e.g. Spring Boot `<X>.0` Migration Guide wiki)
  for: module restructuring, starter renames, auto-config package moves, dropped
  modules, dependency-management removals.
- For each explicitly-versioned dep in the repo, find the version compatible with the
  target Boot/Framework (springdoc, mockito-kotlin, spring-retry, etc.).
- **For internal / organisation libraries** that may lack a build for the target:
  apply the "INTERNAL LIBRARIES WITHOUT A JAKARTA / BOOT-N BUILD" decision framework
  below, and present its recommendation per library rather than an open question.

Record all of this as a short table (like the migration plan's "Dependency Change
Table").

---

## PHASE 1 — Runtime Constraint Discovery (CRITICAL — do not skip)

For EACH in-scope deployment target found in 0.1, establish the hard runtime facts.
Ask the user to run these on the actual instances if you can't see them. Examples:

- **Container scheduler (e.g. Nomad) / any container:** the base image and its JRE;
  Tomcat version. (Check the Jib `<from>` / `Dockerfile` `FROM` image, and the
  container startup log's `VersionLoggerListener` / JVM line.)
- **On-prem / VM:** `ps aux | grep java` on a deployed host → the real
  `.../jdkXX/bin/java` path (JRE version) and `-Djava.library.path=...tomcatN-native...`
  (Tomcat version). Also any per-environment JVM descriptor (JDK version, GC
  profile) — these SELECT the host JVM.
- **AWS:** the base image / runtime in the `Dockerfile` / ECS task def / buildspec →
  JRE version; whether it's embedded server (Boot fat-jar/exec) or a container.

Then decide, and state explicitly:
- **Java target** = lowest version satisfying Boot baseline + all in-scope JREs +
  any Java-N-bytecode dependency.
- **Servlet/container** = the min container for the target Boot; flag any target that
  can't meet it as **out of scope** (with the platform upgrade needed).

If constraints conflict (e.g. one target on an old container/JRE), surface the
trade-off to the user and let them choose scope (e.g. "container target only for
now, on-prem after the platform upgrades Tomcat/JRE").

---

## PHASE 2 — Create the Plan / Progress File (pre-flight report)

**Create the plan `.md` now, at the start** — e.g. `SPRING_BOOT_<X>_MIGRATION_PLAN.md`
in the repo root (link any predecessor plan). This file is the **living source of
truth** — you will update it after every checkpoint (Phase 4) and at closeout
(Phase 5). Do not defer creating it. Initial sections:

- **Header** — from/to versions (Boot, Java, Kotlin), deployment scope, branch, date.
- **▶ PROGRESS** — a status line + a **checkpoint table** (`CP | Status | Notes`) with
  every checkpoint listed as ☐ pending; this is what you tick off as you go.
- **Decisions** — the version/scope choices with their rationale (so a context reset
  doesn't lose *why*).
- **Pre-flight findings:**
  - **Hard requirements / version interactions** (Kotlin min, compiler-plugin min for
    the new Java, etc.).
  - **Code changes** (javax→jakarta if 2→3; auto-config exclude package moves;
    security/LDAP/retry API surface to verify; any deprecated-API usage).
  - **Build/dependency changes** (starter renames, compat modules like
    `spring-boot-jackson2`, deps whose management the BOM dropped → explicit version).
  - **Internal-library decisions** (one row per library, from the decision framework).
  - **Per-deployment changes** (Phase 4 preview): CI YAML, base image, env files.
- **Runtime constraints** (from Phase 1): JRE + container per target; out-of-scope calls.
- **Open blockers** (e.g. platform must provide a newer container/JRE).
- **Sources** — cite official migration guides / advisories.

See the "PLAN / PROGRESS FILE" section for the update discipline.

---

## PHASE 3 — Module Inventory

For each module, list what must change:
- Version-pinned deps → bump or remove (if now BOM-managed).
- Its own starters / test frameworks (JUnit, mockito-kotlin, test-container helpers).
- Deployment role (does it produce the deployable? is it test-only / live-env?).
- Whether it's built in the main reactor or run separately (e.g. api-tests as
  post-deployment). Note excluded modules explicitly so they're not forgotten.

---

## INTERNAL LIBRARIES WITHOUT A JAKARTA / BOOT-N BUILD — decision framework

Organisation-internal libraries (shared starters, logging/metrics/tracing glue,
security config, parent POMs/BOMs) are the most common blocker: they are often
compiled against an old Spring/`javax` baseline with no build for the target. Do not
stop and ask an open question per library — work through this framework, present a
recommendation, and record the decision + rationale in the plan file.

### Step 1 — Is there a compatible build?
Search the artifact repository (including groupId/artifactId variants) for a release
built for the target (jakarta, Spring Framework 6/7, Boot 3/4). If one exists **and
has adopters**, bump to it. Done.

### Step 2 — Classify the library
- **Cross-cutting** (logging, metrics, tracing, context propagation, monitoring):
  its job can usually be done by stock Boot + standard observability.
- **Functional** (shared security config, domain clients, a parent POM/BOM that
  pins versions): the app depends on its behaviour.

### Step 3 — Choose one option

| Option | When it fits | Notes |
|---|---|---|
| **Replace with an OSS / stock-Boot equivalent** | Cross-cutting libs | Default for cross-cutting. E.g. Micrometer + actuator Prometheus endpoint for metrics; the OpenTelemetry Java agent (or `micrometer-tracing-bridge-otel` + an OTLP exporter) for tracing; Boot-native logback (`logback-spring.xml`) for logging glue. Preserve any endpoint the lib exposed (e.g. a build-version endpoint) with a tiny local controller reading the manifest `Implementation-Version`. |
| **Inline the needed code** | Functional libs where the app uses a small, stable slice (e.g. a shared `SecurityConfiguration`) | Copy only what is used into the app, migrate it to the new APIs, cover it with tests. Record the provenance in the plan file. |
| **Stop inheriting / override** | A parent POM or BOM that pins old Spring/`javax` versions | Import the Spring Boot BOM (or a newer organisation BOM) and manage versions explicitly, or override the pinned properties. |
| **Fork-and-migrate** | The lib is large, used widely, and worth keeping | Migrate the lib itself to jakarta / the new Spring major and publish a new major version; the app upgrade then waits on (or bundles) that work. Surface the cost to the user. |
| **Shade / relocate** | Last resort, for a lib whose `javax`-bound internals are not on the app's API surface | Only viable if the lib doesn't need to integrate with the new Spring context; it adds maintenance cost and hides the problem. |

### Step 4 — Escalate only genuine blockers
Escalate to the user only when a **functional** library has no compatible build and
cannot reasonably be inlined, overridden, or replaced — that is a genuine blocker.
Record it in the plan file's "Open blockers".

### Public-library facts to check while applying the framework
- A metrics registry that pushes to Kafka and was compiled against Spring Kafka 2.x
  fails with `NoSuchMethodError` on Spring Kafka 3.x → replace with the actuator
  Prometheus endpoint (`management.endpoints.web.exposure.include: prometheus`) +
  an OpenTelemetry agent, and remove its `management.metrics.export.*` config.
- `opentracing-*` / Jaeger client starters → replace with the OpenTelemetry Java
  agent (or `micrometer-tracing-bridge-otel` + OTLP exporter for in-process).
- `logback-ext-spring` / `log4j` 1.x stubs → drop; use Boot-native logback
  (`logback-spring.xml`); add `jcl-over-slf4j` (Framework 7 drops `spring-jcl`).

---

## PHASE 4 — Checkpoint Implementation (stop-and-wait; show `git diff` each)

> Maven setup before any command: select the target JDK (however the environment
> switches JDKs, e.g. SDKMAN or `JAVA_HOME`), then `mvn -version` to confirm. Use the
> repo's build tooling; never `./mvnw` if the repo forbids it. Re-select the JDK in
> each shell if shell state doesn't persist.

Adapt the exact set to the jump (2→3 adds the javax→jakarta sweep; 3→4 adds module
restructuring). Typical checkpoints:

- **CP1 — Versions & property cleanup (root pom):** Boot, Java, Kotlin, `jvmTarget`,
  `maven-compiler-plugin` (must support the new `--release`; add `<proc>full</proc>`
  for JDK 23+ so classpath annotation processors like Lombok still run), remove
  now-BOM-managed overrides, add explicit versions for deps the BOM dropped
  (e.g. spring-retry). Verify with `dependency:tree` (Framework/Security/Tomcat/etc.
  resolve to expected majors). No compile expected yet if jakarta/imports pending.
- **CP2 — Auto-config / package relocations:** repoint moved classes
  (`@SpringBootApplication(exclude=...)` FQNs, embedded-server factory packages,
  etc.). Verify exact new packages from the target version's javadoc/jars.
- **CP3 — Starters, compat modules, jakarta sweep, internal-library decisions:**
  starter renames (e.g. `starter-web`→`starter-webmvc`, `starter-tomcat`→`-tomcat-runtime`
  for WAR), add compat modules (Jackson-2 module), javax→jakarta imports (2→3), and
  **apply the internal-library decisions** recorded in the plan file (replace,
  inline, override, fork, or shade per library; add a local version endpoint if a
  dropped lib provided one). Compile the app modules.
- **CP4 — Verify unchanged subsystems:** confirm security/LDAP/retry/etc. compile
  against the new majors; fix only where an API genuinely moved.
- **CP5 — Test migration:** Kotlin compiler jump (K2), test-framework API changes
  (JUnit `ArgumentsProvider` signatures, moved test classes like `TestRestTemplate`
  and its opt-in `@AutoConfigure...`), missing runtime bridges (e.g. `jcl-over-slf4j`
  when Framework drops `spring-jcl`). Run unit + integration tests green.
- **CP6 — Full regression:** `mvn clean install` across all app + acceptance modules
  (note separately-run modules like api-tests). All tests green.
- **CP7 — Packaging / image / CI / env — PER DEPLOYMENT (see matrix below).**
- **CP8 — Security rescan + closeout:** run the vuln scan (e.g. Snyk) on the new
  tree; prefer real removal/upgrade over suppression (e.g. delete an orphaned
  `log4j:log4j:99-empty` stub if nothing pulls it transitively rather than adding an
  ignore-rule); update CSV/plan/CLAUDE.md; mark deployment scope.

At each CP: show `git diff --ignore-cr-at-eol <files>` (to cut line-ending noise),
confirm the build/test result, **update the plan file's PROGRESS table (mark the CP
done + one-line result) and log any deviation or newly-discovered fix**, then STOP.

---

## PLAN / PROGRESS FILE — update discipline

The plan `.md` created in Phase 2 is a **living document**, not write-once. Keep it
current so the work survives a context reset or handoff:
- **After each checkpoint:** flip that CP's row to ☑ DONE with a one-line result
  (versions resolved, tests green, files touched), and update the top status line to
  the next CP.
- **Whenever you discover something not in the original plan** (a moved package, a
  missing runtime bridge, a Java-N-bytecode dep, a platform blocker): add it to an
  "Additional fixes discovered" / "Open blockers" list with the cause and the file
  touched. These are the highest-value notes for the next person.
- **On every decision or reversal** (Java target change, scope narrowing to a
  single deployment target, etc.): record the decision AND the rationale — future
  readers need the *why*, not just the *what*.
- **At closeout (Phase 5):** final status, deployment scope, security outcome, and
  any follow-ups; also reflect the stack change in `CLAUDE.md`.
- Update via edits to the existing file — one plan file per upgrade; never scatter
  progress across chat only or spin up duplicate docs.

---

## DEPLOYMENT MATRIX (CP7 — what changes per target)

For EVERY in-scope target enumerated in 0.1, update each of these, then verify the
target's runtime image matches the build:

1. **CI build job** — the build image / `JDK_VERSION`-style variable → target Java.
   If no build image for the target Java exists, that's a **platform blocker** — flag it.
2. **Runtime image or host JVM** — the base image (Jib `<from>`, `Dockerfile` `FROM`)
   or host-provisioned JDK → a runtime whose **JRE matches the target Java** (and whose
   servlet container matches the target Servlet spec, if WAR-on-external-container).
3. **Deployment descriptors** — job specs, task definitions, IaC: health-check path,
   `JAVA_OPTS`, agent flags, any runtime/JDK/env references.
4. **Per-environment config** — any file that pins the JVM per environment (JDK
   version, GC profile) → the exact provisioned JDK for the target Java (ASK for the
   exact string — don't guess a patch that may not be installed).
5. **Container config** — validate external `catalina.properties`/`conf` against the
   new Tomcat major.

Examples by target type:

### Container scheduler (e.g. Nomad)
- Pipeline file for this target: JDK variable → target Java.
- Jib `<from>` base image → matching JRE (and Tomcat, if WAR-on-Tomcat). Keep
  extraDirectories/appRoot/ownership/agent wiring.
- Job spec and variable files: health-check path, any JAVA_OPTS/agent flags.

### On-prem / VM with an external servlet container
- Pipeline file for this target: build image → target Java.
- Per-environment JVM descriptors (TEST/UAT/LIVE etc.): JDK version → the exact
  provisioned patch; GC profile → the matching profile for the new major.
- Confirm the host **container** meets the Servlet spec (external Tomcat major) and
  the host has the target **JRE** provisioned. If not → out of scope until platform
  upgrade.
- `SpringBootServletInitializer`/WAR packaging stays for external Tomcat.

### AWS
- `Dockerfile` / base image → JRE matching target Java (and server if applicable).
- `buildspec.yml` / CI AWS stage → build JDK.
- ECS task def / CDK / Terraform → any runtime/JDK/env references.
- If deployed as an exec-JAR/container (embedded server), the Servlet-container
  constraint is satisfied by the Boot-managed embedded Tomcat — just ensure the JRE
  matches.

### Multiple targets
- Do every matching section. The Java target must satisfy the **lowest** JRE across
  all targets (Principle 2). If targets disagree irreconcilably, split scope with the
  user.

---

## PHASE 5 — Verification & Closeout

- Re-run the full build on the target JDK; confirm the compiled class-file major
  matches the target Java (`od` check) so it will load on the deployment JRE.
- Security scan clean (map each finding: fixed-by-version vs needs-other-change like
  a false-positive removal).
- Update the plan `.md` (status per checkpoint, decisions, deployment scope, any
  platform blockers), CLAUDE.md tech-stack table, and any version CSV.
- Provide a plain, branch-prefixed commit message (per repo convention). Offer
  per-checkpoint commit messages if the user prefers granular commits.

---

## GOTCHAS CHECKLIST (verify each; these bit us on a real 3.5→4.0 upgrade)

- [ ] JDK 23+ silently disables classpath annotation processing → Lombok stops →
      add `<proc>full</proc>` (or `annotationProcessorPaths`).
- [ ] Framework 7 removed `spring-jcl` → `org.apache.commons.logging.LogFactory`
      absent → add `org.slf4j:jcl-over-slf4j`.
- [ ] Boot 4 split the default servlet `SecurityFilterChain` out of
      `SecurityAutoConfiguration` → also exclude `ServletWebSecurityAutoConfiguration`
      if the app runs with no security filter.
- [ ] `TestRestTemplate` moved to `org.springframework.boot.resttestclient` and is
      opt-in via `@AutoConfigureTestRestTemplate`; needs `spring-boot-restclient` +
      `spring-boot-resttestclient`.
- [ ] Embedded Tomcat factory classes moved to `org.springframework.boot.tomcat(.servlet)`.
- [ ] JUnit 5.13+ `ArgumentsProvider.provideArguments(ParameterDeclarations, ExtensionContext)`.
- [ ] Kotlin K2 (2.x) rejects reifying intersection types → `arrayOf<Any>(...)`.
- [ ] spring-retry dependency-management dropped in Boot 4 → pin an explicit version.
- [ ] A transitive/org dependency compiled for a newer Java forces the whole app's
      Java floor up (verify with the `UnsupportedClassVersionError` class number).
- [ ] `dependency:analyze` needs a modern plugin (`maven-dependency-plugin:3.x`); the
      2.10 pinned by old corporate parents fails on new bytecode. Its "unused declared"
      list is mostly false positives (starters, runtime-only deps).
- [ ] CRLF working trees: use `git diff --ignore-cr-at-eol`; don't commit CRLF churn.
      For whole-file LF↔CRLF reencoding `--ignore-cr-at-eol` under-reports — use
      `git diff --ignore-all-space` as the source of truth for "is this diff real?".
- [ ] api-tests / post-deployment modules often aren't in the main reactor — build
      them separately and don't assume they were covered.
