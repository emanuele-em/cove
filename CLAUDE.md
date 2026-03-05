# Morfeo — Development Guidelines

## What is Morfeo

Morfeo is a GUI database client written in Rust + iced. Alternative to DataGrip and TablePlus.

## Rules

### Code Style
- Write ONLY idiomatic Rust. No C-style patterns, no Java-style patterns.
- Keep code simple. If a solution feels complicated, step back and find a simpler one.
- Do not over-engineer. No premature abstractions, no unnecessary generics, no design patterns "just in case".
- Three lines of similar code is better than a premature abstraction.
- Only add code that is needed right now. Do not build for hypothetical future requirements.

### Structure
- The codebase must be easy to understand for any Rust developer.
- The codebase must be easy to contribute to. Small files, clear naming, obvious organization.
- One concern per file. If a file grows beyond ~300 lines, split it.
- Organize by feature, not by layer.
- Do not add comments for obvious code. Only comment "why", never "what".
- Do not add unnecessary type annotations — let Rust infer where it can.

### Error Handling
- Use `Result` and `?` operator. No `.unwrap()` in production code.
- Keep error types simple. String-based errors are fine when the error is only displayed to the user.
- Only validate at system boundaries (user input, database responses). Trust internal code.

### Dependencies
- Minimal dependencies. Every new crate must justify its existence.
- Prefer the standard library when it's good enough.

### Architecture
- `src/db/` — all database logic. Each backend is one file implementing `DatabaseBackend` trait.
- `src/ui/` — all iced UI components. Each component is one file.
- `src/app.rs` — top-level application state, messages, update, view.
- Adding a new database backend should require ZERO changes to UI code.

## Build & Run

```
cargo build
cargo run
```

## Tech Stack
- Rust (edition 2024)
- iced (GUI framework, with tokio feature)
- sqlx (database driver for PostgreSQL, MySQL)
- async-trait (async trait methods)
