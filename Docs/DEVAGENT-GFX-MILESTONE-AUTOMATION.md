# SharnouDevAgent - Automatic GFX Milestone Campaign

**Document:** DGA-GFX-0.1  
**Date:** 2026-11-28 (Africa/Cairo)  
**Status:** Campaign contract and machine-readable milestone plan created; the native autonomous generator is NOT IMPLEMENTED and NOT ENABLED.  
**Repository baseline reviewed:** Sharnou-Compiler, default HEAD 36b07383cb0ee1996298724202454eb8aec57d98.  
**Related tracking:** [DevAgent issue #14](https://github.com/Sharnou/Sharnou-Compiler/issues/14), [GFX program issue #40](https://github.com/Sharnou/Sharnou-Compiler/issues/40).

## 1. User outcome

The requested outcome is for SharnouDevAgent itself to generate, validate, repair, and submit the complete Sharnou graphics compiler and analysis program:

- GFX-0.1 - graphics compiler architecture;
- GFX-0.2 - SGIR/1 schema and verifier;
- GFX-0.3 - shader lexer, parser and typed AST;
- GFX-0.4 - shader semantic and static analysis;
- GFX-0.5 - D3D11 lowering and reflection;
- GFX-0.6 - actual shader execution and indexed 3D mesh;
- GFX-A.1 - glTF/GLB geometry analyzer;
- GFX-A.2 - KTX2 and PBR material analyzer;
- GFX-A.3 - skeleton and animation analyzer;
- GFX-0.7 - Sharnou IDE graphics workbench;
- GFX-0.8 - GPU profiling and optimization.

The authoritative, machine-readable plan is:

Projects/DevAgent/GfxCampaign.v1.json

Its structural contract is:

Schemas/DevAgent/GfxCampaign.v1.schema.json

The manifest records the actual draft status of PR #39 and PR #41, dependency edges, specialist roles, permitted source paths, deliverables, acceptance gates, hard stops, and owner decisions. It is not an executable code generator by itself.

## 2. Current reality - why automatic generation is not active yet

The current default branch does not contain a production SharnouDevAgent that can autonomously generate and validate source changes.

Repository evidence must be interpreted carefully:

1. PR #7 is a historical native regression-test orchestrator. It exposes a free-form process command path, uses an unbounded wait, and lacks the reviewed model-facing security boundary. Do not reuse it for model-generated commands.
2. PR #18 is a draft native broker/process-execution candidate. Its existence and earlier focused test results do not make it an accepted production execution authority.
3. The separate Phase 2B.8 security sequence is still in qualification. R5.1.c has scoped evidence, but R5.1.d remains draft/not accepted pending final exact-head evidence and the real OS shutdown-delivery qualification. R5.2/R5.3 remain behind that gate. Model-facing process execution and autonomous execution remain DISABLED.
4. The DevAgent architecture still requires a genuine Sharnou-owned in-process inference runtime, durable journal/restart recovery, typed workspace patch transactions, a bounded repair loop, and a native repository adapter. These are not replaced by a campaign JSON file.
5. The GFX source candidates are not accepted: PR #39 is an open draft architecture proposal; PR #41 is an open draft SGIR/1 implementation. PR #41 has no confirmed exact-head Windows PowerShell 5.1 qualification result or verified artifact in the reviewed evidence.

Therefore the campaign's initial activation state is BLOCKED_UNTIL_DEVAGENT_PREREQUISITES_PASS. This is deliberate. A deterministic scheduler must not pretend to be a model, and a model must not be given a process or repository-write capability before its security boundary passes.

The request to automate the GFX program is recorded as the target behavior. The current repository has not yet met the technical prerequisites to execute that behavior.

## 3. Target architecture

The target native DevAgent consists of these cooperating subsystems:

- Campaign Kernel: manifest/schema loader, dependency planner, evidence state machine, durable task journal.
- Local Cognition: in-process model runtime, planner, critic, context manager and specialist roles.
- Typed Tool Registry: repository adapter, workspace transactions, registered build/test broker, research and knowledge tools.
- Evidence Evaluator: exact commit verification, test results, logs, artifact hashes, runtime evidence and owner approvals.
- PR Writer: isolated branch and draft PR creation only after required qualification.

The control plane, local inference runtime, tool broker and persistence layer should be linked into one Sharnou-owned native application. The model weights and research material are data assets, not helper executables.

### 3.1 Campaign kernel

The kernel must:

- Load the schema and campaign manifest with strict version checking.
- Reconcile each milestone against live repository branches, PRs, issues, Actions runs and evidence artifacts.
- Compute a dependency-safe topological order.
- Mark a task READY only when all required predecessors are ACCEPTED and every external gate is satisfied.
- Persist task state, source commit, plan version, patch hash, test evidence and approval decisions.
- Resume only idempotent work after restart; interrupted writes/processes must be reconciled, not assumed successful.
- Create one bounded task graph per milestone and report BLOCKED/FAILED/NOT RUN without hiding the reason.

The model cannot set a milestone to ACCEPTED. The evidence evaluator and owner-review transition determine that state.

### 3.2 Local cognition and specialist roles

The intended default is a real Sharnou-owned model runtime inside the native DevAgent process. It must perform actual inference over a versioned, licensed model; hard-coded responses or template substitution are not AI generation.

Specialist roles are constrained profiles, not unrestricted executable plugins:

- Graphics Compiler Architect
- Shader Language and Frontend Engineer
- SGIR/SSA Verification Engineer
- Shader Semantic Analysis Engineer
- D3D11 Backend and Reflection Engineer
- glTF/GLB Geometry Engineer
- KTX2/PBR Material Engineer
- Skeleton and Animation Engineer
- Sharnou IDE Graphics Engineer
- GPU Profiling Engineer
- Test/QA Engineer
- Security and Dependency Reviewer

A reviewer role critiques each patch against the task contract. It does not replace Windows tests, static verifiers or physical-GPU evidence.

OpenAI and Perplexity may be optional provider adapters after protected credential, redaction, budget and provider-contract work is complete. A ChatGPT subscription/UI session is not an API integration. No private source is sent to a remote provider without explicit owner permission.

### 3.3 Native repository adapter

The production DevAgent needs a provider-neutral, typed repository interface:

- Read repository metadata, branches, files, PRs, issues, workflow results and artifacts.
- Create an isolated branch from the exact accepted parent commit.
- Write only approved patch paths to the staging worktree.
- Commit and push only under the campaign's explicit policy.
- Open a DRAFT PR after all required local and Windows qualification gates pass.
- Read back the PR and ensure its recorded head SHA equals the tested SHA.

GitHub credentials must be stored in the protected Windows credential boundary, never in source, prompt text, task journal, generated agent manifests or model-visible context. The native adapter must not use the ChatGPT connector's credentials implicitly.

## 4. Campaign dependency graph

The scheduler must follow these edges; it must not simply iterate the table or launch every row concurrently.

GFX-0.1 Architecture  
  -> GFX-0.2 SGIR/1 schema + verifier  
  -> GFX-0.3 Lexer / parser / typed AST  
  -> GFX-0.4 Semantic + static analysis  
  -> GFX-0.5 D3D11 lowering + reflection  
  -> GFX-0.6 Real shader execution + indexed mesh  
  -> GFX-0.7 IDE workbench  
  -> GFX-0.8 GPU profiling

Asset stream:

GFX-0.1 Architecture  
  -> GFX-A.1 glTF/GLB geometry  
       +-> GFX-A.2 KTX2/PBR material  
       +-> GFX-A.3 Skeleton/animation

GFX-0.7 depends on GFX-0.3, GFX-0.4, GFX-0.5, GFX-0.6 and all three asset analyzers. GFX-0.8 depends on GFX-0.6 and GFX-0.7. The machine-readable manifest is authoritative if this visual outline is edited later.

### Parallelism

The default is one active milestone at a time. After GFX-A.1 is accepted, GFX-A.2 and GFX-A.3 may run in parallel only if their staged worktrees and owned paths do not overlap. The campaign's maximum concurrency is two. Shared-file conflicts force serialization; they are not resolved by an automatic blind merge.

GFX-0.3 must not begin while GFX-0.2 is merely an open PR or while its Windows qualification is missing. GFX-0.7 must wait for the common compiler and asset-analysis interfaces it consumes. GFX-0.8 must wait for the real runtime render path and profiling contract.

## 5. Generation and verification loop

For each READY milestone, the native DevAgent must execute this transaction:

1. **Preflight:** read current AI_START_HERE, session state, master plan, issue register, README, renderer roadmap, exact source/test files, and live PR/Actions state. Record the actual parent SHA.
2. **Reconcile:** inspect existing work. For GFX-0.1 and GFX-0.2, review PR #39 and PR #41; do not regenerate or duplicate their contents.
3. **Plan:** produce a typed task graph with file ownership, allowed paths, explicit dependencies, positive/negative tests, expected runtime evidence, resource budgets and stop conditions.
4. **Research:** consult primary specifications and documentation. Record URLs, retrieval times, version, source claims and content hashes. Treat external text/code as untrusted input.
5. **Generate:** create a minimal patch in an isolated staging worktree. The model must not write directly to the default branch.
6. **Critique:** run the specialist reviewer against the diff, policy, source compatibility, architecture and acceptance contract.
7. **Static validation:** check encoding, paths, schema, compiler diagnostics, verifier invariants, dependency policy and patch limits.
8. **Build and test:** invoke only registered typed tool IDs. Capture separate stdout/stderr, raw exit codes, duration, tool hash and test totals. No model-generated shell command is allowed.
9. **Repair:** allow at most three bounded repair attempts. Every repair reruns the failed gate and all mandatory regression gates. A repeated identical failure or budget exhaustion stops the task.
10. **Rollback or retain:** any mandatory failure restores the staging snapshot and records the evidence. A successful patch remains staged until exact-head Windows validation.
11. **Windows qualification:** open a draft PR only after the required exact-head workflow result and hash-bound artifact are available. The evidence must identify the tested commit, source hashes, runner, PowerShell version, all test outcomes and artifact digest.
12. **Owner review:** stop at a DRAFT PR. The agent never merges, releases, deploys, or changes its own permissions.

A patch passing the agent's critic is not accepted. The actual verifiers, Windows runtime and required physical-GPU capture are authoritative.

## 6. Milestone-specific technical gates

The campaign manifest records the detailed file scopes and gates. The following are non-negotiable:

### Shader compiler milestones

- GFX-0.3 must emit source-mapped, typed AST and lower only supported constructs to SGIR/1. Invalid source emits no valid module.
- GFX-0.4 must distinguish compile-time correctness diagnostics, static estimates and measured hardware data.
- GFX-0.5 must lower only verified IR and compare actual reflection to the Sharnou contract. A D3DCompiler_47.dll in-process bridge is a separate owner decision; it must not appear as an implicit dependency. DXC, Clang, MSVC, fxc.exe and dxc.exe are not authorized.
- GFX-0.6 must render a real indexed mesh through the native Sharnou Engine. A window clear, generated image, static screenshot or WARP-only result is not a high-performance GPU acceptance.

### Asset analysis milestones

- GFX-A.1 parses glTF JSON and GLB containers with bounds/overflow checks and rejects unsupported required extensions.
- GFX-A.2 validates KTX2, DFD, level ranges, Basis/KHR_texture_basisu metadata and PBR texture semantics. Structural parsing does not prove transcoding or GPU upload.
- GFX-A.3 cross-checks skins, joints, weights, inverse-bind matrices and animation channel/accessor targets. It must not invent missing skeleton links.

The established asset roles remain: glTF/GLB for 3D scene/geometry/skeleton/animation; KTX2/Basis with KHR_texture_basisu for 3D material textures; AVIF for appropriate 2D/UI imagery.

### IDE and profiling milestones

- GFX-0.7 must consume the same compiler/analyzer library outputs used by command-line builds; no UI-only reimplementation of shader semantics.
- GFX-0.8 requires real D3D11 timestamp/disjoint query measurements, asynchronous GetData polling, named hardware/driver metadata and reproducible before/after captures. Estimates remain clearly labelled estimates.

## 7. Milestone state machine

Allowed durable states:

BLOCKED -> READY -> PLANNED -> GENERATING -> PATCH_READY -> TESTING -> WINDOWS_QUALIFIED -> OWNER_REVIEW -> ACCEPTED

Alternative holding or terminal states are FAILED, PAUSED and CANCELLED.

Rules:

- A milestone cannot skip a state.
- A failed gate returns to PLANNED only within the bounded repair count; otherwise it becomes FAILED.
- A predecessor PR being open or green on a different SHA is not ACCEPTED.
- WINDOWS_QUALIFIED requires exact-head evidence. Physical-GPU milestones additionally require a real target-device capture.
- Only owner/reviewer acceptance moves OWNER_REVIEW to ACCEPTED.
- Downstream tasks remain BLOCKED until all predecessor and owner-decision gates pass.
- Reopening a predecessor invalidates dependent qualification snapshots until the scheduler revalidates them.

## 8. Process, repository and network safety

The campaign does not waive the DevAgent security design or Phase 2B.8/R5 qualification.

- No raw model-controlled process command, executable path or caller-created argument string.
- No process execution until the typed broker, restricted execution, bounded I/O, timeout/cancellation, Job Object cleanup and restart-safe workspace recovery are accepted.
- No arbitrary path writes, symlink/reparse escapes, network-denied bypass, downloaded executable execution or secret access.
- No direct writes to the default branch.
- No automatic merge, release, service install, compiler dependency addition or system configuration change.
- Research/download must use explicit host policy, HTTPS validation, size/redirect quotas, SHA-256 and provenance.
- API keys remain protected by the Windows credential boundary and never enter model context.
- Existing Phase 2B.8 security gates remain independent and unchanged.

The current model-facing process execution boundary stays DISABLED.

## 9. DevAgent implementation order required to activate this campaign

The GFX manifest is now defined, but the following native capabilities must be implemented and independently qualified before its automatic generation mode can be activated:

| DevAgent increment | Required capability | Activation result |
|---|---|---|
| DGA-0.1 | Campaign schema, milestone DAG and evidence/permission contract (this increment) | Machine-readable campaign defined |
| DGA-0.2 | Deterministic manifest validator and dependency/evidence planner | Can report READY/BLOCKED without generating code |
| DGA-0.3 | Append-only task journal, hash-bound checkpoints and restart recovery | Can resume interrupted planning safely |
| DGA-0.4 | Native read-only GitHub/source/Actions adapter and protected credentials | Can reconcile PRs and live evidence |
| DGA-0.5 | Real Sharnou-owned in-process local inference runtime | Can reason and generate actual candidate source/diffs |
| DGA-0.6 | Typed workspace read/write/diff/rollback transaction engine | Can stage bounded patches safely |
| DGA-0.7 | Accepted native process broker and all required Phase 2B.8 execution/recovery gates | Can invoke registered build/test tools |
| DGA-0.8 | Specialist-role orchestration, critique, bounded repair and evidence collector | Can execute a complete milestone transaction |
| DGA-0.9 | Campaign scheduler, branch/commit/draft-PR writer and restart-resume qualification | Can run the GFX campaign in automatic draft-PR mode |

DGA-0.2 through DGA-0.9 are not claimed implemented by this document. DGA-0.5 must be genuine model inference, not canned responses. DGA-0.7 must not bypass any current security blocker. If local inference is unavailable, an optional external provider may only be used after the provider adapter and private-source approval requirements pass.

## 10. Current campaign disposition

| Milestone | Repository status | Next action |
|---|---|---|
| GFX-0.1 | Draft PR #39 | Architecture review and explicit acceptance |
| GFX-0.2 | Draft PR #41; exact-head Windows qualification unconfirmed | Run/inspect Windows PowerShell 5.1 gate, repair, artifact verification |
| GFX-0.3 | Planned | Blocked on accepted GFX-0.1 and GFX-0.2 |
| GFX-0.4 | Planned | Blocked on GFX-0.3 |
| GFX-0.5 | Planned | Blocked on GFX-0.4 and explicit backend dependency decision |
| GFX-0.6 | Planned | Blocked on GFX-0.5 and physical-device runtime qualification |
| GFX-A.1 | Planned | Blocked on GFX-0.1 architecture acceptance |
| GFX-A.2 | Planned | Blocked on GFX-A.1 |
| GFX-A.3 | Planned | Blocked on GFX-A.1 |
| GFX-0.7 | Planned | Blocked on compiler and asset analyzer interfaces |
| GFX-0.8 | Planned | Blocked on real mesh rendering and IDE profiling integration |

**DGA-GFX-0.1 result:** schema and campaign manifest have been created as a repository contract. The native DevAgent cannot yet execute the campaign. No shader parser, GPU backend, asset analyzer or IDE feature is claimed generated by this increment.

## 11. Acceptance for this DGA-GFX-0.1 contract

- The schema and manifest are valid JSON and the manifest declares exactly the eleven requested GFX milestones.
- Every dependency reference resolves, the graph is acyclic, and all existing PR/head references are recorded as drafts rather than accepted features.
- The campaign activation state remains BLOCKED while local inference, typed patch tools, process broker, durable recovery and native repository/evidence adapters are unavailable.
- The policy forbids default-branch writes, automatic merge/release and arbitrary process commands.
- No GFX milestone can be promoted by model assertion alone.

This deliverable is a durable contract for the future native DevAgent worker, not a claim that autonomous source generation is already running.


## DGA-0.2 - Deterministic campaign validator and dependency planner

**Status:** Windows PowerShell 5.1-qualified on exact head 9db82798bd3e4f97f16cbfa74baee85687932ce1; draft PR review/acceptance remains pending.

DGA-0.2 adds a deterministic, offline campaign kernel. It checks the campaign root, schema identity and key schema invariants, supported property sets, the exact eleven milestone IDs, bounded values, execution-policy invariants, specialist/asset path lists, PR metadata, duplicate and dangling dependency edges, self-dependencies, and dependency cycles. It emits a stable topological order that preserves the independent asset-analysis stream.

The PR snapshot contract is separately versioned in Schemas/DevAgent/GfxPullRequestSnapshot.v1.schema.json. A supplied snapshot is reconciled against the manifest's PR number, expected base branch, head branch and exact head SHA. This explicitly supports the current stacked GFX-0.2 PR base: it targets the GFX-0.1 architecture branch, not the default branch. A candidate cannot be accepted from a manifest status, title or unbound green CI result. Required Windows evidence must match the exact PR head, have at least one passing test, zero failures and zero skips, and carry an artifact SHA-256. Physical-GPU work additionally requires tested-head identity, adapter, driver and capture digest. Explicit owner acceptance is a separate condition.

The planner emits BLOCKED, READY, OWNER_REVIEW, ACCEPTED, FAILED or PAUSED states and full blocker reasons. Existing PRs stay BLOCKED without a valid live snapshot. New work becomes READY only when all predecessors are ACCEPTED and the campaign activation gates are satisfied. An invalid manifest is a hard error.

### Run in Windows PowerShell 5.1

    .\Tools\DevAgent\Invoke-GfxCampaignPlanner.ps1
    .\Tools\DevAgent\Invoke-GfxCampaignPlanner.ps1 -SnapshotPath .\Artifacts\GfxPullRequestSnapshot.v1.json
    .\Tests\Test-GfxCampaign.ps1

The optional PR snapshot is a typed input contract for the future native read-only GitHub adapter. It is not a manually trusted replacement for live repository reads. The current CLI makes no network calls and performs no repository writes.

### Continuous improvement after GFX-0.8

GFX-0.8 is not a terminal product state. The machine-readable continuousImprovement policy keeps Sharnou Graphics Compiler on an ongoing improvement path across compiler construction and IR, shader language frontends, D3D11/DXGI backends, GPU architecture, geometry analysis, glTF/GLB semantics, KTX2/Basis, PBR, skeletal animation, render graphs, GPU profiling, and professional IDE/viewport tooling.

The intended loop is:
1. Discover new primary specifications, official platform documentation, peer-reviewed research and reproducible technical reports.
2. Record source URL, retrieval timestamp, source version/revision, content SHA-256, applicability and contradictory findings. Treat retrieved material as untrusted input.
3. Compare proposals with the existing compiler/runtime architecture, target hardware, ABI, test corpus and dependency policy.
4. Establish reproducible baselines; distinguish estimates from measured CPU and physical-GPU performance.
5. Create a small, versioned follow-on GFX improvement milestone with path ownership, dependencies, positive/negative tests, rollback and evidence requirements.
6. Generate on an isolated branch, independently review, qualify the exact head on Windows, and require explicit owner acceptance.

Future work may continue in later GFX-EVOL campaigns. Accepted milestones and evidence remain immutable; research does not silently rewrite history. No external compiler/linker/shader tool or runtime dependency is admitted without explicit approval. Automatic merge and release remain prohibited.

**Execution boundary:** DGA-0.2 validates and plans the policy; it does not run a background research daemon or autonomously write source. Continuous scheduled research requires later DGA work: durable journal/recovery, native read-only repository/research adapter, genuine Sharnou-owned local inference, typed patch transactions, accepted process-broker security gates, and the campaign scheduler. When the DevAgent host is stopped, no background progress is claimed.

### DGA-0.2 limitations

This is a repository-specific contract validator, not a complete implementation of every JSON Schema 2020-12 keyword. It cross-checks schema identity and selected structural invariants, then applies strict domain validation and cross-object rules. Windows PowerShell 5.1 ConvertFrom-Json does not expose duplicate JSON object keys for rejection at this layer; duplicate milestone IDs, dependency edges and PR snapshot numbers are rejected. The validator/planner contains no process launch, shell invocation, network call or Git write API.


## DGA-GFX-0.2 Windows qualification evidence - 2026-11-28

- Qualified branch head: 6299da2234d4adcb1a3c01efd70225580d230761.
- Windows PowerShell 5.1 workflow: SharnouDevAgent GFX Campaign Validation.
- Pull request validation run: https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46148617044 - PASS.
- Branch push validation run: https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46148612214 - PASS.
- Dedicated campaign tests: 47 passed, 0 failed, 47 total.
- Source encoding/BOM gate: PASS.
- Planner CLI: PASS; emits the eleven-milestone readiness plan and correctly leaves the campaign blocked by unaccepted predecessor/activation gates.
- These results qualify the DGA-0.2 validator/planner on the tested PR head. They do not qualify the GFX compiler milestones, the native DevAgent runtime, background research, GPU rendering or autonomous code generation.
- The branch remains a draft PR stacked on DGA-GFX-0.1 PR #42. No merge was performed.


## DGA-GFX-0.3 - durable task journal, hash-bound checkpoints and restart recovery

**Status:** Windows PowerShell 5.1-qualified on exact head 847e9e7c3c5b07d02ce2cb21aa56caac1293e4fa; draft PR review/acceptance remains pending.

DGA-GFX-0.3 introduces a local persistence primitive for future DevAgent campaign execution. The journal is append-only and uses one immutable JSON envelope per event, named by a monotonically increasing sequence and deterministic event ID. Each envelope contains an exact body string and SHA-256 digest. Each body binds the journal ID, sequence, event ID, idempotency key, event type, task ID, timestamp, previous-record SHA-256 and Base64-encoded bounded event payload. Replay validates the complete chain from the genesis event and reconstructs task state; any malformed, missing, reordered, tampered or conflicting record fails closed.

The journal uses a named mutex in the Windows Local namespace, derived from the state-directory path. It serializes cooperating writers within the same Windows logon session; it does not guarantee mutual exclusion across separate logon sessions that concurrently open the same state root. A new file is written to a same-directory temporary file, flushed with FileStream.Flush(true), closed, and moved to its immutable final name. Existing records are never rewritten. A crash may leave an unreferenced temporary file or checkpoint; these are reported, not silently promoted or deleted. This is a Windows filesystem durability strategy, not a claim against faulty storage hardware, malicious same-user tampering or filesystem/volume failure.

Checkpoints are separate immutable files. Their state payload is bounded, UTF-8 encoded and SHA-256 hashed; each checkpoint body binds journal ID, task ID, checkpoint sequence, predecessor checkpoint digest, payload digest and state bytes. A TaskCheckpointed journal event binds the filename and both digests. Replay verifies every referenced checkpoint, including its predecessor link, before it trusts task state. A checkpoint written immediately before a crash but not journaled is an orphan and is not treated as committed.

### Task lifecycle and idempotency

Supported events are JournalCreated, TaskPlanned, TaskStarted, TaskCheckpointed, TaskInterrupted, TaskResumed, TaskCompleted, TaskFailed and TaskCancelled. Task identities are derived from stable caller-supplied idempotency keys. Repeating an identical operation returns DUPLICATE_NOOP; reusing a key with different content is a hard conflict. State transitions are checked on append and replay. Running tasks discovered on restart receive one idempotent HOST_RESTART interruption event and become resumable only against the latest verified checkpoint.

### Run

In Windows PowerShell 5.1:

    .\Tools\DevAgent\Invoke-GfxTaskJournal.ps1 -Action Initialize
    .\Tools\DevAgent\Invoke-GfxTaskJournal.ps1 -Action Inspect
    .\Tools\DevAgent\Invoke-GfxTaskJournal.ps1 -Action Recover
    .\Tests\Test-GfxTaskJournal.ps1

The default state root is %LOCALAPPDATA%\Sharnou\DevAgent\GfxCampaignState; tests use an isolated temporary directory. The journal contains bounded task metadata, hashes and checkpoint state only. Do not put prompts, credentials, tokens, proprietary source contents or unreviewed research text into journal/checkpoint state. Credential-like property names are rejected in checkpoint state.

### DGA-GFX-0.3 security and operational boundary

This component performs local file persistence only. It has no process launch, shell, network, repository mutation or model-inference path. It does not enable unattended workers, research scheduling, model-facing process execution, build/test invocation or GitHub writes. It is not yet the fully qualified protected execution workspace: ACL identity, service-owned storage, hostile same-user process isolation, and the separate Phase 2B.8/R5 process-broker boundary remain independent requirements. A checksum detects modification; it is not an authentication signature and does not stop an attacker who can rewrite the complete journal and recompute hashes.

DGA-0.3 does not itself make continuous research run in the background. It supplies durable task history and restart reconciliation needed by later repository/research adapters, local inference, typed patch transactions, specialist orchestration and the eventual scheduler.


## DGA-GFX-0.3 Windows qualification - 2026-11-28

- Qualified implementation head: 847e9e7c3c5b07d02ce2cb21aa56caac1293e4fa.
- Windows PowerShell 5.1 push run: https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46159857700 - PASS.
- Windows PowerShell 5.1 pull-request run: https://github.com/Sharnou/Sharnou-Compiler/actions/runs/46159863463 - PASS.
- Journal test suite: 30 passed, 0 failed.
- Source encoding and BOM gate: PASS.
- CLI Initialize and Inspect: PASS; returned integrity PASS, one genesis record, zero tasks and no abandoned temporary files.
- Negative tests cover relative and UNC state roots, conflicting idempotency reuse, credential-shaped checkpoint keys, resume without a committed checkpoint, checkpoint tampering, journal tampering and a missing interior record.
- Positive tests cover deterministic task identities, lifecycle transitions, duplicate no-op behavior, two sequential checkpoints and checkpoint predecessor validation, restart interruption, idempotent recovery, verified resume, completion, failure and cancellation.
- PR #44 remains a draft stacked on PR #43. No merge or default-branch write occurred.

### Operational limitations to preserve

The mutex uses the Windows Local namespace, so concurrent writers in separate Windows logon sessions are not coordinated by this DGA-0.3 implementation. The same state root must therefore be owned by one DevAgent host session until a later cross-session coordination design is independently qualified.

The journal stores task metadata and explicitly supplied bounded checkpoint state. It does not automatically persist model conversations, raw source trees, credentials, prompts or complete research documents. SHA-256 chaining detects record corruption but is not a signature or an authorization mechanism. An attacker able to rewrite all journal/checkpoint files can recompute the hashes. Protected service-owned ACLs, verified service identity and the independent Phase 2B.8/R5 security gates remain mandatory before the journal is trusted by autonomous or model-controlled execution.


## DGA-GFX-0.4 - read-only GitHub repository and Actions adapter

**Status:** implementation candidate; exact-head Windows PowerShell 5.1 qualification is pending.

DGA-GFX-0.4 adds a typed read-only GitHub REST adapter for the fixed Sharnou/Sharnou-Compiler repository. Its public operations read repository metadata, branch tips, commit metadata, source-file contents, pull-request state, Actions workflow runs and run-artifact metadata. The adapter has no general-purpose URL or HTTP method input. Every network request is HTTPS to api.github.com, uses an explicit GET method, disables automatic redirects, applies bounded timeouts and response sizes, and suppresses response bodies in HTTP error messages.

Source-file reads first resolve the requested branch/ref to a full commit SHA, then request the file at that exact SHA. The adapter verifies Git's blob SHA-1 against the received bytes and records an independent SHA-256 digest and byte count. Source reads are capped at 1 MiB. Actions results are queried by full commit SHA; a returned run with a different head SHA is rejected. Commit evidence binds repository identity, commit/tree identity, workflow run IDs and attempts, timestamps, conclusions, and each artifact's run ID, size, expiration and GitHub-provided SHA-256 digest.

A fine-grained GitHub token can be configured interactively with Read-Host -AsSecureString. It is encrypted with Windows DPAPI for the current Windows user and written under %LOCALAPPDATA%\\Sharnou\\DevAgent\\Credentials with an owner-only ACL. The CLI never accepts a token argument and its credential status output contains no token. Recommended fine-grained token permissions are repository Metadata: read, Contents: read, Pull requests: read and Actions: read. Use the narrowest repository selection possible. See the official [fine-grained token permission matrix](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).

Example Windows PowerShell 5.1 commands:

\`\`\`powershell
.\\Tools\\DevAgent\\Invoke-GfxGitHubAdapter.ps1 -Action CredentialStatus
.\\Tools\\DevAgent\\Invoke-GfxGitHubAdapter.ps1 -Action ConfigureCredential
.\\Tools\\DevAgent\\Invoke-GfxGitHubAdapter.ps1 -Action PullRequestEvidence -PullRequestNumber 44
.\\Tools\\DevAgent\\Invoke-GfxGitHubAdapter.ps1 -Action CommitEvidence -CommitSha <full-40-character-sha>
.\\Tools\\DevAgent\\Invoke-GfxGitHubAdapter.ps1 -Action File -Path Tools/DevAgent/GfxTaskJournal.psm1 -Ref <branch-or-full-sha>
\`\`\`

The captured artifact entries are metadata only. DGA-GFX-0.4 does not download ZIP artifacts, extract archives, fetch job logs, or claim that the GitHub-reported digest has been independently verified against artifact bytes. A later bounded evidence collector must perform digest-verified artifact retrieval before artifacts can be treated as locally verified test evidence. Workflow conclusion alone is not a qualification decision; exact-head checks, test totals, artifact payload verification and owner acceptance remain separate gates.

The credential store is DPAPI-protected for the interactive user's Windows identity, not a service SID or cross-session secret broker. It must not be treated as service-owned authentication until the independent Phase 2B.8/R5 identity, ACL and lifecycle qualification is accepted. The adapter does not launch processes, execute shell commands, infer/generate code, write Git objects, create branches, mutate PRs/issues, trigger or rerun workflows, approve deployments, or run in the background. External API content remains untrusted input and must be size-bounded, provenance-bound and reviewed before reuse.


## DGA-GFX-0.4 - qualification and journal persistence

DGA-GFX-0.4 implements a read-only GitHub adapter and a bounded metadata-only evidence checkpoint path through the DGA task journal. It is qualified with Windows PowerShell 5.1 on implementation head bacde01986c701ca8735e0e27591bdba3f3b2235: the DGA-GFX-0.4 adapter suite passed 44/44, the DGA-GFX-0.3 journal regression suite passed 30/30, the schema/encoding gates passed, and the credential-status CLI returned NOT_CONFIGURED without exposing a secret. Exact-head Windows push run #46164326875 and PR run #46164332876 passed.

Example: .\Tools\DevAgent\Invoke-GfxGitHubAdapter.ps1 -Action PullRequestEvidence -PullRequestNumber 45 -PersistEvidence. The default persistence root is %LOCALAPPDATA%\Sharnou\DevAgent\DgaGfxState; -StateDirectory overrides it. A snapshot gets its own DGA campaign journal identity, deterministic task ID, immutable checkpoint and idempotent completion. It contains repository/commit/run/artifact metadata only, is bounded to 240 KiB with at most 250 workflow-run summaries and 500 artifact summaries, and records truncation/omission counts.

The GitHub artifact SHA-256 value is an API-supplied metadata field. This milestone does not download the artifact archive or independently hash its bytes; it does not certify the artifact payload. Current-user DPAPI token storage is not a service identity/secret broker. The DGA task journal's SHA-256 chain provides corruption detection, not authentication. Phase 2B.8/R5 service identity, ACL and key lifecycle remain separate prerequisites. No model inference, source generation, process launch, shell, GitHub mutation, worker scheduling or background execution is enabled.
