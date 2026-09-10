class Kirocc < Formula
  desc "Anthropic Messages API proxy to the Kiro backend"
  homepage "https://github.com/d-kuro/kirocc"

  # Pinned to the kylerjensen/kirocc fork's main HEAD at 7d36bd3 (forward of
  # the v0.12.0-dev.1 tag): folds in the fix from kirocc PR #1 for a
  # round-boundary text-loss bug (ResetAccumulator dropped text a prior
  # ToolSearch/advisor round was still holding back) and a swallowed
  # json.Marshal error on invalid UTF-8 in streamed SSE deltas. No new tag
  # exists yet, so this pins the commit SHA directly (not refs/heads/main)
  # to keep the tarball + sha256 reproducible; see CLAUDE.md "Pinning fork
  # commits over tags". The previous kirocc-dub temp formula tracked this
  # same fix and has been removed now that it's here.
  url "https://github.com/kylerjensen/kirocc/archive/7d36bd39b0f56e70f2ca4d15919f5c436f3640f8.tar.gz"
  version "0.12.0-dev.2"
  sha256 "c5febb34a9b16036dcc594f1c7dfef4f416c86b5a90d35b6f89f3267a0c2a36d"
  license "Apache-2.0"

  bottle do
    root_url "https://github.com/kylerjensen/homebrew-tap/releases/download/kirocc-0.12.0-dev.2"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "d5325f605d428e0a5efa109e51fda5a0cdf7d80d247fae17e2f7ed979493f489"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "7281fddd875bd93efc1ca2a15e3eb34dec7463e21c34e8cab4fd677e2e30fd73"
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
