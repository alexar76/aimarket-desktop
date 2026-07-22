# Contributing

## Development Setup

### Prerequisites

- Rust (stable) with `cargo`
- Tauri prerequisites for your OS (see https://tauri.app/start/prerequisites/)
- Node.js 18+ (for the web front-end assets, if building the UI)
- A wallet for the AI Market (created during first-launch wizard)

### Getting Started

```bash
# Clone the desktop monorepo (this app lives in apps/local-security-audit)
git clone https://github.com/alexar76/aimarket-desktop.git
cd aimarket-desktop/apps/local-security-audit

# Run tests
cargo test

# Run the app in dev mode
cargo tauri dev

# Production build
cargo tauri build
```

### Local SDK Development

If you are also changing the `aimarket-agent` Rust SDK, use a path dependency in `src-tauri/Cargo.toml`:

```toml
[dependencies]
aimarket-agent = { path = "../../aimarket-sdks/rust" }
```

## Code Style

- Format with `cargo fmt` before committing.
- Lint with `cargo clippy --all-targets -- -D warnings`.
- Prefer explicit error types; avoid `unwrap()`/`expect()` on fallible paths that can be reached at runtime.
- Keep `unsafe` out of application code unless justified with a comment.

## Pull Request Process

1. Create a feature branch from `main`.
2. Make your changes.
3. Run `cargo test` and `cargo clippy` — both must pass.
4. Update documentation if needed.
5. Create a pull request with a clear title and description.
6. A maintainer will review your PR.

## Commit Messages

Follow conventional commits:
- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation
- `test:` — tests
- `refactor:` — code refactoring
- `chore:` — maintenance

## Code of Conduct

Be respectful, constructive, and inclusive. See our full Code of Conduct in the repository root.
