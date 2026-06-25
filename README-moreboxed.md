# Moreboxed Fork Notes

This document tracks decisions and constraints specific to the `moreboxed/libghostty-spm` fork.

## Supported platforms

We currently only care about **macOS arm64**. The release workflow builds a single-variant `macos-arm64_x86_64` fat binary so local development on Apple Silicon and Intel still works, but the consumer (`moreboxed/moreboxed`) only targets macOS 14+ arm64.

## Swift compiler versioning

The prebuilt Swift xcframeworks are built with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, which emits `.swiftinterface` files. Those interfaces are **compiler-version-sensitive**:

- Binaries built with Swift 6.1.x will fail to import under Swift 6.3.x.
- Binaries built with Swift 6.3.x will fail to import under Swift 6.1.x.

To avoid mismatch errors like:

```
failed to build module 'GhosttyTerminal'; this SDK is not supported by the compiler
(the SDK is built with 'Apple Swift version 6.1.2 ...', while this compiler is
'Apple Swift version 6.3.1 ...')
```

**Keep `libghostty-spm` release builds and `moreboxed/moreboxed` CI on the same macOS runner image and Xcode version.** As of this writing both use `macos-15` with `/Applications/Xcode_16.4.app` and produce Swift 6.3.x interfaces. If either side changes runner images or Xcode versions, verify the Swift compiler version matches before cutting a new release.

We intentionally stay on `macos-15` for the libghostty Zig build: newer runner images (e.g. `macos-26`) ship an SDK that Zig 0.15.2 cannot cross-compile against reliably, producing undefined system symbol errors such as `__availability_version_check`, `_abort`, `_arc4random_buf`, etc.

### Checking the compiler version

In a workflow step or locally:

```bash
swift --version
```

The release workflow also records the compiler version in the generated `.swiftinterface` files inside each xcframework zip.

## Release workflow

- Trigger: manual (`workflow_dispatch`) only.
- Workflow: `.github/workflows/build-macos-arm64.yml`.
- Release tag format: `storage-macos-arm64.<major>.<minor>.<patch>` (auto-incremented).
- Artifacts: six xcframework zips plus `Package.consumer.swift` with URLs and SHA256 checksums.

## Source changes we carry

### `GhosttyThemeCatalog.allThemes` shape

We changed the generated catalog from:

```swift
public extension GhosttyThemeCatalog {
    static let allThemes: [GhosttyThemeDefinition] = [...]
}
```

to:

```swift
public extension GhosttyThemeCatalog {
    static var allThemes: [GhosttyThemeDefinition] { _allThemes }
}

private let _allThemes: [GhosttyThemeDefinition] = [...]
```

This avoids a library-evolution linker error (`unsafeMutableAddressor` missing) when packaging `GhosttyTheme` as a distributable binary framework.

**Upstream reconciliation:** when merging upstream changes, make sure `Script/generate-themes.sh` and `Sources/GhosttyTheme/Themes/ThemeCatalog_Generated.swift` keep this shape. If upstream changes the catalog structure, we need to port the `static var` + `private let` pattern forward.

## Things to watch when merging upstream

- `Package.swift.template` / `Package.swift` binary target URL: we keep our own `storage-macos-arm64.*` release URLs, not upstream's multi-platform storage tags.
- `Script/merge-xcframework.sh`: upstream's flat static-library layout is fine for the `libghostty` C core; our Swift modules are packaged separately by `Script/build-release-xcframeworks.sh`.
- `BUILD_LIBRARY_FOR_DISTRIBUTION` requirements: any new `public static let` of a large value type in a Swift module may need to become a computed `var` backed by an internal `let` before archiving.
- Minimum deployment targets: upstream supports iOS 15+ and macOS 13+. We only consume macOS 14+, so we don't need to validate iOS paths unless we choose to.

## Files added or modified by us

| File | Purpose |
|------|---------|
| `.github/workflows/build-macos-arm64.yml` | Single-platform macOS arm64 release workflow |
| `Script/build-release-xcframeworks.sh` | Build libghostty + Swift module xcframeworks |
| `Script/generate-consumer-manifest.py` | Generate `Package.consumer.swift` for releases |
| `Script/generate-themes.sh` | Patched to emit library-evolution-compatible catalog |
| `Sources/GhosttyTheme/Themes/ThemeCatalog_Generated.swift` | Patched checked-in generated catalog |
| `README-moreboxed.md` | This file |
