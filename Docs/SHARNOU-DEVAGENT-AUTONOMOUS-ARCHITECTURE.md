# SharnouDevAgent - Autonomous Development Architecture

**Status:** Requested architecture and implementation proposal; no autonomous AI source generator is implemented yet.  
**Audited branch:** `Sharnou-Compiler`  
**Audited HEAD:** `cf8a9cd26cf3819d1ee3156155eafa5259c39b05`  
**Tracking issue:** [#14 - Build SharnouDevAgent as a native autonomous development system](https://github.com/Sharnou/Sharnou-Compiler/issues/14)

## 1. Product goal

Evolve SharnouDevAgent from a native test orchestrator into a project-scoped autonomous software-development system that can research, understand, plan, modify, compile, test, debug, reverse-engineer authorized binaries, create specialist agents, and recover work after restarts.

The primary operating mode must be local and offline. ChatGPT, Perplexity, search services, model hubs, or other AI providers are optional integrations, never required for local reasoning or normal compiler development.

"Full control" means broad capability within explicitly granted workspace, network, and process permissions. It does not mean unrestricted administrator rights, silent security-policy changes, credential access, or arbitrary model-generated shell execution.

## 2. Current repository baseline

The current default-branch Stage 0 compiler does not contain the `sh_dev_run_process` or `CreateProcessA` DevAgent intrinsic. The native DevAgent prototype exists on open draft PR #7, not on the default branch.

PR #7 is a development/test orchestrator. Its source checks workspace files, probes child exit-code propagation, and launches the Stage 7A PowerShell test suite. It is not a source-generating AI agent.

The PR #7 prototype accepts a raw command-line string, creates a child with `CreateProcessA`, inherits standard handles, and waits indefinitely. The reviewed implementation has no executable/argument allowlist, bounded timeout, job-object process-tree containment, sandbox policy, cancellation, or durable worker recovery. It must not be exposed to model-produced commands in its present form.

The repository state records:
- M1-M6 as user-reported Windows passes.
- M7A implementation and Windows CI evidence.
- The frozen 83-case M1-M6 test package as still absent from default until PR #11 is normally reviewed/integrated.
- Historical Windows x64 ABI gaps in issue #1: stack probing, unwind metadata, runtime nonvolatile-register/stack/argument tests, and generic checked API-call marshalling.

These dependencies must be reconciled before broad autonomous compiler edits or self-hosting claims.

## 3. High-level architecture

```text
                       SharnouDevAgent.exe
                 (single native Windows process)
                                |
             +------------------+------------------+
             |                  |                  |
        Agent Kernel       Local Cognition     Durable State
       task scheduler       SharnouAI             journal
       policy engine        model runtime         checkpoints
       tool broker          planner/critic        evidence DB
       agent registry       context manager       content cache
             |                  |                  |
             +------------------+------------------+
                                |
                       Typed Tool Registry
                                |
       +------------+-----------+-----------+-------------+
       |            |           |           |             |
    Workspace    Research    Compiler     Binary        Agent
    read/edit    search      build/test   inspection    factory
       |            |           |           |             |
       +------------+-----------+-----------+-------------+
                                |
                    Windows system API boundary
           WinHTTP / Win32 file APIs / Job Objects /
            restricted process tokens / Credential APIs
                                |
                  Optional remote model adapters
                     OpenAI Responses API
                    Perplexity Agent API
```

The control plane, local inference engine, tool broker, and persistence layer should be linked into the same Sharnou-owned native application. The local model weights and downloaded reference material are data assets, not external executables.

### 3.1 Agent kernel

Responsibilities:
- Convert a user goal and acceptance criteria into a bounded task graph.
- Track dependencies, budgets, deadlines, current state, and cancellation.
- Assign tasks to specialist agent profiles.
- Select tools by declared capability, not by generating arbitrary command strings.
- Require each state transition to produce a journal record.
- Stop on missing evidence, permission denial, repeated failure, or exhausted budgets.

### 3.2 Local cognition runtime

The long-term primary model runtime is a Sharnou-owned inference implementation running in-process. It must not call the ChatGPT desktop/web application or another local AI executable.

Required internal components:
1. Model manifest and tensor-container reader for a documented, versioned Sharnou model format.
2. Tokenizer and detokenizer with versioned vocabulary metadata.
3. Tensor and matrix operations with scalar correctness paths first.
4. CPU feature detection and separately tested optimized kernels.
5. Transformer inference graph for the first explicitly supported model architecture.
6. Context manager, KV cache, batching policy, sampler, stop conditions, and deterministic test mode.
7. Quantized model support only after reference-vector and numerical-tolerance tests.

This is a substantial subsystem. The first delivery should support one small, legally usable model end-to-end, not claim compatibility with every model architecture. Model weights must be obtained under a license that permits the intended use. The model file is downloaded data; no model-hosting program is required.

A compiler/runtime does not become an intelligent LLM merely by adding a planner. Until native model inference and licensed weights exist, the DevAgent can still provide deterministic repository analysis and scripted diagnostics, but it must label generative reasoning as unavailable.

### 3.3 Planning and verification loop

Use a structured loop:

1. **Intake:** parse the requested outcome, constraints, permitted paths, and acceptance tests.
2. **Context:** read current source-of-truth docs, repository state, relevant source/tests, and indexed evidence.
3. **Plan:** build a dependency-aware task graph with explicit stop conditions.
4. **Hypothesize:** generate one or more candidate causes/solutions with evidence references.
5. **Execute:** invoke typed tools with least privilege.
6. **Critique:** a separate reviewer role checks the plan and patch against constraints and evidence.
7. **Verify:** compile, inspect PE output, run targeted tests, then run required regression gates.
8. **Repair:** permit a small bounded number of correction cycles; re-run every failed gate.
9. **Persist:** save source hashes, patch, commands/tool IDs, outputs, exit codes, test totals, and checkpoint.
10. **Report:** distinguish completed, failed, blocked, not-run, and user-approved follow-up actions.

Do not treat a model's self-assessment as proof. Test output, hashes, verifier reports, and runtime evidence are authoritative.

## 4. Typed tool system

Expose named, schema-checked functions. Do not give the model a general `run_command(string)` tool.

Initial tool families:

| Tool family | Example operations | Default permission |
|---|---|---|
| Workspace | list, read, search text, hash, inspect diff | Read-only |
| Research | search configured indexes, fetch URL, extract page | Network policy |
| Download | retrieve into quarantine, verify hash, record provenance | Network + quarantine |
| Knowledge | parse, chunk, index, cite, retrieve | Workspace read |
| Compiler | parse, compile, link, verify PE | Build workspace |
| Tests | run registered suite, collect stdout/stderr/exit code | Allowlisted process |
| Patch | create diff, apply to staging worktree, rollback | Workspace write approval |
| Binary inspection | inspect PE, imports, relocations, strings, decode supported x64 | Read-only |
| Agent management | draft, validate, version, enable, disable, restore profile | Agent-admin approval |
| Provider adapter | submit redacted question, collect response and citations | Explicit opt-in |

All tool inputs and outputs use versioned schemas with strict types, length limits, path canonicalization, and structured error codes. The model never selects arbitrary DLL entry points or raw native addresses.

## 5. Search, read, download, and learning

### 5.1 Native web transport

Use Windows WinHTTP directly:
- `WinHttpOpen`
- `WinHttpConnect`
- `WinHttpOpenRequest`
- `WinHttpSendRequest`
- `WinHttpReceiveResponse`
- `WinHttpQueryDataAvailable`
- `WinHttpReadData`
- `WinHttpCloseHandle`

Require HTTPS by default, normal certificate validation, strict redirect rules, host allowlists, response-size caps, request timeouts, and an audit record. WinHTTP provides the HTTP transport; it is not itself a web-search index. Web search therefore needs a configured search API or a bounded crawler over selected public domains.

### 5.2 Download quarantine

- Write downloads to a temporary quarantine directory, never directly to executable/toolchain paths.
- Enforce maximum size, content-type expectations, redirect limits, and total download quotas.
- Compute SHA-256 and record source URL, final URL, timestamp, byte count, and claimed license/provenance.
- Compare expected hashes when supplied; reject mismatches.
- Do not launch downloaded binaries, scripts, plugins, or agents automatically.
- Promote a quarantined item only through a separate validated action.

### 5.3 Read and learn

Readers should be implemented incrementally for Sharnou source, PowerShell, JSON, XML, Markdown, HTML, PE32+, and archive metadata. PDF support should be added only with a tested parser.

"Learn" initially means:
- Extract facts/code symbols/test behavior from sources.
- Store content-addressed chunks and source provenance.
- Index by path, symbol, error, API, and topic.
- Retrieve relevant chunks into a task context with citations.
- Record corrections and accepted decisions in a durable knowledge journal.

Retrieval memory is not model training. Do not silently fine-tune model weights from arbitrary internet content. Training is a separate, licensed, resource-budgeted pipeline.

## 6. Native process execution and isolation

The existing PR #7 raw-command runner is not safe for model-directed autonomy.

Replace it with a process broker that accepts a structured request:
- Registered executable identity and expected SHA-256.
- Argument vector (not a shell command string).
- Canonical working directory under an approved workspace.
- Explicit environment-variable allowlist.
- Standard input/output/error policy.
- Wall-clock timeout and cancellation token.
- CPU, memory, output-size, and child-process limits.
- Explicit network permission.
- Expected output artifacts and exit-code policy.

The broker must:
1. Resolve the executable to a registered path and verify its hash.
2. Reject shell metacharacters and implicit shell execution because no shell is needed.
3. Create the process suspended when needed to assign containment before execution.
4. Assign it to a Windows Job Object with process-count/resource policy and kill-on-close behavior.
5. Apply a restricted token or AppContainer profile where compatible with the task.
6. Resume only after all policy setup succeeds.
7. Enforce timeout/cancellation and terminate the complete job process tree.
8. Capture bounded stdout/stderr, exit code, duration, and executable hash.

A Job Object manages a process group and can enforce limits or terminate processes; it is not by itself a complete security sandbox. Use filesystem ACLs/restricted tokens/AppContainer capabilities for isolation where appropriate. Never elevate privileges for the agent.

## 7. Automatic corrections and source editing

A correction is a transaction, not an in-place blind rewrite.

1. Create a clean staging worktree or immutable workspace snapshot.
2. Hash all files in the baseline and record modified paths.
3. Parse compiler diagnostics and map them to source spans.
4. Generate a minimal unified diff; reject writes outside allowed paths.
5. Run formatting/encoding checks and static validation.
6. Compile the changed target and run focused tests.
7. Run PE verification and the required regression suites.
8. If any gate fails, preserve the diagnostic, revert the transaction, and return to planning.
9. Limit repair attempts (initial policy: three per task) and stop on repeated identical failures.
10. Keep passing changes in the staging workspace; require owner approval before commit/push/merge/release.

Destructive operations, mass refactors, edits to security/policy files, system-wide configuration, credential operations, and deployment always require explicit owner approval.

## 8. Agent creation and editing

Represent agents as versioned declarative manifests, not arbitrary executable code.

Example conceptual manifest:

```json
{
  "schema_version": 1,
  "agent_id": "compiler-debugger",
  "display_name": "Compiler Debugger",
  "role": "Diagnose Sharnou parser, IR, x64, and PE defects",
  "allowed_tools": [
    "workspace.read",
    "workspace.search",
    "compiler.parse",
    "compiler.build",
    "pe.verify",
    "tests.run"
  ],
  "allowed_paths": [
    "Stage0/**",
    "Tests/**",
    "Examples/**"
  ],
  "network_hosts": [],
  "max_task_seconds": 900,
  "max_tool_calls": 80,
  "max_patch_files": 8,
  "requires_approval": [
    "workspace.apply_patch",
    "git.push",
    "git.merge"
  ]
}
```

Built-in roles may include:
- Compiler Architect
- Lexer/Parser Specialist
- x64 Backend and ABI Auditor
- PE Linker/Verifier
- Windows API and D3D11 Engineer
- Asset Pipeline Engineer
- Reverse Engineering Analyst
- Test/QA Engineer
- Security Reviewer
- Build/Release Auditor

The Agent Factory may draft or edit manifests, generate test prompts, and run a permission-conformance suite. An agent is not enabled until its manifest, tool access, budget, path scope, adversarial tests, and rollback behavior pass. An agent cannot alter its own permission policy or promote itself.

## 9. Reverse engineering

The first reverse-engineering capability is static and read-only:
- Parse DOS/PE32+ headers, section tables, data directories, imports, exports, relocations, and resources.
- Extract strings and metadata.
- Decode a deliberately enumerated subset of AMD64 instructions; unknown instructions remain undecoded bytes, never guessed.
- Recover branch targets, function candidates, and a control-flow graph where decoding is unambiguous.
- Compare two binaries by sections, imports, relocations, instruction blocks, and hashes.
- Cross-reference disassembly with compiler-emitted symbols/maps when available.

Dynamic analysis must use an isolated, user-authorized test workspace and explicit run approval. No process injection, credential extraction, persistence, or bypass of third-party licensing/DRM is part of the DevAgent design.

## 10. Optional external AI consultations

Local inference is the default. Provider adapters are optional and can be disabled entirely.

- **OpenAI:** use the official Responses API over HTTPS; structured tool/function calling can be bridged to Sharnou's typed tool broker. See https://developers.openai.com/api/reference/responses/overview and https://developers.openai.com/api/docs/guides/tools.
- **Perplexity:** use its current Agent API rather than hard-coding an old Sonar-only integration. See https://docs.perplexity.ai/docs/agent-api and the provider's migration announcement at https://www.perplexity.ai/en-GB/hub/blog/agent-api-one-place-to-build-with-llms-the-web-and-agents.
- A provider response is advice/evidence, not authority to execute an action. The local verifier and test suite decide whether a suggested patch is accepted.
- Send only the minimum task context. Redact credentials, personal data, private source paths, tokens, and secrets. Require explicit opt-in before sending private source.
- Store API credentials in Windows Credential Manager or protect local secret blobs with DPAPI. Never put keys into source files, agent manifests, prompts, logs, or model-visible context.
- If the provider is offline, rate-limited, changed, or misconfigured, local work continues without it.

## 11. Persistent memory and recovery

Use an append-only session journal plus content-addressed artifacts:
- Task ID, plan version, state transition, and parent task.
- Source file path, SHA-256, and content hash.
- Tool name/schema version, sanitized arguments, result, duration, and exit code.
- Model/runtime version and model file hash.
- Evidence references and citations.
- Patch diff and rollback snapshot.
- Build/test suite identifiers, totals, failures, and logs.
- User approvals and policy decisions.

On restart, recover the last committed checkpoint, verify referenced hashes, mark interrupted tools as interrupted, clean up orphaned child jobs, and resume only idempotent operations. Never assume an interrupted download, write, or process completed.

## 12. Phased implementation order

| Phase | Deliverable | Acceptance gate |
|---|---|---|
| A - Preconditions | Restore/pin the exact 83-case M1-M6 source suite; reconcile PR #11; re-audit ABI issue #1 | Same-commit 83 + M7A results; documented ABI gate plan |
| B - Safe process broker | Typed executable registry, argument arrays, workspace scope, timeouts, cancellation, Job Objects, restricted execution, audit | Positive/negative process tests; timeout kills descendants; forbidden command/path tests |
| C - Native research and knowledge | WinHTTP transport, search adapters/crawler, reader suite, download quarantine, hash/provenance, local index | Offline index test; host/redirect/size/hash rejection tests; restart-safe downloads |
| D - Local cognition | Sharnou-owned in-process tokenizer/tensor/transformer inference for one supported model | Golden-vector tests, deterministic mode, context/KV tests, CPU limits; no network required |
| E - Planner, memory, and subagents | Task graph, evidence ledger, durable journal, specialist agent registry and critique flow | Multi-step task and restart-recovery tests; exact provenance; budgets enforced |
| F - Agent Factory | Create/edit/version/validate agent manifests | Schema, capability, privilege-escalation, path, tool, and rollback tests |
| G - Autonomous repair | Diagnostic-to-patch loop, staging transaction, focused/full test gates, rollback | Intentionally broken fixtures corrected; one failed gate proves rollback; capped retries |
| H - Reverse engineering | PE parser, x64 decoder subset, CFG, binary comparison | Known-good/known-corrupt fixtures; decoder target validation; unknown bytes fail closed |
| I - Optional AI providers | OpenAI Responses and Perplexity Agent API adapters | Mock contract tests, credential redaction, offline mode, provider error/fallback tests |

Phases A and the existing compiler ABI gate are prerequisites to giving a model control over compiler builds. The local model implementation is a large engineering project; it must not be simulated with hard-coded responses or described as complete before real model inference runs.

## 13. Definition of done

SharnouDevAgent is an autonomous AI development system only when it can, on a clean supported Windows installation:

1. Start with networking disabled and use its local model to understand a repository task.
2. Recover its task, journal, and artifacts after a forced process restart.
3. Search/read/index local source and cite the exact files and hashes used.
4. Create and test a new agent manifest without granting it unauthorized capabilities.
5. Diagnose a seeded compiler defect, patch a staging copy, build and test it, and roll back a deliberately failing patch.
6. Demonstrate a permitted internet search/download with TLS, host policy, size/hash verification, and quarantine.
7. Parse and analyze an authorized PE32+ sample deterministically.
8. Pass the exact frozen compiler regression baseline plus DevAgent security, reliability, and task-level evaluations.
9. Run with no ChatGPT/Perplexity API key and no external AI CLI or helper process.
10. Use optional provider adapters only when explicitly enabled by the owner, with secrets protected and private-source sharing controlled.

No task is accepted on the basis of model confidence or a green final counter alone; all individual test results, hashes, exit codes, and required runtime evidence must be recorded.
