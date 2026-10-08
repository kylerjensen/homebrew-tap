class Kirocc < Formula
  desc "Anthropic Messages API proxy to the Kiro backend"
  homepage "https://github.com/d-kuro/kirocc"

  # Pinned to the kylerjensen/kirocc fork's main HEAD at 724e50b. This is one
  # commit ahead of tag v0.15.0-dev.1 (bbceb5c): it adds a fix in the request
  # converter to omit standalone Claude Code billing system blocks. The
  # v0.15.0-dev.1 base merges upstream d-kuro/kirocc main (v0.15.0) into the
  # fork and fixes kirocc issue #168: image blocks were counted as text in the
  # prompt token pre-count, so a single screenshot was reported as millions of
  # input tokens and Claude Code auto-compacted almost every turn. Earlier
  # fork-only work is still included (Auto model support, configurable
  # request-body cap, round-boundary text-loss fix, invalid-UTF8 SSE fix, image
  # carry in history). HEAD has no matching tag yet, so we pin the commit SHA
  # (not refs/heads/main) to keep the tarball + sha256 reproducible; see
  # CLAUDE.md "Pinning fork commits over tags".
  url "https://github.com/kylerjensen/kirocc/archive/724e50bbbbfad0a4230f16533792c2a9439910a8.tar.gz"
  version "0.15.0-dev.2"
  sha256 "1c6129fcc15c97e732ccfe8194fb4121ef26c569c7e0bb4f803119c5cb6d356c"
  license "Apache-2.0"

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
    rebuild 1
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "4194a14029d3acb3ad490443140a48ea11568bf8597467bd418f67787f5ab328"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "541f863de345183df883de82b313139a368e384673e5553841e326db42cfab63"
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
