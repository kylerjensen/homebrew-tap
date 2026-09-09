class Kirocc < Formula
  desc "Anthropic Messages API proxy to the Kiro backend"
  homepage "https://github.com/d-kuro/kirocc"

  # Pinned to the kylerjensen/kirocc fork's main HEAD: Kiro "Auto" model
  # support and the configurable request-body cap (upstream PRs ahead of any
  # tag). Tracking a fork's main via a pinned commit SHA (not refs/heads/main)
  # keeps the tarball + sha256 reproducible; see CLAUDE.md "Pinning fork
  # commits over tags".
  url "https://github.com/kylerjensen/kirocc/archive/0ed6f6bc04b1c3a92f5f2e0644b8cd1781ff9ca9.tar.gz"
  version "0.12.0.dev.1"
  sha256 "20e1391825d4e56aba655812fb9e3ca6cf5b62a3c36f81f275fcef5a9aad35b1"
  license "Apache-2.0"

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
