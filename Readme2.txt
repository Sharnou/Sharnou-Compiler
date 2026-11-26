# Sharnou File-Format Governance Policy
## Initial proposal - Pending approval

The previous restriction against custom Sharnou file formats is revoked.

The initial policy accepts four native Sharnou formats and preserves the existing asset-format strategy. It establishes consistent encoding, validation, integrity, versioning, and compatibility rules across the compiler, IDE, Engine, and Honour War repositories.

**Status: PROPOSED - NOT APPROVED - NOT APPLIED**

I inspected the four connected repositories without making changes:

| Repository | Default branch | Existing configuration |
|---|---|---|
| `Sharnou/Sharnou-Compiler` | `Sharnou-Compiler` | No root `.gitattributes` or `.gitignore` found |
| `Sharnou/Sharnou-IDE` | `main` | No root `.gitattributes` or `.gitignore` found |
| `Sharnou/Sharnou-Engine` | `main` | Existing `.gitignore`; no root `.gitattributes` found |
| `Sharnou/Honour-War` | `main` | Existing `.gitignore`; no root `.gitattributes` found |

`Docs/FileFormats.md` was not found in the default branches of those repositories.

The proposed configurations below preserve the existing Engine and Honour-War ignore rules and extend them. They do not replace or alter existing compiler implementation files.

---

# 1. Complete accepted-format list

There are two categories: native Sharnou formats and supported interoperable asset formats.

## 1.1 Native Sharnou custom formats

The following four extensions are initially accepted.

| Extension | Official name | Purpose | Encoding |
|---|---|---|---|
| `.sharnou` | Sharnou Source | Sharnou programming-language source code | UTF-8 without BOM |
| `.sharnouproj` | Sharnou Project | Project, build, and IDE configuration | UTF-8 without BOM |
| `.sharnoumeta` | Sharnou Metadata | Metadata, resource properties, and classifications | UTF-8 without BOM |
| `.sharnouasset` | Sharnou Asset Descriptor | Asset descriptors, references, and manifests | UTF-8 without BOM |

These are the only initially accepted custom Sharnou extensions.

Other `.sharnou*` extensions are not automatically accepted. They must go through the format-addition process described below.

### A. `.sharnou` - Programming-language source

Purpose:

- Compiler input.
- Engine implementation.
- IDE implementation.
- Game logic.
- Functions and modules.
- Classes and future language constructs.
- Runtime and rendering code.

Example:

```text
fn calculate_damage(base, multiplier) {
    let result = base * multiplier;
    return result;
}

fn main() {
    let damage = calculate_damage(100, 3);
    print(damage);
}
```

Rules:

- UTF-8 without BOM.
- LF line endings.
- One final newline.
- Source imports must resolve to valid project or module paths.
- Unsupported language features must produce explicit diagnostics.
- No binary payloads embedded in source files.
- Compiler language compatibility must be explicit.
- No silent interpretation of unknown syntax.

### B. `.sharnouproj` - Project and IDE configuration

Purpose:

- Project identity.
- Startup source selection.
- Compiler configuration.
- Engine configuration.
- Source and module roots.
- Asset roots.
- Target architecture.
- Build profiles.

The initial schema uses strict JSON syntax with the `.sharnouproj` extension.

Example:

```json
{
  "formatVersion": "1.0.0",
  "project": {
    "name": "Honour War",
    "id": "honour-war"
  },
  "languageVersion": "1.0",
  "target": {
    "platform": "windows",
    "architecture": "x64"
  },
  "entryPoint": "src/main.sharnou",
  "sourceRoots": [
    "src"
  ],
  "moduleRoots": [
    "src",
    "StdLib"
  ],
  "assetRoots": [
    "Assets"
  ]
}
```

Rules:

- Strict JSON syntax.
- UTF-8 without BOM.
- LF line endings.
- Explicit `formatVersion`.
- Relative paths.
- No machine-specific absolute paths.
- No credentials or personal secrets.
- Reject unsupported required configuration features.

### C. `.sharnoumeta` - Metadata and resource properties

Purpose:

- Resource identity.
- Resource classification.
- Display names.
- Tags.
- Properties.
- Version information.
- Resource dependencies.

Example:

```json
{
  "formatVersion": "1.0.0",
  "resourceId": "warrior_hero_001",
  "resourceType": "character",
  "displayName": "Warrior Hero",
  "properties": {
    "category": "character",
    "tier": 1,
    "enabled": true
  },
  "tags": [
    "warrior",
    "hero"
  ]
}
```

Rules:

- Strict JSON syntax.
- UTF-8 without BOM.
- LF line endings.
- Explicit metadata schema version.
- Stable resource identifiers.
- No embedded binary files.
- References to resources must resolve.
- Unsupported required metadata features must be rejected.

### D. `.sharnouasset` - Asset descriptors and manifests

Purpose:

- Describe 3D models.
- Describe material textures.
- Associate textures with models.
- Describe UI images.
- Record asset dependencies.
- Record file hashes.
- Validate asset completeness.

Example:

```json
{
  "formatVersion": "1.0.0",
  "assetId": "warrior_hero_001",
  "assetType": "character",
  "files": [
    {
      "role": "scene",
      "path": "Models/warrior_hero.glb",
      "format": "glb",
      "sha256": "<64-character SHA-256>"
    },
    {
      "role": "texture",
      "path": "Textures/warrior_hero.ktx2",
      "format": "ktx2",
      "sha256": "<64-character SHA-256>"
    },
    {
      "role": "preview",
      "path": "Previews/warrior_hero.avif",
      "format": "avif",
      "sha256": "<64-character SHA-256>"
    }
  ]
}
```

Rules:

- Strict JSON syntax.
- UTF-8 without BOM.
- LF line endings.
- Explicit asset schema version.
- Relative asset paths.
- SHA-256 integrity verification.
- Asset paths must not escape their declared root.
- Missing dependencies must fail validation.
- The descriptor does not contain the actual binary asset payload.

---

## 1.2 Supported interoperable asset formats

These are established asset formats, not custom Sharnou file formats.

| Extension | Format | Assigned responsibility | Git treatment |
|---|---|---|---|
| `.gltf` | glTF 2.0 JSON | 3D scene descriptions | Text |
| `.glb` | Binary glTF 2.0 | Combined 3D scene and resources | Binary |
| `.ktx2` | KTX2 / Basis Universal | 3D material textures | Binary |
| `.avif` | AVIF | 2D and UI images | Binary |

### Asset-format rules

**glTF/GLB**

- Used for 3D scenes, models, skeletons, animations, and associated scene resources.
- glTF JSON must be valid and use the supported glTF version.
- GLB must pass binary container validation.
- Referenced external resources must resolve.
- Scene and material references must be validated.

**KTX2**

- Used for 3D material textures.
- Basis Universal content is supported.
- The `KHR_texture_basisu` extension must be correctly declared when used.
- Required extension declarations must match the actual texture references.
- The KTX2 header and level index must pass validation.

**AVIF**

- Used for 2D images and UI assets.
- Must pass AVIF/ISO-BMFF structural validation.
- Dimensions and decoder resource limits must be checked.
- AVIF must not silently substitute for an unsupported 3D texture format.

The four custom Sharnou formats describe and organize these assets. They do not replace glTF, GLB, KTX2, or AVIF.

---

# 2. Complete format-governance rules

## Rule 1 - Format registration

Every accepted format must have a registered specification.

Registration must identify:

1. Extension.
2. Official name.
3. Purpose.
4. Encoding.
5. File structure.
6. Versioning.
7. Parser or decoder requirements.
8. Integrity rules.
9. Compatibility requirements.
10. Owning component.

No new custom extension becomes accepted merely because a file has been created with that extension.

## Rule 2 - Encoding

All text formats use:

- UTF-8 encoding.
- No UTF-8 BOM.
- LF line endings.
- One final newline.
- No NUL bytes.
- No mixed line endings.

The initial compiler may have more restrictive lexical capabilities than UTF-8 as a container encoding. Language-level Unicode support must not be assumed until implemented and tested.

The four accepted custom formats must not contain hidden binary payloads.

## Rule 3 - Strict parsing

Consumers must validate file contents before using them.

Examples:

| File | Required validation |
|---|---|
| `.sharnou` | Lexer, parser, semantic analysis |
| `.sharnouproj` | JSON parsing and project schema validation |
| `.sharnoumeta` | JSON parsing and metadata schema validation |
| `.sharnouasset` | JSON parsing, asset-reference and hash validation |

Invalid files must produce actionable diagnostics.

A consumer must not silently repair malformed files and continue as though the original file were valid.

## Rule 4 - Path security

All referenced project, module, metadata, and asset paths must:

- Use relative paths.
- Use forward slashes in serialized documents.
- Resolve inside declared project or asset roots.
- Reject path traversal outside the root.
- Reject unintended absolute paths.
- Be validated before opening a file.
- Preserve the canonical spelling and capitalization of repository paths.

Different files must not silently alias the same resource through conflicting path spellings.

## Rule 5 - Deterministic integrity

SHA-256 is the required integrity algorithm.

Each binary asset referenced by `.sharnouasset` must have:

- A declared relative path.
- A format identifier.
- Its actual file size.
- Its SHA-256 digest.
- Its role within the resource.

The hash must be recalculated from the actual bytes.

A declared hash is not proof that an asset is valid; structural validation is also required.

## Rule 6 - Versioning

Every custom descriptor format uses a `formatVersion` field.

The initial version is:

```json
"formatVersion": "1.0.0"
```

Versioning follows this policy:

| Version change | Meaning | Compatibility |
|---|---|---|
| Major | Breaking structure or meaning | Requires explicit migration |
| Minor | Backward-compatible optional additions | Older readers may ignore optional additions |
| Patch | Clarification or non-structural correction | No structural change |

A missing or unsupported major version must fail closed.

The `.sharnou` language version is selected through the project's `languageVersion` setting. A compiler must reject an unsupported language version rather than interpreting it using a different grammar.

## Rule 7 - Compatibility

The following responsibilities apply:

| Component | Required compatibility |
|---|---|
| Sharnou Compiler | Reads `.sharnou`; validates project configuration and module imports |
| Sharnou IDE | Reads and writes `.sharnouproj`; edits `.sharnou`; manages metadata and asset descriptors |
| Sharnou Engine | Reads supported metadata and asset descriptors; validates referenced assets |
| Honour War | Uses supported project, source, metadata, and asset formats |

A format change must not silently break another component.

Before a new format version is accepted, the relevant consumer implementations and test fixtures must be identified.

## Rule 8 - Binary handling

Binary formats must have explicit structural documentation.

At minimum, documentation must define:

- Magic/signature or identification fields.
- Container version.
- Header structure.
- Byte order where applicable.
- File-size and section-length rules.
- Offset and alignment rules.
- Resource bounds.
- Dependency references.
- Integrity validation.
- Invalid-file rejection behavior.

Examples:

| Format | Structural validation |
|---|---|
| GLB | Header magic, version, declared file length, chunk boundaries |
| KTX2 | Identifier, header, level index, offsets, lengths |
| AVIF | ISO-BMFF box structure, valid AVIF brands, payload bounds |
| PE32+ | DOS/PE headers, machine type, sections, directories, imports and relocations |

A file extension alone must never be treated as evidence of a valid binary format.

## Rule 9 - Generated executable protection

Generated compiler and runtime outputs must not be treated as source code.

Protected generated-artifact extensions include:

```text
.exe
.dll
.pdb
.obj
.lib
.ilk
.exp
.pch
.ipdb
.iobj
.o
.a
.so
.dylib
```

These artifacts must:

- Normally be excluded through `.gitignore`.
- Not be added as ordinary source files.
- Be validated before release.
- Be distributed through an approved GitHub Release or artifact process when needed.
- Have SHA-256 records in release manifests.

Important: `.gitignore` does not remove an already-tracked file. Existing tracked binaries require explicit inventory and approval before any removal or migration.

## Rule 10 - Asset preservation

The binary asset formats `.glb`, `.ktx2`, and `.avif` are not generated compiler executables.

They are valid source assets and must not be excluded by the general native-build ignore rules.

Their binary treatment is controlled through `.gitattributes`.

Large binary assets may use Git LFS later, subject to explicit approval. Git LFS is not required for the four initial custom text formats.

## Rule 11 - Testing

Every registered format must have positive and negative test cases.

Positive tests must cover valid files and supported features.

Negative tests must cover:

- Missing required fields.
- Incorrect versions.
- Invalid encoding.
- Invalid signatures.
- Truncated files.
- Out-of-range offsets.
- Missing dependencies.
- Hash mismatches.
- Unsupported required features.
- Path traversal attempts.

Tests must verify that invalid input is rejected and that a failed validation does not produce a misleading success state.

## Rule 12 - Format extension process

A new custom format requires:

1. A written proposal.
2. A registered extension and ownership.
3. A documented versioned structure.
4. Encoding rules.
5. Validation rules.
6. Integrity rules.
7. Compatibility requirements.
8. Positive and negative test fixtures.
9. Consumer implementation references.
10. Explicit approval before repository changes.

Existing accepted formats must not be silently reinterpreted to accommodate a new feature.

## Rule 13 - Immutable accepted baseline

The governance work must not alter:

- Accepted R2-e Fix1 compiler.
- Accepted R2-e Fix1 PE verifier.
- R2-f compatibility stream.
- Any accepted regression test.
- Any pinned SHA-256 hash.

No mass reformatting, renaming, conversion, replacement, or automatic regeneration of those files is permitted.

The proposed configuration also deliberately avoids global Git text-normalization rules that could unexpectedly affect protected files.

---

# 3. Exact `.gitattributes` contents

The same proposed `.gitattributes` file is used in all four repositories.

The file intentionally does **not** contain a global `* text=auto` rule. This is important because existing accepted compiler and verifier files may be covered by pinned hashes.

Only the explicitly named formats receive normalization rules.

## Sharnou-Compiler

Path:

```text
.gitattributes
```

## Sharnou-IDE

Path:

```text
.gitattributes
```

## Sharnou-Engine

Path:

```text
.gitattributes
```

## Honour-War

Path:

```text
.gitattributes
```

### Exact complete contents for all four repositories

```gitattributes
# Sharnou native text formats.
*.sharnou text eol=lf
*.sharnouproj text eol=lf
*.sharnoumeta text eol=lf
*.sharnouasset text eol=lf

# Shared format-governance document.
Docs/FileFormats.md text eol=lf

# glTF 2.0 is JSON text.
*.gltf text eol=lf

# Accepted binary 3D and image asset formats.
*.glb binary
*.ktx2 binary
*.avif binary

# Generated native executable and development artifacts.
*.exe binary
*.dll binary
*.pdb binary
*.obj binary
*.lib binary
*.ilk binary
*.exp binary
*.pch binary
*.ipdb binary
*.iobj binary
*.o binary
*.a binary
*.so binary
*.dylib binary

# Binary archives and release packages.
*.zip binary
*.7z binary
```

### Important preservation property

No extension-wide rule is being added for `.ps1`.

That avoids unintentionally normalizing the accepted R2-e Fix1 compiler, PE verifier, or regression scripts merely because a new governance file was introduced.

The new custom Sharnou file types are normalized explicitly.

---

# 4. Exact `.gitignore` contents

The four repositories have different build and cache requirements. Their ignore files must therefore be different.

The Compiler and IDE repositories currently have no root `.gitignore` in their inspected default branches.

The Engine and Honour-War versions below preserve the existing entries and add the missing generated-native-artifact protections.

## 4.1 Sharnou-Compiler

Repository:

```text
Sharnou/Sharnou-Compiler
```

Path:

```text
.gitignore
```

Complete proposed contents:

```gitignore
# Generated compiler builds.
/Build/
/out/
/artifacts/
/TestResults/

# Local temporary and cache directories.
/.cache/
/tmp/
/temp/

# Compiler logs and temporary files.
*.log
*.tmp
*.bak

# Generated native executable and compiler artifacts.
*.exe
*.dll
*.pdb
*.obj
*.lib
*.ilk
*.exp
*.pch
*.idb
*.ipdb
*.iobj
*.o
*.a
*.so
*.dylib

# Local IDE and editor files.
.vs/
.idea/
*.user
*.suo
*.VC.db
*.VC.opendb

# Operating-system files.
Thumbs.db
Desktop.ini
```

The following remain permitted:

```text
.sharnou
.sharnouproj
.sharnoumeta
.sharnouasset
.ps1
.md
```

Compiler regression fixtures and source-controlled reference hashes are not excluded.

## 4.2 Sharnou-IDE

Repository:

```text
Sharnou/Sharnou-IDE
```

Path:

```text
.gitignore
```

Complete proposed contents:

```gitignore
# Generated IDE and compiler builds.
/Build/
/out/
/artifacts/
/TestResults/

# IDE caches and temporary state.
/.cache/
/Cache/
/Temp/
/temp/
/tmp/

# Generated logs.
Logs/
*.log
*.tmp
*.bak

# Generated native executables and libraries.
*.exe
*.dll
*.pdb
*.obj
*.lib
*.ilk
*.exp
*.pch
*.idb
*.ipdb
*.iobj
*.o
*.a
*.so
*.dylib

# Local IDE and editor state.
.vs/
.idea/
*.user
*.suo
*.VC.db
*.VC.opendb

# Per-user Sharnou project state.
*.sharnouproj.user

# Operating-system files.
Thumbs.db
Desktop.ini
```

The `.sharnouproj` project configuration itself remains source-controlled. Only its per-user local state is ignored.

## 4.3 Sharnou-Engine

Repository:

```text
Sharnou/Sharnou-Engine
```

Path:

```text
.gitignore
```

This version preserves the existing Engine rules.

Complete proposed contents:

```gitignore
# Visual Studio / CMake
.vs/
CMakeUserPresets.json
CMakeFiles/
CMakeCache.txt
cmake_install.cmake
Makefile
build/
out/
install/
*.sln
*.vcxproj
*.vcxproj.filters
*.user

# Generated native executable and libraries
*.exe
*.dll
*.lib
*.pdb
*.ilk
*.obj
*.ipdb
*.iobj
*.exp
*.pch
*.idb
*.o
*.a
*.so
*.dylib

# Toolchain and package-generated outputs
vcpkg_installed/

# Engine runtime and local state
Saved/
Logs/
CrashDumps/

# Sharnou build and validation outputs
Build/
artifacts/
TestResults/
.cache/
Temp/
temp/
tmp/

# Temporary files
*.log
*.tmp
*.bak

# Operating-system files
Thumbs.db
Desktop.ini
```

One consideration: the proposed `Build/` rule is broader than the original Engine ignore rules. It should be applied only after confirming that the Engine repository does not currently use tracked source files under that directory.

If any tracked source or reference file exists there, the narrower version should be used:

```gitignore
Build/Runtime/
Build/Artifacts/
Build/Temp/
```

The broad rule is therefore marked **requiring path inventory before approval**.

## 4.4 Honour-War

Repository:

```text
Sharnou/Honour-War
```

Path:

```text
.gitignore
```

This version preserves all existing Honour-War ignore entries.

Complete proposed contents:

```gitignore
# Sharnou Engine / Visual Studio generated files
.vs/
*.suo
*.user
*.opensdf
*.sdf
*.VC.db
*.VC.opendb
*.pdb
*.obj

# Additional generated native artifacts
*.exe
*.dll
*.lib
*.ilk
*.exp
*.pch
*.idb
*.ipdb
*.iobj
*.o
*.a
*.so
*.dylib

# Native engine build outputs
Engine/SharnouEngine/out/
Build/SharnouEngine/
Build/Windows/
Build/Runtime/

# Legacy / engine cache artifacts
Binaries/
Intermediate/
Saved/
DerivedDataCache/

# Sharnou compiler and IDE local outputs
Build/Compiler/
Build/IDE/
artifacts/
TestResults/
.cache/
Temp/
temp/
tmp/

# Logs and temporary files
Logs/
CrashDumps/
*.log
*.tmp
*.bak

# Operating-system files
Thumbs.db
Desktop.ini
```

**Asset protection:** This file deliberately does not ignore:

```text
*.gltf
*.glb
*.ktx2
*.avif
*.sharnou
*.sharnouproj
*.sharnoumeta
*.sharnouasset
```

Those are eligible source or asset files, subject to their respective validation rules.

---

# 5. Complete initial `Docs/FileFormats.md`

This is the proposed complete document.

The same contents are intended for all four repositories, with the Compiler repository serving as the canonical master.

# Sharnou File-Format Governance

**Document ID:** SHARNOU-FORMATS-001  
**Document Version:** 1.0.0  
**Policy Status:** Initial proposal pending approval  
**Encoding:** UTF-8 without BOM  
**Line Endings:** LF  

## 1. Purpose

This document defines the accepted file formats, encoding requirements, structural validation, integrity, versioning, compatibility, and repository governance rules for the Sharnou toolchain and its projects.

It applies to:

- Sharnou Compiler
- Sharnou IDE
- Sharnou Engine
- Honour War

The purpose is to establish a consistent format contract between the compiler, IDE, Engine, and game.

A file extension alone does not establish that a file is valid. Every accepted file must pass the appropriate parser, schema validator, structural validator, or binary decoder.

## 2. Accepted Native Sharnou Formats

The initial accepted custom formats are:

| Extension | Format Name | Purpose |
|---|---|---|
| `.sharnou` | Sharnou Source | Programming-language source |
| `.sharnouproj` | Sharnou Project | Project and IDE configuration |
| `.sharnoumeta` | Sharnou Metadata | Metadata and resource properties |
| `.sharnouasset` | Sharnou Asset Descriptor | Asset descriptors and manifests |

No additional custom Sharnou extension is accepted by default.

Additional extensions require an explicit format proposal, documented structure, validator, compatibility rules, and approval.

## 3. Sharnou Source: .sharnou

`.sharnou` is the native programming-language source format.

It is consumed by the Sharnou Compiler and edited by the Sharnou IDE.

Permitted content includes:

- Functions and modules.
- Variables and assignments.
- Expressions and arithmetic.
- Conditional statements.
- Loops.
- Imports.
- Engine code.
- Game code.
- Runtime and rendering code.

Requirements:

- UTF-8 without BOM.
- LF line endings.
- One final newline.
- No embedded binary payloads.
- Valid language grammar.
- Valid imports and symbol references.
- Explicit language-version compatibility through the project configuration.

Unsupported syntax must be rejected with source-location diagnostics.

A compiler must not silently reinterpret unsupported syntax.

## 4. Project Configuration: .sharnouproj

`.sharnouproj` is the native project and IDE configuration format.

The initial version uses strict JSON syntax.

Required properties include:

- `formatVersion`
- `project`
- `languageVersion`
- `target`
- `entryPoint`
- `sourceRoots`
- `moduleRoots`
- `assetRoots`

Example:

    {
      "formatVersion": "1.0.0",
      "project": {
        "name": "Honour War",
        "id": "honour-war"
      },
      "languageVersion": "1.0",
      "target": {
        "platform": "windows",
        "architecture": "x64"
      },
      "entryPoint": "src/main.sharnou",
      "sourceRoots": [
        "src"
      ],
      "moduleRoots": [
        "src",
        "StdLib"
      ],
      "assetRoots": [
        "Assets"
      ]
    }

The parser must reject malformed JSON, missing required properties, invalid target values, and unsupported required features.

Project paths must be relative to the project root.

Machine-specific absolute paths and secrets must not be stored in project files.

## 5. Metadata: .sharnoumeta

`.sharnoumeta` stores metadata and resource properties.

The initial version uses strict JSON syntax.

Required properties:

- `formatVersion`
- `resourceId`
- `resourceType`
- `properties`

Optional properties may include:

- `displayName`
- `tags`
- `dependencies`
- `author`
- `description`
- `version`

Example:

    {
      "formatVersion": "1.0.0",
      "resourceId": "warrior_hero_001",
      "resourceType": "character",
      "displayName": "Warrior Hero",
      "properties": {
        "category": "character",
        "tier": 1,
        "enabled": true
      },
      "tags": [
        "warrior",
        "hero"
      ]
    }

Resource identifiers must be stable within their project.

Metadata files must not contain embedded executable payloads or binary asset contents.

## 6. Asset Descriptors: .sharnouasset

`.sharnouasset` describes assets and their dependencies.

The initial version uses strict JSON syntax.

Required properties:

- `formatVersion`
- `assetId`
- `assetType`
- `files`

Each file entry must declare:

- `role`
- `path`
- `format`
- `sha256`

The SHA-256 field must contain exactly 64 hexadecimal characters.

Example:

    {
      "formatVersion": "1.0.0",
      "assetId": "warrior_hero_001",
      "assetType": "character",
      "files": [
        {
          "role": "scene",
          "path": "Models/warrior_hero.glb",
          "format": "glb",
          "sha256": "<64-character SHA-256>"
        },
        {
          "role": "texture",
          "path": "Textures/warrior_hero.ktx2",
          "format": "ktx2",
          "sha256": "<64-character SHA-256>"
        },
        {
          "role": "preview",
          "path": "Previews/warrior_hero.avif",
          "format": "avif",
          "sha256": "<64-character SHA-256>"
        }
      ]
    }

Asset descriptors reference files. They do not embed the actual binary file contents.

Every referenced file must exist and pass its integrity and structural checks.

## 7. Encoding and Text Normalization

All four native Sharnou formats use:

- UTF-8.
- No byte-order mark.
- LF line endings.
- One final newline.
- No NUL bytes.

JSON-based formats must not use:

- Comments.
- Duplicate object keys.
- Trailing commas.
- Invalid escape sequences.
- Invalid JSON values.

The `.sharnou` language uses the grammar and character support implemented by the declared compiler language version.

File encoding support must not be confused with language-level Unicode support.

## 8. Path Rules

Serialized paths must:

- Be relative.
- Use `/` as the separator.
- Resolve within a declared project or asset root.
- Avoid path traversal outside that root.
- Use canonical repository capitalization.
- Resolve to existing files when required by the consuming operation.

Consumers must validate paths before opening files.

Absolute paths and unintended external file references must be rejected.

## 9. Versioning

Every JSON-based custom descriptor contains a `formatVersion`.

The initial version is:

    "formatVersion": "1.0.0"

Version semantics:

- Major: incompatible structural or semantic change.
- Minor: backward-compatible optional addition.
- Patch: clarification or non-structural correction.

Consumers must reject unsupported major versions.

Unsupported required features must never be silently ignored.

The Sharnou language version is declared by the project configuration.

## 10. Compatibility

The Sharnou Compiler must:

- Parse `.sharnou`.
- Validate the declared language version.
- Resolve project and module imports.
- Reject unsupported syntax and required features.

The Sharnou IDE must:

- Read and write `.sharnouproj`.
- Edit `.sharnou`.
- Manage `.sharnoumeta`.
- Manage `.sharnouasset`.

The Sharnou Engine must:

- Consume supported metadata.
- Resolve asset descriptors.
- Validate asset files.
- Reject unsupported asset features.

Honour War must use only supported formats and versions.

A format change must identify every affected consumer and its compatibility test.

## 11. Interoperable Asset Formats

The following established formats are accepted as asset payload formats.

They are not custom Sharnou formats.

### 11.1 glTF

Extension: `.gltf`

Purpose:

- 3D scenes.
- Meshes.
- Nodes.
- Materials.
- Skeletons.
- Animations.
- Scene references.

`.gltf` is textual JSON and must use LF line endings.

The asset version and required extensions must be validated.

### 11.2 Binary glTF

Extension: `.glb`

Purpose:

- Binary glTF 2.0 scene delivery.
- Combined scene and resource payloads.

`.glb` is binary.

Validation must include:

- Magic identifier.
- Container version.
- Declared total length.
- Chunk boundaries.
- Chunk lengths.
- Referenced resource validity.

### 11.3 KTX2

Extension: `.ktx2`

Purpose:

- 3D material textures.
- Basis Universal texture delivery.
- GPU-oriented texture resources.

The KTX2 identifier, header, dimensions, level index, offsets, and payload bounds must be validated.

When used through glTF, `KHR_texture_basisu` declarations and references must be consistent.

### 11.4 AVIF

Extension: `.avif`

Purpose:

- 2D images.
- UI images.
- Previews.
- Icons and presentation graphics.

AVIF must pass ISO-BMFF container validation.

The file must have valid AVIF-compatible brand declarations and valid box boundaries.

AVIF is not a substitute for KTX2 material textures.

## 12. Binary Handling

Binary data must not be processed as text.

The following formats require binary handling:

- `.glb`
- `.ktx2`
- `.avif`
- `.exe`
- `.dll`
- `.pdb`
- `.obj`
- `.lib`
- Other generated native artifacts.

Each accepted binary asset format must document:

- Identification/signature.
- Version.
- Header structure.
- Byte order.
- Length and bounds.
- Offsets and alignment.
- Payload structure.
- Maximum resource limits.
- Integrity validation.
- Failure behavior.

A binary parser must reject truncated, malformed, overlapping, or out-of-range structures.

No binary format is accepted solely because a filename has a recognized extension.

## 13. Integrity and SHA-256

SHA-256 is the required integrity algorithm.

Asset descriptors must declare hashes for referenced binary files.

The consumer must calculate the actual hash and compare it with the declared value.

A mismatch must fail validation.

Pinned compiler, verifier, and regression-test hashes are immutable acceptance records.

Format-governance changes must not rewrite or regenerate existing pinned hashes.

## 14. Generated Native Artifacts

Generated native outputs must not be committed as ordinary source.

Protected generated-artifact extensions include:

- `.exe`
- `.dll`
- `.pdb`
- `.obj`
- `.lib`
- `.ilk`
- `.exp`
- `.pch`
- `.ipdb`
- `.iobj`
- `.o`
- `.a`
- `.so`
- `.dylib`

Generated binaries must normally be excluded through `.gitignore`.

Release artifacts may be attached to GitHub Releases or handled through a separately approved artifact process.

Existing tracked files are not automatically removed by `.gitignore`.

Any tracked binary inventory requires review before modification.

## 15. Git Attributes and Ignore Rules

The four repositories must receive the approved `.gitattributes` and `.gitignore` configuration.

Text normalization is explicitly assigned to the four custom text extensions, glTF JSON, and the shared format-governance document.

Binary asset and executable formats must have binary Git attributes.

The accepted `.glb`, `.ktx2`, and `.avif` source assets must not be excluded by general native-output ignore rules.

Generated native executables and intermediate build files must be excluded.

No global normalization rule may be introduced without reviewing its effect on protected files.

## 16. Git LFS

Git LFS is not required for the four initial custom text formats.

The following are binary assets:

- `.glb`
- `.ktx2`
- `.avif`

They may be stored directly in Git when repository policy permits.

Git LFS may be considered for large binary assets after explicit approval.

No Git LFS tracking rule is implied by this document.

Generated `.exe`, `.dll`, `.pdb`, `.obj`, and `.lib` files must not be added to LFS as a substitute for keeping generated artifacts out of source control.

## 17. Validation Requirements

Every format must have positive and negative tests.

Positive tests must cover valid structures and supported features.

Negative tests must cover malformed structures, invalid versions, missing fields, invalid references, corrupt binaries, and hash mismatches.

Every validator must fail closed.

A failed validation must not create a false success result or publish a partially validated resource.

## 18. New Format Approval

A new custom format requires:

1. Written proposal.
2. Extension registration.
3. Purpose and ownership.
4. Encoding rules.
5. Structural specification.
6. Versioning rules.
7. Compatibility rules.
8. Integrity rules.
9. Validator implementation.
10. Positive tests.
11. Negative tests.
12. Consumer integration.
13. Explicit approval.

The extension must not become accepted until its required documentation and validation are available.

## 19. Frozen Baseline Protection

This format-governance policy does not authorize modification of:

- The accepted R2-e Fix1 compiler.
- The accepted R2-e Fix1 PE verifier.
- The R2-f compatibility stream.
- Any accepted regression test.
- Any pinned SHA-256 hash.

No existing accepted source, executable test fixture, verifier, compatibility stream, or pinned hash may be rewritten, deleted, renamed, reformatted, or regenerated as part of this initial governance proposal.

Any future change affecting a frozen acceptance artifact requires its own explicit approval and compatibility decision.

## 20. Repository Distribution

The canonical policy document is maintained in:

    Sharnou/Sharnou-Compiler/Docs/FileFormats.md

Identical copies are maintained in:

    Sharnou/Sharnou-IDE/Docs/FileFormats.md
    Sharnou/Sharnou-Engine/Docs/FileFormats.md
    Sharnou/Honour-War/Docs/FileFormats.md

All copies must have identical content and SHA-256.

A policy change must update the canonical document and all approved mirrors as one coordinated change.

No repository may silently adopt a different format rule.

## 21. Change Control

This document is an initial proposal.

It does not authorize:

- Commits.
- Branch creation.
- Pull requests.
- Releases.
- File replacements.
- Compiler or verifier modifications.
- Regression-test modifications.
- Pinned hash changes.

Implementation begins only after explicit approval.

**End of policy.**

---

# 6. Repository distribution matrix

The intended distribution is:

| File | Compiler | IDE | Engine | Honour-War |
|---|---:|---:|---:|---:|
| `.gitattributes` | Yes | Yes | Yes | Yes |
| `.gitignore` | Yes | Yes | Yes | Yes |
| `Docs/FileFormats.md` | Canonical | Identical mirror | Identical mirror | Identical mirror |
| Custom format validators | Compiler-owned | IDE integration | Engine integration | Game integration |
| Format test fixtures | Yes | Yes | Yes | Yes |
| Asset structure documentation | Shared | Shared | Shared | Shared |

The compiler repository is the canonical policy source.

The mirrors must be byte-for-byte identical.

The repositories should not invent local variations in their definitions of the four custom formats.

---

# 7. Binary handling and GitHub/LFS configuration

## Initial requirements

| Format | Text or binary | Git LFS required? | Special handling |
|---|---|---|---|
| `.sharnou` | Text | No | UTF-8, no BOM |
| `.sharnouproj` | Text | No | Strict JSON |
| `.sharnoumeta` | Text | No | Strict JSON |
| `.sharnouasset` | Text | No | Strict JSON and asset hashes |
| `.gltf` | Text | No | JSON/glTF validation |
| `.glb` | Binary | No | Binary container validation |
| `.ktx2` | Binary | No | KTX2 structural validation |
| `.avif` | Binary | No | ISO-BMFF/AVIF validation |
| `.exe` | Binary | No | Generated output; exclude from source |
| `.dll` | Binary | No | Generated output; exclude from source |
| `.pdb` | Binary | No | Generated debug output; exclude from source |
| `.obj` | Binary | No | Generated native object; exclude from source |
| `.lib` | Binary | No | Generated native library; exclude from source |

### GitHub configuration decision

**No Git LFS configuration is required for the initial proposal.**

The four custom formats are small text files.

The four asset/interchange formats have explicit binary handling in `.gitattributes`.

LFS can be introduced later for large asset payloads, but only with approval. No LFS filters or pointer files should be introduced during the initial governance setup.

### Release-artifact policy

Generated binaries should normally be distributed using:

- GitHub Releases.
- An approved build artifact workflow.
- A documented release package.
- A SHA-256 manifest.

They should not be checked into the source tree as compiler or Engine source.

---

# 8. Frozen R2-e Fix1 and R2-f protection

The protection requirements are explicit.

| Protected item | Policy |
|---|---|
| Accepted R2-e Fix1 compiler | Immutable |
| Accepted R2-e Fix1 PE verifier | Immutable |
| R2-f compatibility stream | Immutable |
| Accepted regression tests | Immutable |
| Pinned SHA-256 hashes | Immutable |

Additional safeguards:

1. No automatic formatting.
2. No automatic line-ending conversion of protected PowerShell files.
3. No filename or directory migration.
4. No regenerated compiler or verifier.
5. No replacement of regression fixtures.
6. No hash-manifest regeneration for existing pinned artifacts.
7. No removal of already-tracked binary files without review.
8. No mixing format-governance changes with compiler implementation changes.

The proposed `.gitattributes` deliberately avoids global text normalization and PowerShell-specific conversion rules.

**Confirmation:** I have made no GitHub writes. No protected compiler, PE verifier, compatibility stream, test, or pinned hash has been modified by this work. This is a confirmation of no writes, not a fresh cryptographic audit of every protected artifact.

---

# 9. Final implementation scope

The initial approval would authorize only these new or updated configuration/documentation paths:

| Repository | New or updated paths |
|---|---|
| `Sharnou/Sharnou-Compiler` | `.gitattributes`, `.gitignore`, `Docs/FileFormats.md` |
| `Sharnou/Sharnou-IDE` | `.gitattributes`, `.gitignore`, `Docs/FileFormats.md` |
| `Sharnou/Sharnou-Engine` | `.gitattributes`, `.gitignore`, `Docs/FileFormats.md` |
| `Sharnou/Honour-War` | `.gitattributes`, `.gitignore`, `Docs/FileFormats.md` |

Before applying the Engine `.gitignore`, the broad `Build/` entry must be checked against currently tracked files. If tracked source exists below that directory, the narrower alternative must be used.

No other files are included in this initial change proposal.

## Final status

**FORMAT GOVERNANCE: COMPLETE AS A PROPOSAL - AWAITING YOUR APPROVAL**

The four initial custom formats are defined. The shared governance document is complete. Exact proposed `.gitattributes` and `.gitignore` contents are provided for all four repositories.

No commit, branch, pull request, release, or repository file change has been made.

I will wait for your approval before making any repository changes.