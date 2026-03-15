# Contributing

## Build

```
xcodebuild -scheme Cove -derivedDataPath .build build && open .build/Build/Products/Debug/Cove.app
```

Or open `Cove.xcodeproj` in Xcode (Cmd+B). Requires macOS 15+.

## Rules

- Everything goes through `DatabaseBackend`. No backend checks in UI code.
- Swift 6, `@Observable`, native macOS controls, no force-unwraps.
- One concern per file, ~300 line max.
- Adding a backend? See [`DB/README.md`](Cove/DB/README.md).

## Submitting

1. Fork, branch, make changes (one feature/fix per PR).
2. Verify build succeeds.
3. Open a PR with a clear description.
