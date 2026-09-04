class KiroGateway < Formula
  desc "Proxy gateway exposing Kiro's models over OpenAI/Anthropic-compatible APIs"
  homepage "https://github.com/jwadow/kiro-gateway"
  url "https://github.com/jwadow/kiro-gateway/archive/refs/tags/v2.3.tar.gz"
  sha256 "dfe6d99001d98cdb3c06e419e5c4f076183ee12e0132386a09a2b92ccbd5876d"
  license "AGPL-3.0-or-later"

  depends_on "python@3.14"

  # tiktoken ships a compiled Rust extension with a linker-signed, @rpath-ID'd
  # Mach-O binary and no headerpad reserved. Homebrew's install-name
  # relocation tries to rewrite that ID to an absolute Cellar path and fails
  # ("needs to be relinked"). Leaving the @rpath ID alone is harmless since
  # Python loads extensions by file path, never by their Mach-O ID.
  preserve_rpath

  # Upstream ships no pyproject.toml/setup.py (just a requirements.txt and a
  # `python main.py` entry point), so it isn't pip-installable and the
  # Python::Virtualenv helper doesn't apply. Vendor the source into libexec,
  # install deps into a private venv, and wrap main.py with a launcher script.
  def install
    libexec.install Dir["*"]

    system formula_opt_bin("python@3.14")/"python3.14", "-m", "venv", libexec/"venv"
    # requirements.txt also lists pytest/hypothesis under a "Testing
    # dependencies" heading; hypothesis ships a compiled extension that trips
    # Homebrew's install-name relocation, and none of the test deps are
    # needed at runtime, so install only the actual runtime packages.
    system libexec/"venv/bin/pip", "install", "fastapi", "uvicorn[standard]", "httpx", "loguru",
           "python-dotenv", "tiktoken"

    (bin/"kiro-gateway").write <<~EOS
      #!/bin/bash
      # Auto-detect Kiro credentials on every launch (not just at install
      # time) unless the user's .env already names a source, so logging into
      # Kiro IDE/kiro-cli after installing this formula just works on the
      # next `brew services restart` -- no reinstall or manual edit needed.
      # This can't live in the formula's install/post_install: Homebrew's
      # build sandbox denies reads outside a fixed allowlist, so ~/.aws and
      # ~/.local/share are invisible there even when they exist.
      env_file="#{var}/kiro-gateway/.env"
      if ! grep -qE '^(KIRO_CREDS_FILE|KIRO_CLI_DB_FILE|REFRESH_TOKEN)=' "$env_file" 2>/dev/null; then
        kiro_ide_creds="$HOME/.aws/sso/cache/kiro-auth-token.json"
        kiro_cli_db="$HOME/.local/share/kiro-cli/data.sqlite3"
        amazon_q_cli_db="$HOME/.local/share/amazon-q/data.sqlite3"
        if [[ -f "$kiro_ide_creds" ]]; then
          export KIRO_CREDS_FILE="$kiro_ide_creds"
        elif [[ -f "$kiro_cli_db" ]]; then
          export KIRO_CLI_DB_FILE="$kiro_cli_db"
        elif [[ -f "$amazon_q_cli_db" ]]; then
          export KIRO_CLI_DB_FILE="$amazon_q_cli_db"
        fi
      fi
      # Deliberately not "cd libexec": main.py's own imports work by sys.path,
      # not cwd. What actually needs to live next to main.py is .env itself --
      # python-dotenv's load_dotenv() (called at kiro/config.py import time)
      # walks up from that *module's* directory, ignoring cwd entirely for a
      # real script run. install() symlinks libexec/.env to this persistent
      # config file so it survives upgrades (which replace libexec wholesale).
      exec "#{libexec}/venv/bin/python3" "#{libexec}/main.py" "$@"
    EOS
  end

  def post_install
    (var/"kiro-gateway").mkpath
    env_file = var/"kiro-gateway/.env"
    unless env_file.exist?
      env_file.write <<~EOS
        # Homebrew installs are single-user, single-machine, so this binds to
        # loopback only and leaves PROXY_API_KEY at upstream's default rather
        # than inventing a secret on your behalf. Widen either if you ever
        # expose this beyond localhost.
        SERVER_HOST="127.0.0.1"

        # KIRO_CREDS_FILE, KIRO_CLI_DB_FILE, and REFRESH_TOKEN are all left
        # unset here: the launcher script auto-detects Kiro IDE/kiro-cli
        # credentials on every start instead, so a login that happens after
        # this install is picked up without editing this file. Set one of
        # them explicitly to pin a specific source instead of auto-detecting.
      EOS
    end
    ln_sf env_file, libexec/".env"
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
      #{var}/kiro-gateway/.env binds to 127.0.0.1 only and leaves
      PROXY_API_KEY at upstream's default, since Homebrew installs are
      assumed single-user/single-machine here.

      Every start, the launcher auto-detects Kiro credentials (Kiro IDE's
      ~/.aws/sso/cache/kiro-auth-token.json, then kiro-cli's
      ~/.local/share/kiro-cli/data.sqlite3) unless that .env already sets
      KIRO_CREDS_FILE, KIRO_CLI_DB_FILE, or REFRESH_TOKEN -- so logging into
      Kiro after installing this formula just works on the next
      `brew services restart`, no reinstall or manual edit needed. Set one
      of those three yourself in the .env to pin a specific source instead.
      See upstream's README for details on each option:
        https://github.com/jwadow/kiro-gateway#%EF%B8%8F-configuration

      Homebrew service:
        brew services start kiro-gateway
        brew services info kiro-gateway
        brew services stop kiro-gateway
    EOS
  end

  test do
    # main.py validates config (and exits 1) before it ever parses CLI args,
    # so --help isn't reachable without credentials. Running with none set
    # deterministically hits that validation error, which is enough to prove
    # the interpreter, venv, and vendored source all wired up correctly.
    output = shell_output("#{bin}/kiro-gateway 2>&1", 1)
    assert_match "No Kiro credentials configured", output
  end
end
