# DGA-GFX-0.5 - Sharnou-owned in-process local inference

**Current increment:** DGA-GFX-0.5A - model profile, native runtime contract, and fail-closed readiness gate  
**Status:** CONTRACT FOUNDATION IMPLEMENTED CANDIDATE / NATIVE INFERENCE NOT IMPLEMENTED / NOT QUALIFIED  
**Parent:** DGA-GFX-0.4 PR #45, exact parent commit 485481364d57153b16e340d7333a9bf6f4a94e0c  
**Execution policy:** offline-capable, in-process only, no model tool authority

## 1. Objective and non-claims

DGA-GFX-0.5 is the first real cognition layer for SharnouDevAgent. Its acceptance target is genuine token generation from a versioned, legally usable model, performed by Sharnou-owned inference code inside the native DevAgent process.

This increment introduces the model profile and a deterministic contract validator. It does not contain a tokenizer, tensor engine, transformer graph, model weights, or a native inference executable. The validator deliberately returns BLOCKED. It is not an LLM, does not generate answers, and does not enable the graphics campaign.

Do not describe this candidate as local AI, native inference, autonomous reasoning, or a completed DGA-GFX-0.5 runtime.

## 2. First reference-model candidate

The initial architecture candidate is HuggingFaceTB/SmolLM2-135M-Instruct:

- Reference repository: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct
- Reference model configuration revision: 02e84e7cc564d9c3ca090f978a4da4698ccaac29
- Declared license on the official model card: Apache-2.0
- Model architecture: LlamaForCausalLM / llama
- Configuration: 30 decoder layers, hidden size 576, intermediate size 1536, 9 attention heads, 3 key/value heads, vocabulary size 49152, configured context 8192, RMSNorm epsilon 1e-5, RoPE theta 100000, SiLU activation, BF16 weights.

The official model page identifies the artifact family as Safetensors and BF16. The selected profile is a bring-up/reference target, not a claim that a 135M parameter model is sufficient for production-grade compiler engineering. The model card itself describes factual and reasoning limitations. Model output remains advisory and must be verified.

The repository commit above pins the inspected configuration file only. It does not pin model weights, tokenizer bytes, chat-template bytes, or the model license file. Those artifacts remain UNPINNED until their exact revisions, filenames, byte counts, SHA-256 hashes, and license provenance are independently captured. No model has been downloaded or redistributed by this change.

Primary references:
- Model card and license: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct
- Exact configuration: https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct/blob/02e84e7cc564d9c3ca090f978a4da4698ccaac29/config.json

## 3. Required native runtime architecture

The completed runtime must be Sharnou-owned code linked into one native DevAgent process. Model files are untrusted data assets, never helper executables.

Required components, in dependency order:

1. **Model profile and provenance** - strict versioned manifest, immutable source revisions, per-artifact SHA-256, license evidence, declared tensor shapes/dtypes, and a bounded memory estimate.
2. **Safe model-container reader** - parse only the explicitly supported container version; checked arithmetic for every offset/length; reject overlapping, unaligned, truncated, duplicate, out-of-file, or unsupported tensor records. Never deserialize executable/pickle content.
3. **Tokenizer** - exact vocabulary, merges, normalization/pre-tokenization rules, special-token IDs, and chat template from pinned artifacts. Golden encode/decode vectors must match the reference.
4. **Tensor engine** - scalar CPU correctness path first; explicit BF16-to-FP32 conversion; FP32 accumulation; checked tensor shapes and strides; bounded temporary allocations. SIMD is a later optimization and must match scalar results within declared tolerances.
5. **Llama decoder graph** - token embeddings, RMSNorm, RoPE, grouped-query causal attention, attention softmax, KV cache, SwiGLU/SiLU feed-forward, output normalization and language-model head.
6. **Generation controller** - deterministic greedy test mode, bounded sampling mode, repetition policy, EOS/stop handling, cancellation checks, context accounting and output limits.
7. **Native host integration** - in-process API, explicit initialization/disposal, model read-only ownership, no background thread unless separately designed, no process or dynamic-library loader.

Do not add llama.cpp, ggml, Ollama, PyTorch, Transformers, ONNX Runtime, Python, Node.js, MSVC, Clang, an external C++ runtime, or an inference helper process. The architecture and numerical kernels must be Sharnou-owned. Windows system APIs may be used only through reviewed and ABI-verified imports.

## 4. Numeric and compiler prerequisites

The current Sharnou language contract documents integer arithmetic and native integer control flow. The accepted 7C scope includes primitive types, structs, pointers, arrays, slices, and memory ownership, but the reviewed plan does not yet define a complete floating-point ABI or FP32 arithmetic contract.

A BF16 model runtime cannot be implemented safely by pretending integer operations are floating-point. Before transformer kernels are generated, the compiler/runtime work must explicitly define and test:

- IEEE-754 binary32 storage, arithmetic, comparisons, NaN/Infinity behavior, signed zero, and conversion rules.
- BF16 load and conversion semantics, including round-to-nearest-even behavior where conversion is used.
- Checked heap allocation, pointer arithmetic, array indexing, alignment, tensor dimensions and overflow behavior.
- Windows x64 ABI handling for floating-point parameters/returns, XMM register preservation, stack arguments and unwind behavior.
- Deterministic scalar reference kernels before CPU-specific vectorized paths.

These are real compiler/runtime prerequisites, not optional performance refinements. Do not add an unreviewed C++ compiler or external numerical library to bypass them. If a prerequisite is missing, the relevant inference stage remains BLOCKED.

## 5. Initial resource and execution policy

Initial bring-up limits are intentionally conservative and may be reduced by the host:

| Limit | Initial contract |
|---|---:|
| Inference backend | Sharnou native CPU |
| Weight precision | BF16 |
| Accumulation precision | FP32 |
| Quantization | None in first reference path |
| Context window | 1024 tokens |
| Generated output | 128 tokens per request |
| UTF-8 input | 32 KiB |
| Working set ceiling | 1 GiB |
| Request wall-clock budget | 300,000 ms |
| Network during inference | Disabled |

The model configuration permits a larger context, but the initial runtime contract intentionally caps context at 1024 until measured memory, latency and KV-cache behavior are qualified. Quantized support must wait for reference-vector and error-tolerance evidence.

## 6. Security and authority boundary

Inference is not permission to execute tools.

The completed local runtime must enforce:

- No child process, shell, script, executable, plugin or dynamic library loading.
- No network request or remote-provider fallback during local inference.
- No GitHub mutation, workspace write, compiler invocation or process-broker call from the model runtime.
- No function-call text interpreted as an executable tool request.
- No model-controlled capability, policy, permission, milestone-acceptance or credential changes.
- No model weights mutation or arbitrary memory mapping outside the validated model file.
- No prompts, source content, generated text, secrets or credentials in the DGA-GFX task journal.
- Cancellation and resource checks at token and transformer-layer boundaries.
- Model output is untrusted. A separate typed tool registry and later DGA-GFX milestones must authorize every future action.

Private repository content must remain local unless the owner explicitly approves a separate external-provider disclosure. The local runtime must pass with networking disabled.

## 7. DGA-GFX-0.5 staged implementation plan

| Slice | Deliverable | Exit gate |
|---|---|---|
| 0.5A | Model profile, strict manifest contract, dependency audit, fail-closed readiness | Contract tests pass; readiness remains BLOCKED |
| 0.5B | Pinned model/tokenizer/license artifacts and safe container reader | Exact artifact hashes; malformed/truncated/overlap tests |
| 0.5C | Tokenizer, special tokens and chat template | Reference encode/decode golden vectors |
| 0.5D | BF16/FP32 tensor storage and scalar CPU kernels | Numerical golden vectors and overflow/bounds tests |
| 0.5E | Llama graph, GQA, RoPE, KV cache and sampler | Layer-level and full-logit reference vectors |
| 0.5F | Native in-process host integration | Offline Windows exact-head inference and restart/resource tests |

The slices are sequential. Do not mark 0.5 complete until 0.5F passes. A successful manifest validation is not model inference evidence.

## 8. Full DGA-GFX-0.5 acceptance gates

- A model profile pins the exact weight, tokenizer, chat-template and license artifacts by immutable revision, byte count and SHA-256.
- License evidence is retained and reviewed for intended use; no artifact is promoted from a model-card label alone.
- The native runtime parses only the documented supported model format and rejects all unsupported structures.
- Golden tokenizer vectors and model tensor vectors match the reference implementation.
- Scalar tensor kernels pass numerical tolerance, bounds, overflow and determinism tests.
- The full supported decoder produces deterministic greedy outputs for pinned prompts with recorded token IDs and output hashes.
- The native runtime executes inside the same process as the DevAgent; process telemetry and import-table review prove no helper executable or inference DLL is used.
- It operates with networking disabled, within memory/context/output/time limits, and supports cancellation and clean disposal.
- Exact-head Windows CI reports source hashes, test totals, exit codes, model artifact identities and runtime measurements.
- The runtime exposes no process, repository-write, network or tool authority.
- The existing DGA-GFX-0.3 journal and DGA-GFX-0.4 adapter regression suites remain passing on the same PR head.
- The campaign remains blocked until later typed patch, process-security and orchestration milestones are separately accepted.

## 9. Current result and next dependency

Implemented candidate files:
- Schemas/DevAgent/GfxLocalModel.v1.schema.json
- Projects/DevAgent/Models/SmolLM2-135M-Instruct.profile.v1.json
- Tools/DevAgent/GfxLocalInferenceContract.psm1
- Tools/DevAgent/Invoke-GfxLocalInferenceContract.ps1
- Tests/Test-GfxLocalInferenceContract.ps1
- .github/workflows/devagent-gfx-local-inference-contract.yml

This slice validates the model proposal and proves the readiness gate refuses activation. It does not implement any of the runtime components in section 3.

Next engineering dependency: complete the explicit Sharnou numeric/memory/ABI prerequisite audit and select/pin the actual model and tokenizer artifacts. Only then begin the safe container reader and scalar tensor-kernel implementation. Keep model-facing process execution disabled; Phase 2B.8/R5 is an independent gate.
