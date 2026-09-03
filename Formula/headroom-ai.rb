class HeadroomAi < Formula
  desc "Context optimization layer for LLM applications"
  homepage "https://headroom-docs.vercel.app"
  url "https://files.pythonhosted.org/packages/b6/17/10c3eb35dddb30055d84116444b7158d435758c4cfc161d7c206fb871782/headroom_ai-0.37.0.tar.gz"
  sha256 "7ffdecba91ce44dd02f1601499f6c935c47374b7cb6ec61e569b816a4bb78a26"
  license "Apache-2.0"

  depends_on "python@3.13"

  # jiter (pulled in transitively via litellm -> openai) ships a
  # linker-signed, @rpath-ID'd Mach-O extension with no headerpad reserved.
  # Homebrew's install-name relocation tries to rewrite that ID to an
  # absolute Cellar path and fails ("needs to be relinked"). Leaving @rpath
  # IDs alone is harmless here since Python loads extensions by file path,
  # never by their Mach-O ID.
  preserve_rpath

  # headroom-ai ships prebuilt wheels (it bundles a compiled Rust extension)
  # and pulls in heavy binary deps (torch, onnxruntime) via the "all" extra.
  # Homebrew's Python::Virtualenv helper forces `pip install --no-binary
  # :all:`, which would try to compile all of that from source, so we drive
  # a plain venv + pip ourselves to install from the published wheels.
  def install
    system formula_opt_bin("python@3.13")/"python3.13", "-m", "venv", libexec
    pip = libexec/"bin/pip"
    system pip, "install", "--upgrade", "pip"
    # PyPI's default Linux "torch" wheel unconditionally pulls a full set of
    # NVIDIA CUDA runtime packages (cudnn, nccl, cusparselt, ...), which ship
    # libcuda/libcublas/libmpi that Homebrew's linkage check then reports as
    # missing on CI's GPU-less containers. torch's CPU-only wheel needs none
    # of that; macOS has no CUDA build to begin with, so this index is a
    # no-op there.
    system pip, "install", "--extra-index-url", "https://download.pytorch.org/whl/cpu",
           "headroom-ai[all]==#{version}"
    # rapidocr (pulled in by the "image" extra) depends on GUI-enabled
    # opencv-python, which bundles X11/GL/video-codec libraries this
    # proxy/CLI tool never exercises. Homebrew's linkage check flags them as
    # missing on Linux and flat-namespace on macOS. Swap in the headless
    # build, which exposes the same `cv2` API without those extras.
    system pip, "uninstall", "-y", "opencv-python"
    system pip, "install", "opencv-python-headless"
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
