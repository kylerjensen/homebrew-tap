class KiroGateway < Formula
  desc "Proxy API gateway for Kiro IDE & CLI (Amazon Q Developer / AWS CodeWhisperer)"
  homepage "https://github.com/kylerjensen/kiro-gateway"
  url "https://github.com/kylerjensen/kiro-gateway/archive/5c570b30ba37201bc86220a6713d0923703ab1e5.tar.gz"
  version "2.4.dev.13"
  sha256 "d84b6417034aa07e6b263cd755a2f29af64ad08247651acab4a2d0fbd3d2f0db"
  license "AGPL-3.0-only"

  bottle do
    root_url "https://github.com/kylerjensen/homebrew-tap/releases/download/kiro-gateway-2.4.dev.13"
    rebuild 1
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "407dafefeadaf2a89b2ebd0d58dc19637464391d0414c5419c6de94c1914ab69"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "49c98b2968fdb38857194e0a807d6f9e13d062d522c38f234edfe1e9e10adc6a"
  end

  depends_on "python@3.14"

  # tiktoken ships a compiled Rust extension with a linker-signed, @rpath-ID'd
  # Mach-O binary and no headerpad reserved. Homebrew's install-name
  # relocation tries to rewrite that ID to an absolute Cellar path and fails
  # ("needs to be relinked"). Leaving the @rpath ID alone is harmless since
  # Python loads extensions by file path, never by their Mach-O ID.
  preserve_rpath

  def install
    # Upstream ships no pyproject.toml/setup.py (just a requirements.txt and a
    # `python main.py` entry point), so it isn't pip-installable as a package
    # and the Python::Virtualenv helpers don't apply. Vendor the source into
    # libexec, create a private venv there, and wrap main.py with a launcher.
    libexec.install Dir["*"]

    system formula_opt_bin("python@3.14")/"python3.14", "-m", "venv", libexec/"venv"
    # requirements.txt also lists pytest/hypothesis under a "Testing
    # dependencies" heading; hypothesis ships a compiled extension that trips
    # Homebrew's install-name relocation, and none of the test deps are
    # needed at runtime, so install only the actual runtime packages.
    system libexec/"venv/bin/pip", "install", "fastapi", "uvicorn[standard]", "httpx",
           "loguru", "python-dotenv", "tiktoken"

    # brew services points launchd's working_dir at var/<name> (see the
    # service block), and launchd won't spawn if that dir is missing. Create
    # it at install time -- it's under Homebrew's own prefix, which the build
    # sandbox permits (unlike the user paths the launcher reads at start time).
    (var/"kiro-gateway").mkpath

    (bin/"kiro-gateway").write <<~EOS
      #!/bin/bash
      set -e

      # --version/--help just print and exit; they need neither .env nor
      # a writable var/. Short-circuit before any provisioning so they work
      # in read-only contexts (e.g. Homebrew's `test do` sandbox denies writes
      # to var/, which would otherwise make `mkdir`/`.env` creation fail here).
      case "$1" in
        --version|-V|--help|-h)
          cd "#{libexec}" || exit 1
          exec "#{libexec}/venv/bin/python3" main.py "$@"
          ;;
        token)
          env_dir="#{var}/kiro-gateway"
          env_file="$env_dir/.env"
          if [ -f "$env_file" ]; then
            grep "^PROXY_API_KEY=" "$env_file" | cut -d'=' -f2-
          else
            echo "PROXY_API_KEY not found — run 'kiro-gateway' once to generate it" >&2
            exit 1
          fi
          ;;
      esac

      env_dir="#{var}/kiro-gateway"
      env_file="$env_dir/.env"
      mkdir -p "$env_dir"

      if [ ! -f "$env_file" ]; then
        # Homebrew installs are single-user, single-machine, so bind to
        # loopback only. PROXY_API_KEY has no safe default upstream, so
        # generate a random secret rather than leaving it guessable.
        api_key="$(/usr/bin/openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p | tr -d '\\n')"

        umask 077
        cat > "$env_file" <<ENVEOF
      SERVER_HOST=127.0.0.1
      SERVER_PORT=8000
      PROXY_API_KEY=$api_key
      KIRO_CLI_DB_FILE="~/Library/Application Support/kiro-cli/data.sqlite3"
      ENVEOF
      fi

      # python-dotenv's load_dotenv() runs at kiro/config.py import time and
      # resolves relative to that module's directory, ignoring cwd -- so .env
      # must live next to the vendored source. Symlink the persistent var/
      # copy into libexec so it survives upgrades (which replace libexec
      # wholesale).
      ln -sf "$env_file" "#{libexec}/.env"

      cd "#{libexec}" || exit 1
      exec "#{libexec}/venv/bin/python3" main.py "$@"
    EOS
  end

  service do
    run [opt_bin/"kiro-gateway"]
    keep_alive true
    working_dir var/"kiro-gateway"
    log_path var/"log/kiro-gateway.log"
    error_log_path var/"log/kiro-gateway.log"
  end

  def caveats
    <<~EOS
      #{var}/kiro-gateway/.env binds to 127.0.0.1 only and auto-generates a
      random PROXY_API_KEY and sets KIRO_CLI_DB_FILE on first run -- clients
      must send that key as their bearer/x-api-key. Find it with:
        grep PROXY_API_KEY #{var}/kiro-gateway/.env

      To output your token:
        kiro-gateway token

      A running service still needs valid Kiro credentials if not using
      the default kiro-cli database: set one of
      KIRO_CREDS_FILE or REFRESH_TOKEN in that .env (see
      the upstream README's configuration section):
        https://github.com/jwadow/kiro-gateway#readme

      Homebrew service:
        brew services start kiro-gateway
        brew services info kiro-gateway
        brew services stop kiro-gateway
    EOS
  end

  test do
    # main.py parses CLI args before it validates config, so --version is
    # reachable without credentials. This asserts the interpreter, venv, and
    # vendored kiro package all wired up correctly.
    assert_match version.to_s, shell_output("#{bin}/kiro-gateway --version 2>&1")
  end
end
