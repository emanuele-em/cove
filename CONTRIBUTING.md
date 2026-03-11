# Contributing

## Quick start

```
xcodebuild -scheme Morfeo -derivedDataPath .build build
open .build/Build/Products/Debug/Morfeo.app
```

Or open `Morfeo.xcodeproj` in Xcode and build (Cmd+B). Requires macOS 15+.

## Architecture

Everything goes through the `DatabaseBackend` protocol. The UI never checks which backend is active — it asks the protocol what's possible and renders accordingly.

**Adding a new backend:**
1. Add a case to `BackendType` in `ConnectionConfig.swift`
2. Implement `DatabaseBackend` in a new `DB/<Backend>/` directory
3. Wire it up in `morfeoConnect()`

See [`DB/README.md`](Morfeo/DB/README.md) for the full guide with a working skeleton.

## Rules

- No `if postgres` / `if scylla` in UI code. Ever.
- Swift 6, structured concurrency, `@Observable`.
- Keep files under ~300 lines. One concern per file.
- Only comment "why", never "what".
- Use native macOS controls. No custom-drawn UI when SwiftUI provides a standard equivalent.
- `throws` + `try`. No force-unwraps.
- Minimal dependencies. Every new package must justify itself.

## Submitting changes

1. Fork and create a branch from `main`.
2. Make your changes. Keep PRs focused — one feature or fix per PR.
3. Verify the build succeeds: `xcodebuild -scheme Morfeo -derivedDataPath .build build`
4. Open a PR with a clear description of what and why.
