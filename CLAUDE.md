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
- `--only-formulae` — full audit + install + test, on both PRs and pushes to `main` (it builds the bottle the publish job consumes, so it can no longer be PR-only)
- Matrix: `macos-26` and `ubuntu-latest` (in the `ghcr.io/homebrew/brew:main` container). `macos-15-intel` was deliberately dropped from the matrix (see comment in tests.yml) due to unrelated runner-side DNS failures.

### Shipping a new/updated formula version (no `pr-pull`)

Bottles are built and published automatically; there is no `brew pr-pull` label step and no `publish.yml`. To ship a version bump:

1. Branch off `main`.
2. Edit the formula's `url` (point it at the new source tarball, e.g. a new commit-SHA archive) and bump `version`. Leave the existing `bottle do` sha256 lines as-is; CI clobbers them. Keep the `root_url` line.
3. Commit, push the branch, open a PR.
4. CI's `test-bot` matrix builds a bottle per platform and uploads them as artifacts. The `publish-bottles` job then merges every platform's sha256 into the formula with `brew bottle --merge --write --no-commit`, commits the refreshed `bottle do` block **back to the PR branch**, and pushes the OCI blobs to GHCR with `brew pr-upload --upload-only`.
5. Merge the PR normally (a real GitHub merge — the PR shows as **merged**, unlike the old `pr-pull` flow). The same publish job runs again on the push to `main`; if the bottle is already current it is a no-op.
6. `brew upgrade <formula>` then pulls the new bottle from GHCR.

Why this is safe against loops and double-work: the bottle commit in step 4 is pushed with the default `GITHUB_TOKEN`, which GitHub does not let re-trigger a workflow run, so there is no build loop. When nothing changed (e.g. a docs-only push to `main`), `brew bottle --merge` produces no diff and the job self-skips. Order inside the publish job is load-bearing — merge, then commit, then upload — because `brew pr-upload`'s `check_transition_bottles!` re-reads the committed `.rb` and fails if its bottle metadata doesn't match the uploaded blobs.

Fork PRs are skipped by the publish job: CI can't push a bottle commit back to a fork's branch. A maintainer must re-run such a bump from a branch in this repo.

### Bottle hosting (GitHub Packages / GHCR)

Bottles are published to GitHub Packages (GHCR) at `ghcr.io/v2/kylerjensen/tap`, not to GitHub Releases. This is the only Homebrew-supported way to serve bottles that keep working when the tap repo is private: a plain `github.com/.../releases/download/...` URL always resolves to the default unauthenticated `CurlDownloadStrategy` (no `Authorization` header is ever injected, so a private repo 404s), whereas any `ghcr.io/v2/...` URL is auto-detected as the bearer-auth-aware `CurlGitHubPackagesDownloadStrategy`. See issue #13 for the full diagnosis.

How it fits together:

- Each formula's `bottle do` block sets `root_url "https://ghcr.io/v2/kylerjensen/tap"`. The canonical GHCR root lowercases the org and strips the `homebrew-` repo prefix (`kylerjensen/homebrew-tap` becomes `kylerjensen/tap`), mirroring homebrew/core's `ghcr.io/v2/homebrew/core`. No `using:` argument is needed because the URL is auto-detected.
- `tests.yml` `test-bot` job passes `--root-url=https://ghcr.io/v2/kylerjensen/tap` to `--only-formulae` and sets a base64-encoded `HOMEBREW_DOCKER_REGISTRY_TOKEN` so the build/install step can pull already-published dependency bottles.
- `tests.yml` `publish-bottles` job uploads the freshly built bottle to GHCR with `brew pr-upload --upload-only`, authenticated by `HOMEBREW_GITHUB_PACKAGES_USER` / `HOMEBREW_GITHUB_PACKAGES_TOKEN` (both derived from `GITHUB_TOKEN`), and needs the `packages: write` permission. The destination root_url comes from the formula's `bottle do` block, but `--upload-only` still takes an explicit `--root-url` to route to the GHCR uploader.

One-time manual step per formula: the first time CI publishes a bottle for a new formula, GHCR creates the container package **private by default** (it does not inherit repo visibility). To allow unauthenticated `brew install`, flip each package to Public at `github.com/users/kylerjensen/packages/container/<formula>/settings`, and link it to the repo there. If a package is left private, end users must `export HOMEBREW_GITHUB_PACKAGES_AUTH="Bearer <GHCR PAT with read:packages>"` before installing; public packages need no env var.

Current intent: the tap repo is being flipped back to private (the GHCR migration is what makes that safe), but the bottle packages themselves are kept Public so `brew install kylerjensen/tap/<formula>` works without any auth setup.

## Architecture / conventions

Each formula documents *why*, not *what*, in comments — non-obvious constraints (sandbox limits, linking quirks, upstream packaging gaps) are explained inline because the reasoning isn't derivable from reading the DSL alone. Follow this pattern for new formulae/casks: comment the reasoning behind workarounds, not the mechanics of the DSL calls themselves.

Recurring patterns across formulae in this tap:

- **Ad-hoc-signed/unnotarized upstream binaries** (e.g. [kirocc.rb](Formula/kirocc.rb)): strip the quarantine xattr in `install` so Gatekeeper doesn't block first launch, since Homebrew's downloader quarantines fetched tarballs.
- **No native packaging from upstream** (e.g. [ankitcharolia-kiro-gateway.rb](Formula/ankitcharolia-kiro-gateway.rb)): vendor source into `libexec`, create a private venv/dependency install, and write a wrapper launcher script into `bin` rather than relying on Python::Virtualenv or similar helpers that assume a `pyproject.toml`/`setup.py`.
- **Runtime credential/config auto-detection**: formulae that need to discover user credentials at *service start time* (not install time) do so from the launcher script itself, because Homebrew's build sandbox denies filesystem reads outside a fixed allowlist during `install`/`post_install` — see the kiro-gateway launcher script and its `post_install` `.env` handling.
- **Pinning fork commits over tags**: when tracking a fork's `main` branch instead of upstream's tagged releases (because needed fixes land ahead of upstream tags), pin the `url` to a specific commit SHA (not `refs/heads/main`) so the tarball and its `sha256` stay reproducible.
- **`service do` blocks**: formulae exposing a long-running process define a `brew services`-compatible service block (`run`, `keep_alive`, `log_path`/`error_log_path`, `working_dir`) rather than expecting users to run the binary manually.
- **Security-conscious defaults in `caveats`**: formulae that bind to network ports document that they default to loopback-only and explain when/why to set an API key or widen the bind host.
- **`test do` blocks avoid touching `$HOME` or real network/service state** — they assert against `--help`/`--version` output or deterministic early-exit error messages (e.g. missing-credentials validation) rather than exercising real functionality that would mutate user state.

## Formula/cask index

- [Formula/kirocc.rb](Formula/kirocc.rb) — Anthropic Messages API proxy to the Kiro backend; prebuilt multi-arch/multi-OS binary releases.
- [Formula/ankitcharolia-kiro-gateway.rb](Formula/ankitcharolia-kiro-gateway.rb) — OpenAI/Anthropic-compatible proxy gateway for Kiro; vendored Python source + private venv, tracks a fork's `main` via pinned commit SHA.
- [Formula/kiro-gateway.rb](Formula/kiro-gateway.rb) — OpenAI/Anthropic-compatible proxy gateway for Kiro (kylerjensen fork); vendored Python source + private venv, tracks fork's `main` via pinned commit SHA, `brew services`-compatible.
- [Formula/icloud-sync.rb](Formula/icloud-sync.rb) — symlinks `$HOME` directories into iCloud Drive; macOS-only, wraps a pre-bundled Node ESM script.
- [Casks/omlx-app.rb](Casks/omlx-app.rb) — menu bar app cask for the oMLX LLM inference server; per-OS-version download variants, arm64-only.

`audit_exceptions/flat_namespace_allowlist.json` allowlists formulae for `brew audit`'s flat-namespace check.
