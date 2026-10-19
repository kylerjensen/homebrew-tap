class SplashMacOSRequirement < Requirement
  fatal true
  # Splash needs macOS 26.4, a point release `depends_on macos: :tahoe`
  # (26.0) cannot express, so a requirement of its own checks the full version.
  satisfy(build_env: false) { OS.mac? && MacOS.full_version >= "26.4" }

  def message
    "Splash requires macOS 26.4 or newer."
  end
end

class Splash < Formula
  desc "Local inference engine for Apple silicon, built around the model"
  homepage "https://github.com/kylerjensen/splash"

  # Pinned to the kylerjensen/splash fork's main at 6fe260c: upstream
  # incoai/splash 1.3.2 plus JIT mode (kylerjensen/splash#2), which serves
  # several models from one server, loading the one each request names and
  # unloading it after an idle TTL. HEAD has no matching tag yet, so we pin the
  # commit SHA (not refs/heads/main) to keep the tarball + sha256 reproducible;
  # see CLAUDE.md "Pinning fork commits over tags".
  url "https://github.com/kylerjensen/splash/archive/6fe260c4c86a61ce11a58952e47812caaa40240d.tar.gz"
  version "1.3.2-dev.1"
  sha256 "cae31578c5dbd46f5bb8ea2c9a03e8621fb1290d21125ebde5418e0e544a88f9"
  license "Apache-2.0"

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
  end

  # The build's own virtualenv needs Python 3.12-3.14; the build sandbox's
  # python3 is the Command Line Tools' 3.9. The installed runtime does not use
  # it: it bundles its own Python (see install).
  depends_on "python@3.13" => :build
  depends_on arch: :arm64
  # :macos alone keeps Linux from building it (test-bot skips it there);
  # Homebrew only accepts a minimum macOS version beside it inside on_macos.
  depends_on :macos
  depends_on SplashMacOSRequirement

  on_macos do
    depends_on macos: :tahoe
  end

  def install
    # Build exactly what an upstream release ships rather than vendoring the
    # source tree: `make package` compiles the Metal engine, bundles a
    # checksum-pinned standalone Python with the runtime's wheels, smoke-tests
    # the staged runtime, and writes the release tarball. Its release.json marks
    # the install as packaged, so models and caches live under
    # ~/Library/Application Support/Splash, never in the Cellar, and survive
    # upgrades.
    system "make", "package", "RELEASE_VERSION=#{version}",
           "PYTHON_CANDIDATES=#{formula_opt_bin("python@3.13")}/python3.13"
    release = "splash-#{version}-arm64-macos26"
    system "tar", "-xzf", "dist/#{release}.tar.gz"
    libexec.install Dir["#{release}/*"]

    # The same launcher upstream's formula writes: the bundled Python runs the
    # launcher, never a python3 from the user's PATH.
    (bin/"splash").write <<~SH
      #!/bin/sh
      export PYTHONDONTWRITEBYTECODE=1
      exec "#{opt_libexec}/python/bin/python3" -u "#{opt_libexec}/install/launcher.py" "$@"
    SH
    chmod 0755, bin/"splash"
    zsh_completion.install_symlink libexec/"install/completions/_splash"
    bash_completion.install_symlink libexec/"install/completions/splash.bash" => "splash"
    fish_completion.install_symlink libexec/"install/completions/splash.fish"
  end

  def caveats
    <<~EOS
      Serve a model:
        splash serve --model unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M

      This build adds JIT mode: repeat --model (or pass --all-models) to serve
      several models from one server. Each request loads the model it names,
      one at a time, and an idle model unloads after --model-ttl (default 5m;
      off keeps it loaded):
        splash serve --model unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M \\
          --model unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_M

      Security:
        The server listens on 127.0.0.1:8000 (loopback only) without
        authentication by default. Before widening it with --host, set
        --api-key (or SPLASH_API_KEY).

      This formula and upstream's incoai/tap/splash both install `splash`.
      If upstream's is installed, remove it first; installed models are kept:
        brew uninstall incoai/tap/splash
    EOS
  end

  test do
    # --version and --help print and exit without touching models, the
    # network or ~/Library, so they check the bundled runtime deterministically.
    assert_match version.to_s, shell_output("#{bin}/splash --version")
    assert_match "serve", shell_output("#{bin}/splash --help")
  end
end
