class HeadroomAi < Formula
  desc "Context optimization layer for LLM applications"
  homepage "https://headroom-docs.vercel.app"
  url "https://files.pythonhosted.org/packages/b6/17/10c3eb35dddb30055d84116444b7158d435758c4cfc161d7c206fb871782/headroom_ai-0.37.0.tar.gz"
  sha256 "7ffdecba91ce44dd02f1601499f6c935c47374b7cb6ec61e569b816a4bb78a26"
  license "Apache-2.0"

  depends_on "python@3.13"

  # headroom-ai ships prebuilt wheels (it bundles a compiled Rust extension)
  # and pulls in heavy binary deps (torch, onnxruntime) via the "all" extra.
  # Homebrew's Python::Virtualenv helper forces `pip install --no-binary
  # :all:`, which would try to compile all of that from source, so we drive
  # a plain venv + pip ourselves to install from the published wheels.
  def install
    system Formula["python@3.13"].opt_bin/"python3.13", "-m", "venv", libexec
    system libexec/"bin/pip", "install", "--upgrade", "pip"
    system libexec/"bin/pip", "install", "headroom-ai[all]==#{version}"
    bin.install_symlink libexec/"bin/headroom"
  end

  service do
    run [opt_bin/"headroom", "proxy", "--port", "8787"]
    keep_alive true
    log_path var/"log/headroom-proxy.log"
    error_log_path var/"log/headroom-proxy.log"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/headroom --version")
    assert_match "Usage:", shell_output("#{bin}/headroom --help")
  end
end
