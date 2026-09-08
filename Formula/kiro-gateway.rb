class KiroGateway < Formula
  include Language::Python::Virtualenv

  desc "Proxy API gateway for Kiro IDE & CLI (Amazon Q Developer / AWS CodeWhisperer)"
  homepage "https://github.com/kylerjensen/kiro-gateway"
  url "https://github.com/kylerjensen/kiro-gateway/archive/5c570b30ba37201bc86220a6713d0923703ab1e5.tar.gz"
  version "2.4.dev"
  sha256 "d84b6417034aa07e6b263cd755a2f29af64ad08247651acab4a2d0fbd3d2f0db"
  license "AGPL-3.0-only"

  depends_on "rust" => :build
  depends_on "python@3.14"

  def install
    # No pyproject.toml/setup.py exists upstream; vendor source into libexec
    # and install dependencies via pip in a private venv rather than relying
    # on Python::Virtualenv helpers that assume a build system.
    libexec.install Dir["*"]

    venv = Language::Python::Virtualenv.virtualenv_create(libexec, "python@3.14")
    system "#{venv}/bin/pip", "install", "-r", "requirements.txt"

    # main.py imports from the kiro package at the repo root, so libexec
    # must be the working directory for the launcher below.
    (var/"kiro-gateway").mkpath

    (bin/"kiro-gateway").write <<~EOS
            #!/bin/bash
            set -e

            # --version/--help just print and exit; they need neither .env nor
            # a writable var/. Short-circuit before any provisioning so they work
            # in read-only contexts (e.g. Homebrew's test do sandbox).
            case "$1" in
              --version|-V|--help|-h)
                cd "#{libexec}" || exit 1
                exec "#{libexec}/venv/bin/python3" main.py "$@"
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
      ENVEOF
            fi

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
      kiro-gateway v2.4.dev is an OpenAI/Anthropic-compatible
      proxy gateway for Kiro (Amazon Q Developer / AWS CodeWhisperer). It
      requires valid Kiro credentials to function.

      Before starting the service, configure your Kiro credentials by
      copying the .env.example from the repo and setting the required
      fields (at minimum PROXY_API_KEY). The formula auto-generates a
      .env on first run with a random PROXY_API_KEY, but you still need
      a Kiro refresh token or credentials file.

      By default this service binds to 127.0.0.1 only. Set SERVER_HOST in
      the .env to widen the bind address if needed.

      Homebrew service:
        brew services start kiro-gateway
        brew services info kiro-gateway
        brew services stop kiro-gateway
    EOS
  end

  test do
    # Assert the interpreter, venv, and vendored kiro package all wired
    # up correctly and agree on the version derived from the git tag.
    assert_match version.to_s, shell_output("#{bin}/kiro-gateway --version 2>&1")
  end
end
