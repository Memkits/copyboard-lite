# Copyboard Lite agent notes

- `calcit.cirru` is the canonical Calcit snapshot. Never edit it with text replacement or `apply_patch`; use `calcit edit`, `calcit tree`, `calcit cursor`, or `calcit config`.
- Before mutating Calcit code, run `calcit docs agents --contract`, confirm the CLI version matches `deps.cirru`, and inspect the target with `calcit query`/`calcit tree show`.
- Keep the Rust HTTP backend and Calcit.js frontend independently runnable. Browser requests must remain CORS-compatible.
- Storage is provided by `worktools/unionid`. Reproduce suspected database defects independently and report confirmed UnionID issues in that repository rather than working around them silently here.
- Before committing, run Rust format, Clippy, tests, Calcit checks/code generation, and the frontend production build.

