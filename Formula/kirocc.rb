class Kirocc < Formula
  desc "Anthropic Messages API proxy to the Kiro backend"
  homepage "https://github.com/d-kuro/kirocc"
  version "0.9.1"
  license "Apache-2.0"

  on_macos do
    on_intel do
      url "https://github.com/d-kuro/kirocc/releases/download/v#{version}/kirocc_#{version}_darwin_amd64.tar.gz"
      sha256 "bec5ecd043dcf08075900a37ba44c48b3111cc582b75f33c9328b53e098fae43"
    end
    on_arm do
      url "https://github.com/d-kuro/kirocc/releases/download/v#{version}/kirocc_#{version}_darwin_arm64.tar.gz"
      sha256 "bd645bca7c08a900e6c36bb3e3d2078f35c1665d19ea2b7b8735c7df1b25e72e"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/d-kuro/kirocc/releases/download/v#{version}/kirocc_#{version}_linux_amd64.tar.gz"
      sha256 "97a36da994256dacfcc7075205321f7fef9e6200a5c650e096a67f229533bb45"
    end
    on_arm do
      url "https://github.com/d-kuro/kirocc/releases/download/v#{version}/kirocc_#{version}_linux_arm64.tar.gz"
      sha256 "2100af01858426acf422a51c2dc65ba8f16229b67003a9c2961df4233169b2af"
    end
  end

  def install
    bin.install "kirocc"
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
