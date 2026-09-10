class KiroccDub < Formula
  desc "Anthropic Messages API proxy to the Kiro backend (temp: dup-letter round-boundary fix)"
  homepage "https://github.com/d-kuro/kirocc"

  # TEMPORARY formula, not for general use — remove once the fix below lands
  # in a tagged kirocc release and the main kirocc formula picks it up.
  # (Named "kirocc-dub", not "kirocc@dub": Homebrew derives a formula's Ruby
  # class name from its filename, and its "@"-version convention only
  # handles a numeric suffix after "@" (e.g. node@18 -> NodeAT18); a
  # non-numeric suffix like "dub" would produce an invalid class name.)
  #
  # Pins to commit ce675defba4e28865b8a5bdd234c0e69d7e50c99 on the
  # kylerjensen/kirocc fork's claude/kirocc-repeated-letters-cl5c7g branch
  # (kirocc PR #1, unreleased): fixes a round-boundary byte-loss bug where
  # ResetAccumulator discarded text a prior ToolSearch/advisor round was
  # still holding back (a partial <thinking> tag or stop-sequence prefix)
  # instead of flushing it, plus a swallowed json.Marshal error that could
  # emit a malformed SSE delta on invalid UTF-8. Pinned to the commit SHA
  # rather than the branch ref so the tarball and sha256 stay reproducible
  # while the fix is still unreleased and the branch can move.
  url "https://github.com/kylerjensen/kirocc/archive/ce675defba4e28865b8a5bdd234c0e69d7e50c99.tar.gz"
  version "0.12.0-dev.1-dub"
  sha256 "359aa29d7e903b9e37e303bf94c67fd2dc78c550dc5a180eb1f363f1492c6cc7"
  license "Apache-2.0"

  # Conflicts with the main kirocc formula: both build a binary named
  # "kirocc" from ./cmd/kirocc, so this installs it as "kirocc-dub" instead
  # to avoid clobbering/link-conflicting with a real kirocc install.
  conflicts_with "kirocc", because: "both install a service named kirocc; stop one before running the other"
  depends_on "go" => :build

  def install
    # The dependency tree is pure-Go (modernc.org/sqlite), so build with cgo
    # disabled for reproducible cross-platform builds with no C toolchain.
    ENV["CGO_ENABLED"] = "0"
    system "go", "build", "-o", bin/"kirocc-dub", *std_go_args, "./cmd/kirocc"
  end

  service do
    run [opt_bin/"kirocc-dub"]
    keep_alive true
    log_path var/"log/kirocc-dub.log"
    error_log_path var/"log/kirocc-dub.log"
    working_dir Dir.home
  end

  def caveats
    <<~EOS
      TEMPORARY formula tracking an unreleased fix (kirocc PR #1) for a
      round-boundary text-loss bug. Uninstall this and use "kirocc" once the
      fix ships in a tagged release.

      Quick start:
        kirocc-dub

      On startup, kirocc-dub prints endpoint hints like:
        set ANTHROPIC_BASE_URL to use with Claude Code url=http://127.0.0.1:3456

      Useful env vars:
        export ANTHROPIC_BASE_URL=http://127.0.0.1:3456
        export ANTHROPIC_AUTH_TOKEN=<your KIROCC_API_KEY value>

      Security:
        By default kirocc-dub listens on 127.0.0.1:3456.
        If you bind to a non-loopback host, set an API key:
          kirocc-dub --api-key '<strong-random-key>'

      Credentials:
        Default DB path:
          macOS: ~/Library/Application Support/kiro-cli/data.sqlite3
          Linux: ~/.local/share/kiro-cli/data.sqlite3

        If needed, override with:
          kirocc-dub --db '<path-to-data.sqlite3>'
          # or
          export KIROCC_DB_PATH='<path-to-data.sqlite3>'

      Homebrew service:
        brew services start kirocc-dub
        brew services info kirocc-dub
        brew services stop kirocc-dub
    EOS
  end

  test do
    output = shell_output("#{bin}/kirocc-dub -h 2>&1")
    assert_match "listen port", output
    assert_match "kiro-api-key", output
  end
end
