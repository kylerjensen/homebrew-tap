class LlamaSwap < Formula
  desc "Proxy server for swapping models on llama.cpp"
  homepage "https://github.com/mostlygeek/llama-swap"
  version "264"
  license "MIT"

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "0ff3158453b3c479223360c2275c86b541293f376b4edb63dfa7179f9e53063a"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "eaa15e339d450e33753340a9ca39229e6f5c67087947ebfbbcf41a24953b4922"
  end

  # Upstream ships prebuilt, per-OS/per-arch release tarballs (no `go build`
  # from source needed), so select the right archive by platform rather than
  # vendoring + compiling. sha256s are the upstream release checksums
  # (llama-swap_<version>_checksums.txt). CI still bottles whatever `install`
  # lays down and publishes it to GHCR (see the bottle block + CLAUDE.md), so
  # private-repo users get a working `brew install` without re-fetching the
  # GitHub release.
  on_macos do
    on_arm do
      url "https://github.com/mostlygeek/llama-swap/releases/download/v#{version}/llama-swap_#{version}_darwin_arm64.tar.gz"
      sha256 "a0beb847db08945dcabe5ee6a9ae7a18876be24d159eaf775679f11a453526dd"
    end
    on_intel do
      url "https://github.com/mostlygeek/llama-swap/releases/download/v#{version}/llama-swap_#{version}_darwin_amd64.tar.gz"
      sha256 "8a68d20330df73a71a91bbd9e90ab3cf88ff28cc99df1cfe0026eb1354078de8"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/mostlygeek/llama-swap/releases/download/v#{version}/llama-swap_#{version}_linux_arm64.tar.gz"
      sha256 "cffc26da029d830399d812fa5c9a00fa31bd0967f251eaf07d1270b4f42592ad"
    end
    on_intel do
      url "https://github.com/mostlygeek/llama-swap/releases/download/v#{version}/llama-swap_#{version}_linux_amd64.tar.gz"
      sha256 "ed3569386f0194401b39732e592b881c72223c8a0a49f6a2e1376f1796e3101d"
    end
  end

  def install
    bin.install "llama-swap"
    # No mkpath for the config dir here: it lives at ~/.llama-swap (see the
    # service block), and Homebrew's build sandbox denies writes outside its
    # own prefix, so the directory + config.yaml must be created by the user
    # before starting the service (see caveats).
  end

  service do
    # llama-swap has no default config path and exits non-zero if neither
    # -config nor -config-dir is given, so the service cannot be configless; it
    # reads ~/.llama-swap/config.yaml, which the user must create first (see
    # caveats). Dir.home resolves to the installing user's home at formula-eval
    # time -- "~" is not expanded inside the generated launchd plist/systemd
    # unit, so an absolute path is required here. Bind to loopback only by
    # default: the binary's own default is ":8080" (all interfaces), which this
    # tap deliberately narrows for a single-user Homebrew install. Widen it by
    # editing the -listen value.
    run [opt_bin/"llama-swap", "-config", "#{Dir.home}/.llama-swap/config.yaml", "-listen", "127.0.0.1:8080"]
    keep_alive true
    working_dir "#{Dir.home}/.llama-swap"
    log_path var/"log/llama-swap.log"
    error_log_path var/"log/llama-swap.log"
  end

  def caveats
    <<~EOS
      llama-swap has no default config and will not start without one.
      Before starting the service, create the directory and a config file at:
        ~/.llama-swap/config.yaml

      A minimal config defines at least one model, e.g.:
        mkdir -p ~/.llama-swap
        cat > ~/.llama-swap/config.yaml <<'YAML'
        models:
          "my-model":
            cmd: llama-server --port ${PORT} --model /path/to/model.gguf
        YAML

      See the documented options and example config:
        https://github.com/mostlygeek/llama-swap/blob/main/docs/config.example.yaml

      Security:
        The bundled service binds to 127.0.0.1:8080 only. The llama-swap
        binary's own default is ":8080" (all interfaces); to expose it on the
        network, edit the -listen value in the service definition and consider
        setting apiKeys in your config.

      Homebrew service:
        brew services start llama-swap
        brew services info llama-swap
        brew services stop llama-swap

      Running manually (any listen host/port you choose):
        llama-swap -config ~/.llama-swap/config.yaml -listen :8080
    EOS
  end

  test do
    # -version runs before any config loading and exits 0, so it is a
    # config-free, deterministic check that the binary unpacked and runs.
    assert_match version.to_s, shell_output("#{bin}/llama-swap -version 2>&1")
  end
end
