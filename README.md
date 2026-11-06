# Sharnou-Compiler

Central versioned database for validated Sharnou compiler packages.

## Current pin

- Release tag: R26.0-R2-R8
- Archive SHA-256: BB9FC1AD8B240D257DB2FB85B896B26CCDF37CC0C36B4E2B3644C2B1DCDB5FC1
- Archive entries: 658
- Frozen bootstrap compiler: Stage0/SharnouCompiler-6A7A-Merged.ps1
- Frozen bootstrap compiler SHA-256: 7D574ED78347FDC5B91FAB84DFBF9EBB15486BA2B4A018555AE58C329F6BB7AF
- Frozen R25-R4 archive SHA-256: CA01AEACB2E35C6E8039E58F15202A01399DAEA3E0A24E7B4D357772C8EF1274

The R26.0-R2-R8 ZIP has been SHA-256 verified in the preparation workspace, but it is not yet attached to a GitHub Release. The release workflow is staged; publication requires placing the exact ZIP under incoming/R26.0-R2-R8/. It then runs the Windows PowerShell 5.1 acceptance runner and publishes the ZIP, checksum, manifest, and changelog as release assets. It refuses to overwrite an existing tag.

## Publish a new validated revision

1. Create incoming/<new-tag>/.
2. Add the complete compiler ZIP, matching .sha256, release-manifest.json, and CHANGELOG.md.
3. Set the manifest release_tag, archive name/hash, entry count, compiler entry path/hash, runner path, and required PASS markers.
4. Push to branch Sharnou-Compiler (or dispatch the workflow with the tag).
5. The workflow validates on Windows PowerShell 5.1, then creates the immutable tag and GitHub Release with all four assets.

Do not change or replace frozen R25-R4 or R26.0-R2-R8 inputs. Later revisions receive new tags.

## Compatibility boundary

R26.0-R2-R8 is a PowerShell bootstrap compiler for the .sharnou source language. It is not a native sharnou-cxx.exe and does not implement a C++ frontend. The current Sharnou Engine repository contains .cpp/.hpp sources; those sources cannot honestly be built by this compiler package yet. Consumer repositories can pin and verify the release, but native Engine/IDE/Game build remains blocked until the sources are ported to supported Sharnou or a Sharnou C++ frontend/native driver is implemented.
