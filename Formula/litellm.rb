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
  def install
    python = formula_opt_bin("python@3.13")/"python3.13"
    system python, "-m", "venv", libexec
    system libexec/"bin/pip", "install",
           "--no-cache-dir", "--disable-pip-version-check",
           "litellm[proxy]==#{version}"

    (bin/"litellm").write_env_script libexec/"bin/litellm", PATH: "#{libexec}/bin:$PATH"

    (etc/"litellm").mkpath
    config = etc/"litellm/config.yaml"
    config.write <<~YAML unless config.exist?
      # LiteLLM Proxy server configuration.
      # Docs: https://docs.litellm.ai/docs/proxy/configs
      #
      # Add models below, then restart the service:
      #   brew services restart litellm
      #
      # Example:
      #   model_list:
      #     - model_name: gpt-4o
      #       litellm_params:
      #         model: openai/gpt-4o
      #         api_key: os.environ/OPENAI_API_KEY
      #
      # `os.environ/...` references are read from the proxy process
      # environment. Under `brew services`, add variables with:
      #   brew services edit litellm
      model_list: []
    YAML
  end

  service do
    run [opt_bin/"litellm", "--config", etc/"litellm/config.yaml",
         "--host", "127.0.0.1", "--port", "4000"]
    keep_alive true
    log_path var/"log/litellm.log"
    error_log_path var/"log/litellm.log"
    working_dir Dir.home
  end

  def caveats
    <<~EOS
      The LiteLLM Proxy service listens on http://127.0.0.1:4000 and serves an
      OpenAI-compatible API (Swagger UI at the same address).

      Configure models in:
        #{etc}/litellm/config.yaml
      then restart the service:
        brew services restart litellm

      Service management:
        brew services start litellm
        brew services info litellm
        brew services stop litellm
        brew services edit litellm

      Point clients at the proxy, for example:
        export OPENAI_API_BASE=http://127.0.0.1:4000

      The service binds to loopback only. If you expose it beyond localhost
      (change the --host argument via `brew services edit litellm`), set a
      master key first: https://docs.litellm.ai/docs/proxy/virtual_keys
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
        brew services edit litellm

      Point clients at the proxy, for example:
        export OPENAI_API_BASE=http://127.0.0.1:4000

      The service binds to loopback only. If you expose it beyond localhost
      (change the --host argument via `brew services edit litellm`), set a
      master key first: https://docs.litellm.ai/docs/proxy/virtual_keys
    DOC
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/litellm --version")
  end
end
