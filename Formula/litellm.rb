# frozen_string_literal: true

# OpenAI-format proxy gateway for 100+ LLM APIs
class Litellm < Formula
  desc "OpenAI-format proxy gateway for 100+ LLM APIs"
  homepage "https://github.com/BerriAI/litellm"
  url "https://files.pythonhosted.org/packages/9c/97/c9da198af273d700bf44d7d82eb21c5b8078c82574b31856b71b1298234b/litellm-1.98.0.tar.gz"
  sha256 "0e6ba5d645a73ca6d0ffb4e8ec539d94b6e8fad691f2a54c6819011e6d0de8bf"
  license "MIT"

  livecheck do
    url "https://pypi.org/pypi/litellm/json"
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  depends_on "postgresql@17"
  depends_on "python@3.13"

  # Rust/maturin wheels (jiter, pydantic-core, tiktoken, orjson, tokenizers, and
  # litellm's own rust_bridge) ship with linker-signed adhoc Mach-O binaries
  # that have no header padding. Homebrew's post-install relocation step tries to
  # rewrite their @rpath install names to absolute paths, but the header is full
  # so it falls back to a manual adhoc resign — which breaks the linker-signed
  # flag that macOS requires and causes SIGKILL (Code Signature Invalid) on load.
  # preserve_rpath tells Homebrew to skip rewriting @rpath IDs entirely, leaving
  # the original linker signatures intact. Python's dlopen loads .so files by
  # filesystem path so the @rpath ID is irrelevant at runtime.
  preserve_rpath

  # The sdist builds with maturin and needs a Rust toolchain, but PyPI ships
  # prebuilt cp310-abi3 wheels for macOS (x86_64/arm64) and Linux
  # (manylinux/musllinux, x86_64/aarch64). So instead of building the staged
  # sources, pip installs the pinned version from PyPI and lets the wheels do
  # the platform-specific work. litellm itself stays pinned to this formula's
  # version; its dependencies resolve from PyPI at install time.
  # extra_proxy pulls in prisma, which is required for the web admin UI.
  def install
    python = formula_opt_bin("python@3.13")/"python3.13"
    system python, "-m", "venv", libexec
    system libexec/"bin/pip", "install",
           "--no-cache-dir", "--disable-pip-version-check",
           "litellm[proxy,extra_proxy]==#{version}"

    (bin/"litellm").write_env_script libexec/"bin/litellm", PATH: "#{libexec}/bin:$PATH"

    (etc/"litellm").mkpath
    config = etc/"litellm/config.yaml"
    return if config.exist?

    require "securerandom"
    master_key = "sk-#{SecureRandom.hex(24)}"
    (var/"log/litellm-master-key").open("w") { |f| f.write(master_key) }
    db_url = "postgresql://#{ENV.fetch("USER", nil)}@localhost/litellm"
    config.write <<~YAML
      # LiteLLM Proxy server configuration.
      # Docs: https://docs.litellm.ai/docs/proxy/configs
      #
      # Add models below and restart the service:
      #   brew services restart litellm
      #
      # Example:
      #   model_list:
      #     - model_name: gpt-4o
      #       litellm_params:
      #         model: openai/gpt-4o
      #         api_key: os.environ/OPENAI_API_KEY
      #
      # API keys referenced as `os.environ/VAR` are read from the service
      # process environment. Set them in your shell profile or launchd plist.

      general_settings:
        master_key: #{master_key}
        database_url: "#{db_url}"

      model_list: []
    YAML
  end

  def post_install
    pg_bin = formula_opt_bin("postgresql@17")
    db_name = "litellm"

    # quiet_system returns a boolean without raising; skip DB setup if
    # PostgreSQL isn't running. The user can run `brew postinstall litellm`
    # after starting postgresql@17.
    return unless quiet_system pg_bin/"pg_isready", "--quiet"

    # createdb exits non-zero if the DB already exists; that is fine.
    quiet_system pg_bin/"createdb", db_name

    db_url = "postgresql://#{ENV.fetch("USER", nil)}@localhost/#{db_name}"

    # Use litellm_proxy_extras.utils.ProxyExtrasDBManager.setup_database() which
    # handles the full Prisma toolchain bootstrap (downloads Node.js + Prisma CLI
    # on first run) and runs prisma db push. The venv bin dir must be on PATH so
    # the `prisma` CLI entry point is found by the subprocess calls inside it.
    venv_bin = (libexec/"bin").to_s
    with_env("DATABASE_URL" => db_url,
             "PATH"         => "#{venv_bin}:#{ENV.fetch("PATH", nil)}") do
      system libexec/"bin/python3", "-c",
             "from litellm_proxy_extras.utils import ProxyExtrasDBManager; " \
             "ProxyExtrasDBManager.setup_database()"
    end
  end

  service do
    run [opt_bin/"litellm", "--config", etc/"litellm/config.yaml",
         "--host", "127.0.0.1", "--port", "4000"]
    keep_alive true
    log_path var/"log/litellm.log"
    error_log_path var/"log/litellm.log"
    working_dir Dir.home
    environment_variables DATABASE_URL: "postgresql://#{ENV.fetch("USER", nil)}@localhost/litellm"
  end

  def caveats
    master_key = (var/"log/litellm-master-key").exist? ? (var/"log/litellm-master-key").read.strip : nil
    <<~EOS
      The LiteLLM Proxy listens on http://127.0.0.1:4000 and provides an
      OpenAI-compatible REST API and web UI.

      Start PostgreSQL before starting the proxy:
        brew services start postgresql@17
        brew services start litellm
      #{"\n      Master key (sign in to the web UI and use as your API Bearer token):\n        #{master_key}\n" if master_key}
      Configure models in:
        #{etc}/litellm/config.yaml
      then restart the service:
        brew services restart litellm

      Service management:
        brew services start litellm
        brew services info litellm
        brew services stop litellm

      Point clients at the proxy, for example:
        export OPENAI_API_BASE=http://127.0.0.1:4000
        export OPENAI_API_KEY=#{master_key || "<master_key>"}
    EOS
  end

  def doc
    <<~DOC
      OpenAI-format proxy gateway for 100+ LLM APIs.

      Configure models in:
        #{etc}/litellm/config.yaml
      then restart the service:
        brew services restart litellm

      Service management:
        brew services start litellm
        brew services info litellm
        brew services stop litellm

      Point clients at the proxy, for example:
        export OPENAI_API_BASE=http://127.0.0.1:4000
    DOC
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/litellm --version")
  end
end
