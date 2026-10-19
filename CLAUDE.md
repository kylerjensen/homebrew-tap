# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Homebrew tap (`kylerjensen/tap`) containing custom formulae (`Formula/*.rb`) and casks (`Casks/*.rb`). This is not application code — there is no build step; each `.rb` file is a self-contained Homebrew DSL definition installed via `brew install kylerjensen/tap/<name>`.

The tap is **macOS-only by owner decision** (October 2026): every formula declares `depends_on :macos`, no Linux bottles are built or published, and Linux-specific machinery gets deleted rather than fixed when it misbehaves (litellm's manylinux-wheel/zlib linkage workarounds were the trigger). CI's build matrix is macOS-only; the `publish-bottles` job still runs on an ubuntu runner because that is CI infrastructure, not supported software.

## Commands

Audit and test a specific formula/cask locally (requires Homebrew installed):

```bash
brew style Formula/<name>.rb
brew audit --strict --online kylerjensen/tap/<name>
brew install --build-from-source Formula/<name>.rb
brew test kylerjensen/tap/<name>
```

`brew audit`/`brew test` take the full name, not a path (path arguments are disabled once the tap is installed); they resolve against the *installed* tap copy, so for uncommitted edits the authoritative check is CI's `--only-formulae` audit.

Same commands apply to `Casks/<name>.rb` (casks don't have a `test do` block).

CI (`.github/workflows/tests.yml`) runs on every PR and push to `main` via `brew test-bot`:
- `--only-tap-syntax` — Ruby/DSL syntax and style checks across the whole tap. It runs `brew style <tap>`, `brew readall --aliases --os=all --arch=all <tap>`, and `brew audit --except=installed --tap=<tap>`. Note the middle step loads **every formula under every OS/arch tag, including Linux**, even for `depends_on :macos` formulae, and errors with `Invalid formula (x86_64_linux): ... formula requires at least a URL` if a formula has no top-level `url`. So per-arch darwin downloads must keep a top-level `url` (arm64) with the Intel one as an `on_macos { on_intel { ... } }` override: `brew style`'s `FormulaAudit/ComponentsOrder` rejects `url` inside a *top-level* `on_arm`/`on_intel` block, while nesting under `on_macos` is allowed (and `readall` still needs the top-level one). To check locally, stage the worktree files into the installed tap copy and run those three commands against `kylerjensen/tap` directly; running `brew test-bot --only-tap-syntax` from inside the tap directory is a silent no-op (it early-returns because the tap arg resolves to nil).
- `--only-formulae` — full audit + install + test, on both PRs and pushes to `main` (it builds the bottle the publish job consumes, so it can no longer be PR-only)
- Matrix: `macos-26` only (the tap is macOS-only; the `ubuntu-latest` container leg was dropped in October 2026, and `macos-15-intel` earlier -- see the comments in tests.yml for both).

### Shipping a new/updated formula version (no `pr-pull`)

Bottles are built and published automatically; there is no `brew pr-pull` label step and no `publish.yml`. To ship a version bump:

1. Branch off `main`.
2. Edit the formula's `url` (point it at the new source tarball, e.g. a new commit-SHA archive) and bump `version`. Leave the existing `bottle do` sha256 lines as-is; CI clobbers them. Keep the `root_url` line.
3. Commit, push the branch, open a PR.
4. CI's `test-bot` matrix builds a bottle per platform and uploads them as artifacts. The `publish-bottles` job then merges every platform's sha256 into the formula with `brew bottle --merge --write --no-commit`, commits the refreshed `bottle do` block **back to the PR branch** (as `Update bottles. [skip ci]`), and pushes the OCI blobs to GHCR with `brew pr-upload --upload-only`. Don't push to the branch while that job runs: its commit is made from the tree it checked out, so a push in between gets rebased under it and can be overwritten.
5. Squash-merge the PR (a real GitHub merge — the PR shows as **merged**, unlike the old `pr-pull` flow), with a commit message that leaves out the bot's `[skip ci]` commit (see below). The same publish job runs again on the push to `main`; if the bottle is already current it is a no-op.
6. `brew upgrade <formula>` then pulls the new bottle from GHCR.

Why this is safe against loops and double-work: the bottle commit in step 4 carries `[skip ci]` in its message, so GitHub starts no workflow run for it and there is no build loop. `GITHUB_TOKEN` alone used to guarantee this, but since June 2026 a `github-actions[bot]` push to a PR starts a `pull_request` run that waits for a maintainer's approval; `[skip ci]` keeps that run from being created. The repo allows only squash and rebase merges, and GitHub skips a push whose head commit message contains the marker anywhere. So when squashing, edit the commit message so it doesn't list the bot's `Update bottles. [skip ci]` commit, and don't rebase-merge (that makes the bot commit `main`'s head). Otherwise the push-to-`main` run is skipped, which is harmless only because that run is a no-op when the bottle is current. When nothing changed (e.g. a docs-only push to `main`), `brew bottle --merge` produces no diff and the job self-skips. Order inside the publish job is load-bearing — merge, then commit, then upload — because `brew pr-upload`'s `check_transition_bottles!` re-reads the committed `.rb` and fails if its bottle metadata doesn't match the uploaded blobs.

Fork PRs are skipped by the publish job: CI can't push a bottle commit back to a fork's branch. A maintainer must re-run such a bump from a branch in this repo.

**Mandatory: every source change must change `version` (or the `bottle do` `rebuild`).** Homebrew keys a bottle by `version` + `rebuild` + platform tag, never by the source archive SHA in `url`. If you repoint `url` at a new commit but leave `version` unchanged, the new build collides with the existing GHCR tag: end users get served the stale bottle, and `brew pr-upload` aborts with "already exists!". This applies to maintenance edits of an already-bottled formula too (comment tweaks, dependency stanza changes, the October 2026 macOS-only refactor). One caveat: a `rebuild` bump only takes effect once the formula is on `main`, because `brew bottle` computes `rebuild` from the formula at `origin/HEAD` (same version there means its `rebuild` + 1, otherwise 0) and ignores the `rebuild` line on the PR branch. So within the PR that adds a formula, or for an install change before the first merge, bump `version` instead; a `rebuild` bump there still builds 0, the upload is skipped as "already exists", and the formula ends up with a sha256 GHCR doesn't have (the post-merge push-to-`main` does not repair it either: `bottle-exists.sh` only keys on version+rebuild, so it skips the rebuild and keeps the stale sha, and it took a follow-up PR to fix litellm after #30 merged; see the re-run drift below). This discipline is also what makes the build-skip optimization below correct.

To save CI time, the `test-bot` job skips the from-source rebuild when a bottle for the formula's current `version` already exists on GHCR for that platform (checked per-formula, per-platform via `.github/scripts/bottle-exists.sh` against the OCI image index). So an unchanged-`version` push (a re-run, or the push-to-`main` after merge) reuses the published bottle instead of recompiling; a genuine `version` bump finds no bottle and builds. The upload step passes `--warn-on-upload-failure` so that if it is ever reached with an already-published tag, it warns and skips rather than failing the job.

**Re-run drift: every full-build CI run re-merges fresh sha256s, but only new keys get uploaded.** Bottle tarballs embed build-time `tab.json` metadata, so their sha256 changes on every build even when the formula didn't, and `brew pr-upload` warn-skips a key that was already uploaded in an earlier run. The skip decision is all-or-nothing across the run's changed formulae, so any run where one formula lacks a bottle rebuilds (and re-merges shas for) all of them, including ones whose blobs were already uploaded in a previous run of the same PR. The last run's shas are what merges to `main`, pointing at blobs GHCR never has: `brew install` then dies with "Couldn't find manifest matching bottle checksum" for every affected formula (this broke the whole tap when PR #30 merged). Repair recipe: compare each formula's `bottle do` against what GHCR actually holds; get a pull token from `https://ghcr.io/token?scope=repository:kylerjensen/tap/<formula>:pull&service=ghcr.io` (anonymous works; the packages are public), list `https://ghcr.io/v2/kylerjensen/tap/<formula>/tags/list`, then fetch each `manifests/<tag>` as an OCI index (needs an `Accept: application/vnd.oci.image.index.v1+json` header) and read each manifest entry's `org.opencontainers.image.ref.name` (must match the formula's version+rebuild+platform key, e.g. `264.arm64_tahoe.1`) plus `sh.brew.bottle.digest` (the real bottle sha). If the blob holds the formula's current output, repoint the sha to the digest; if the blob is stale (like the rebuild-0 litellm bottle, published before `litellm init` existed), bump `rebuild` so CI builds a fresh key instead.

### Periodic version bumps for `llama-swap`

`llama-swap` tracks upstream's tagged releases (not a pinned fork commit), and upstream ships frequent, monotonically increasing integer tags (`v264`, `v265`, …). It has no autobump/livecheck wired up, so bumps are manual and periodic. To bump:

1. Find the latest release tag:
   ```bash
   curl -sL https://api.github.com/repos/mostlygeek/llama-swap/releases/latest | grep '"tag_name"'
   ```
2. Fetch that release's checksums and copy the two darwin sha256 values (`darwin_arm64`, `darwin_amd64`):
   ```bash
   curl -sL https://github.com/mostlygeek/llama-swap/releases/download/v<N>/llama-swap_<N>_checksums.txt
   ```
3. In [Formula/llama-swap.rb](Formula/llama-swap.rb), bump `version` to the bare integer, update the `v<N>` / `llama-swap_<N>_` literals in the top-level arm64 `url` (it is spelled out, not interpolated, because `brew style` requires `url` before `version`), and replace both `sha256` lines. The `on_intel` override `url` interpolates `#{version}` and follows automatically. Leave the `bottle do` `root_url` as-is; CI clobbers the bottle sha256s.
4. Follow the normal shipping flow above (branch, PR, CI builds + publishes bottles, merge).

Because the version is a bare integer and the only required source change is `version` + the top-level `url` literals + the two darwin checksums, this is a mechanical, well-specified bump: a good candidate to delegate to a cheaper model, with `brew style` + `brew audit --strict --online` + the CI install/test as the backstop. Watch for upstream changing its release-asset naming or dropping a darwin variant; if that happens the top-level/`on_intel` url/sha structure needs a corresponding edit, which is no longer purely mechanical.

### Periodic version bumps for `litellm`

`litellm` tracks upstream's PyPI releases (BerriAI/litellm ships frequent `1.x.y` versions). There is no autobump or livecheck wired up, so bumps are manual. (There is deliberately no `livecheck` block: `Livecheck::Strategy::Pypi` derives the package name from the URL basename, and the hyphens in the `cp310-abi3` wheel tag make it query a 404ing name.) To bump:

1. Fetch the latest version plus the two macOS `cp310-abi3` wheel URLs and sha256s from the PyPI JSON:
   ```bash
   curl -sL https://pypi.org/pypi/litellm/json | python3 -c "
   import json, sys
   d = json.load(sys.stdin)
   print(d['info']['version'])
   for u in d['urls']:
       if 'cp310-abi3' in u['filename'] and 'macosx' in u['filename']:
           print(u['filename'], u['url'], u['digests']['sha256'])
   "
   ```
2. In [Formula/litellm.rb](Formula/litellm.rb), bump `version` and replace both `url` lines: the `/packages/<hash>/` path segment is a per-file PyPI storage hash that does NOT interpolate, so copy it from the JSON output. In the top-level arm64 `url` the `litellm-<version>-cp310-abi3-macosx_11_0_arm64.whl` filename is a literal too (spell the new version in); in the `on_macos`/`on_intel` override `url` the `litellm-#{version}-cp310-abi3-...` filename part interpolates and only the hash segment needs replacing. Replace the two `sha256` lines (the PyPI digests). Leave the `bottle do` `root_url` as-is; CI clobbers the bottle sha256s.
3. Follow the normal shipping flow above (branch, PR, CI builds + publishes bottles, merge).

This is semi-mechanical (the two `macosx_*` filenames must be matched by hand to the top-level arm64 `url` and the `on_macos`/`on_intel` override `url`), with `brew style` + `brew audit --strict --online` + the CI install/test as the backstop. Watch for upstream changing its wheel platform tags (a newer `macosx_<major>_<minor>` deployment target, a different Python ABI tag) or dropping a darwin wheel; if that happens the top-level/`on_macos` url/sha structure needs a corresponding edit. Also watch the `[proxy]` extra's native dependency tree: the install-time Mach-O fix-up in the formula rewrites the dylib IDs bundled by `psycopg-binary`, so a version that changes that bundle (new/renamed `.dylibs`, or non-`@rpath` IDs elsewhere) may need the fix-up adjusted.

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
- **No native packaging from upstream** (e.g. [kiro-gateway.rb](Formula/kiro-gateway.rb)): vendor source into `libexec`, create a private venv/dependency install, and write a wrapper launcher script into `bin` rather than relying on Python::Virtualenv or similar helpers that assume a `pyproject.toml`/`setup.py`.
- **Runtime credential/config auto-detection**: formulae that need to discover user credentials at *service start time* (not install time) do so from the launcher script itself, because Homebrew's build sandbox denies filesystem reads outside a fixed allowlist during `install`/`post_install` — see the kiro-gateway launcher script and its `post_install` `.env` handling.
- **One-time provisioning as a launcher subcommand** (e.g. [litellm.rb](Formula/litellm.rb)): when a formula needs first-run setup that touches user state (create a database, write `~/.litellm/.env` with a generated key, start a dependent service if nothing is listening), the wrapper script intercepts a subcommand (`litellm init`) before its normal `exec` and does it there. `brew install` can't do this (sandbox denies writes outside its prefix, and services aren't running yet), and a separate helper binary is worse UX than making it a subcommand of the tool users already type.
- **Pinning fork commits over tags**: when tracking a fork's `main` branch instead of upstream's tagged releases (because needed fixes land ahead of upstream tags), pin the `url` to a specific commit SHA (not `refs/heads/main`) so the tarball and its `sha256` stay reproducible.
- **Prebuilt per-platform release binaries** (e.g. [llama-swap.rb](Formula/llama-swap.rb)): when upstream publishes ready-to-run per-arch release tarballs, put the arm64 archive's `url`/`sha256` at the top level and override it with the Intel one inside `on_macos { on_intel { ... } }` (see the `--only-tap-syntax` note above for why the split is mandatory rather than wrapping both arch blocks in `on_macos`). sha256s come from upstream's `*_checksums.txt`; no building from source. Keep the `bottle do` block with the GHCR `root_url` so CI still bottles the unpacked binary and private-repo users get a working `brew install`.
- **Prebuilt PyPI platform wheels** (e.g. [litellm.rb](Formula/litellm.rb)): for a regular PyPI package that ships per-platform wheels, put the arm64 wheel's `url`/`sha256` at the top level and override with the Intel one inside `on_macos { on_intel { ... } }` (same split as llama-swap.rb), with `using: :nounzip` (Homebrew would otherwise unzip it on zip magic detection, and pip needs the real wheel file), then `pip install` the wheel plus its extras into a `libexec` venv so pip resolves the remaining deps from PyPI at build time. sha256s are the PyPI digests. `preserve_rpath` is needed for the linker-signed native extensions, and an in-`install` `ruby-macho` fix-up rewrites the install names of bundled dep dylibs whose IDs are non-`@rpath` absolute paths (Homebrew's install-name relocation overflows their name buffers and aborts the install).
- **`service do` blocks**: formulae exposing a long-running process define a `brew services`-compatible service block (`run`, `keep_alive`, `log_path`/`error_log_path`, `working_dir`) rather than expecting users to run the binary manually.
- **Security-conscious defaults in `caveats`**: formulae that bind to network ports document that they default to loopback-only and explain when/why to set an API key or widen the bind host.
- **`test do` blocks avoid touching `$HOME` or real network/service state** — they assert against `--help`/`--version` output or deterministic early-exit error messages (e.g. missing-credentials validation) rather than exercising real functionality that would mutate user state.

## Formula/cask index

- [Formula/kirocc.rb](Formula/kirocc.rb) — Anthropic Messages API proxy to the Kiro backend; builds from Go source at a pinned kylerjensen fork commit (CGO disabled, so no C toolchain).
- [Formula/kiro-gateway.rb](Formula/kiro-gateway.rb) — OpenAI/Anthropic-compatible proxy gateway for Kiro (kylerjensen fork); vendored Python source + private venv, tracks fork's `main` via pinned commit SHA, `brew services`-compatible.
- [Formula/icloud-sync.rb](Formula/icloud-sync.rb) — symlinks `$HOME` directories into iCloud Drive; macOS-only, wraps a pre-bundled Node ESM script.
- [Formula/llama-swap.rb](Formula/llama-swap.rb) — proxy server for swapping models on llama.cpp; prebuilt per-arch upstream release binaries, `brew services`-compatible (requires a user-created `~/.llama-swap/config.yaml`). Version-bump cadence below.
- [Formula/litellm.rb](Formula/litellm.rb) — OpenAI-compatible proxy gateway for 100+ LLM providers (BerriAI/litellm); prebuilt PyPI wheels + private venv, `brew services`-compatible (requires a user-created `~/.litellm/config.yaml`; UI mode provisioned by `litellm init`, which needs the `postgresql` dependency). Version-bump cadence below.
- [Formula/olla.rb](Formula/olla.rb) — proxy and load balancer for self-hosted LLM inference (Ollama, vLLM, llama.cpp, ...); prebuilt per-arch upstream release binaries, `brew services`-compatible (reads a user-created `~/.olla/config.yaml`).
- [Formula/splash.rb](Formula/splash.rb) — local inference engine for Apple silicon (kylerjensen/splash fork, upstream incoai/splash plus JIT mode for serving several models); tracks the fork's `main` via pinned commit SHA with an upstream-base `-dev.N` version. `install` runs upstream's own `make package` (Metal engine + bundled standalone Python), so the keg matches an upstream release; macOS 26.4+ on arm64 only, and it conflicts with `incoai/tap/splash` (both install `splash`). `brew services`-compatible: the service runs `splash serve --all-models` through a `libexec/splash-service` wrapper that reads extra arguments from `~/.config/splash/service-args` and an API key from `~/.config/splash/api-key` (into `SPLASH_API_KEY`, never argv).
- [Casks/omlx-app.rb](Casks/omlx-app.rb) — menu bar app cask for the oMLX LLM inference server; per-OS-version download variants, arm64-only.

`audit_exceptions/flat_namespace_allowlist.json` allowlists formulae for `brew audit`'s flat-namespace check.
