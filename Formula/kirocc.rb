class Kirocc < Formula
  desc "Anthropic Messages API proxy to the Kiro backend"
  homepage "https://github.com/d-kuro/kirocc"

  # Pinned to the kylerjensen/kirocc fork's main HEAD at bbceb5c, tagged
  # v0.15.0-dev.1. This merges upstream d-kuro/kirocc main (v0.15.0) into the
  # fork and adds the fix for kirocc issue #168: image blocks were counted as
  # text in the prompt token pre-count, so a single screenshot was reported as
  # millions of input tokens and Claude Code auto-compacted almost every turn.
  # Earlier fork-only work is still included (Auto model support, configurable
  # request-body cap, round-boundary text-loss fix, invalid-UTF8 SSE fix, image
  # carry in history). A matching tag exists, but we pin the commit SHA (not
  # refs/heads/main) to keep the tarball + sha256 reproducible; see CLAUDE.md
  # "Pinning fork commits over tags".
  url "https://github.com/kylerjensen/kirocc/archive/bbceb5ccaa8c603bc08a8b44e54607ef50d9c520.tar.gz"
  version "0.15.0-dev.1"
  sha256 "e164a18e440be606627910c9f21289a0b70b4e619b7c72d0bdf520f218db2977"
  license "Apache-2.0"

  bottle do
    # Bottles are published to GitHub Packages (GHCR), not GitHub Releases, so
    # they can be fetched with an Authorization header when the tap repo is
    # private. The canonical GHCR root_url lowercases the org and strips the
    # "homebrew-" repo prefix (kylerjensen/homebrew-tap -> kylerjensen/tap),
    # mirroring homebrew/core's ghcr.io/v2/homebrew/core. The ghcr.io URL is
    # auto-detected as CurlGitHubPackagesDownloadStrategy, so no "using:" is
    # needed; a plain releases/download URL would fall through to the default
    # unauthenticated CurlDownloadStrategy and 404 against a private repo.
    root_url "https://ghcr.io/v2/kylerjensen/tap"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "53eb157b623e455d443b25fe737f0072fc59e4cc3d0fa76532af563ef6467a69"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "c88ad22f97c3967f7da8299a16df3c75de1b97c3d9093c63dde94f53cd7d2275"
  end

  depends_on "go" => :build

  def install
    # The dependency tree is pure-Go (modernc.org/sqlite), so build with cgo
    # disabled for reproducible cross-platform bottles with no C toolchain.
    ENV["CGO_ENABLED"] = "0"
    system "go", "build", *std_go_args, "./cmd/kirocc"
  end

  service do
    run [opt_bin/"kirocc"]
    keep_alive true
    log_path var/"log/kirocc.log"
    error_log_path var/"log/kirocc.log"
    working_dir Dir.home
  end

  def caveats
    <<~EOS
      Quick start:
        kirocc

      On startup, kirocc prints endpoint hints like:
        set ANTHROPIC_BASE_URL to use with Claude Code url=http://127.0.0.1:3456

      Useful env vars:
        export ANTHROPIC_BASE_URL=http://127.0.0.1:3456
        export ANTHROPIC_AUTH_TOKEN=<your KIROCC_API_KEY value>

        This build tracks the kylerjensen/kirocc fork's main (Kiro "Auto"
        model support + configurable request-body cap). The client request
        body cap defaults to 32 MiB; tune it with:
          -max-request-body <bytes>
          # or
          export KIROCC_MAX_REQUEST_BODY='<bytes>'   # 0 = unlimited

      Security:
        By default kirocc listens on 127.0.0.1:3456.
        If you bind to a non-loopback host, set an API key:
          kirocc --api-key '<strong-random-key>'

      Credentials:
        Default DB path:
          macOS: ~/Library/Application Support/kiro-cli/data.sqlite3
          Linux: ~/.local/share/kiro-cli/data.sqlite3

        If needed, override with:
          kirocc --db '<path-to-data.sqlite3>'
          # or
          export KIROCC_DB_PATH='<path-to-data.sqlite3>'

      Homebrew service:
        brew services start kirocc
        brew services info kirocc
        brew services stop kirocc
    EOS
  end

  test do
    output = shell_output("#{bin}/kirocc -h 2>&1")
    assert_match "listen port", output
    assert_match "kiro-api-key", output
  end
end
