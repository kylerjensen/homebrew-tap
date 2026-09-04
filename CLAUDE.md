# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Homebrew tap (`kylerjensen/tap`) containing custom formulae (`Formula/*.rb`) and casks (`Casks/*.rb`). This is not application code — there is no build step; each `.rb` file is a self-contained Homebrew DSL definition installed via `brew install kylerjensen/tap/<name>`.

## Commands

Audit and test a specific formula/cask locally (requires Homebrew installed):

```bash
brew audit --strict --online Formula/<name>.rb
brew style Formula/<name>.rb
brew install --build-from-source Formula/<name>.rb
brew test Formula/<name>.rb
```

Same commands apply to `Casks/<name>.rb` (casks don't have a `test do` block).

CI (`.github/workflows/tests.yml`) runs on every PR and push to `main` via `brew test-bot`:
- `--only-tap-syntax` — Ruby/DSL syntax and style checks across the whole tap
- `--only-formulae` — full audit + install + test, PRs only
- Matrix: `macos-26` and `ubuntu-latest` (in the `ghcr.io/homebrew/brew:main` container). `macos-15-intel` was deliberately dropped from the matrix (see comment in tests.yml) due to unrelated runner-side DNS failures.

Merges to `main` happen via `brew pr-pull` (`.github/workflows/publish.yml`), triggered by adding the `pr-pull` label to a PR — this pulls built bottles and pushes the commit, then deletes the PR branch. Don't push formula bottle commits to `main` directly; let the label-triggered workflow do it.

## Architecture / conventions

Each formula documents *why*, not *what*, in comments — non-obvious constraints (sandbox limits, linking quirks, upstream packaging gaps) are explained inline because the reasoning isn't derivable from reading the DSL alone. Follow this pattern for new formulae/casks: comment the reasoning behind workarounds, not the mechanics of the DSL calls themselves.

Recurring patterns across formulae in this tap:

- **Ad-hoc-signed/unnotarized upstream binaries** (e.g. [kirocc.rb](Formula/kirocc.rb)): strip the quarantine xattr in `install` so Gatekeeper doesn't block first launch, since Homebrew's downloader quarantines fetched tarballs.
- **No native packaging from upstream** (e.g. [kiro-gateway.rb](Formula/kiro-gateway.rb)): vendor source into `libexec`, create a private venv/dependency install, and write a wrapper launcher script into `bin` rather than relying on Python::Virtualenv or similar helpers that assume a `pyproject.toml`/`setup.py`.
- **Runtime credential/config auto-detection**: formulae that need to discover user credentials at *service start time* (not install time) do so from the launcher script itself, because Homebrew's build sandbox denies filesystem reads outside a fixed allowlist during `install`/`post_install` — see the kiro-gateway launcher script and its `post_install` `.env` handling.
- **Pinning fork commits over tags**: when tracking a fork's `main` branch instead of upstream's tagged releases (because needed fixes land ahead of upstream tags), pin the `url` to a specific commit SHA (not `refs/heads/main`) so the tarball and its `sha256` stay reproducible.
- **`service do` blocks**: formulae exposing a long-running process define a `brew services`-compatible service block (`run`, `keep_alive`, `log_path`/`error_log_path`, `working_dir`) rather than expecting users to run the binary manually.
- **Security-conscious defaults in `caveats`**: formulae that bind to network ports document that they default to loopback-only and explain when/why to set an API key or widen the bind host.
- **`test do` blocks avoid touching `$HOME` or real network/service state** — they assert against `--help`/`--version` output or deterministic early-exit error messages (e.g. missing-credentials validation) rather than exercising real functionality that would mutate user state.

## Formula/cask index

- [Formula/kirocc.rb](Formula/kirocc.rb) — Anthropic Messages API proxy to the Kiro backend; prebuilt multi-arch/multi-OS binary releases.
- [Formula/kiro-gateway.rb](Formula/kiro-gateway.rb) — OpenAI/Anthropic-compatible proxy gateway for Kiro; vendored Python source + private venv, tracks a fork's `main` via pinned commit SHA.
- [Formula/icloud-sync.rb](Formula/icloud-sync.rb) — symlinks `$HOME` directories into iCloud Drive; macOS-only, wraps a pre-bundled Node ESM script.
- [Casks/omlx-app.rb](Casks/omlx-app.rb) — menu bar app cask for the oMLX LLM inference server; per-OS-version download variants, arm64-only.

`audit_exceptions/flat_namespace_allowlist.json` allowlists formulae for `brew audit`'s flat-namespace check.
