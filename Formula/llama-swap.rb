class LlamaSwap < Formula
  desc "Proxy server for swapping models on llama.cpp"
  homepage "https://github.com/mostlygeek/llama-swap"

  # Upstream ships prebuilt, per-arch release tarballs (no `go build` from
  # source needed), so select the right darwin archive by CPU rather than
  # vendoring + compiling. sha256s are the upstream release checksums
  # (llama-swap_<version>_checksums.txt). CI still bottles whatever `install`
  # lays down and publishes it to GHCR (see the bottle block + CLAUDE.md), so
  # private-repo users get a working `brew install` without re-fetching the
  # GitHub release.
  # The arm64 archive is the top-level `url` and only the Intel one sits in an
  # `on_macos` block (see below): `brew test-bot --only-tap-syntax` runs
  # `brew readall`, which loads every formula under a Linux tag too and fails
  # with "formula requires at least a URL" if every `url` hides behind
  # `on_macos`, and `brew style` rejects `url` inside a top-level
  # `on_arm`/`on_intel` block. `depends_on :macos` keeps the Linux evaluation
  # from ever installing anything.
  # The version is spelled out in the URL (not `#{version}`) because
  # `brew style` requires `url` before `version`, and the interpolation would
  # be empty at that point; the `on_intel` override below (evaluated after the
  # `version` line) does interpolate.
  url "https://github.com/mostlygeek/llama-swap/releases/download/v264/llama-swap_264_darwin_arm64.tar.gz"
  version "264"
  sha256 "a0beb847db08945dcabe5ee6a9ae7a18876be24d159eaf775679f11a453526dd"
  license "MIT"

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
    rebuild 1
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "40cc75d928e621a6c84c0cb484ba6511a58789748b37c86cbcd2e3008ac41aae"
  end

  # macOS only: the tap ships macOS installs by owner decision. llama-swap is
  # cross-platform upstream, but Linux archives aren't fetched or tested here.
  depends_on :macos

  # The Intel archive overrides the top-level arm64 `url` above. The override
  # must sit inside `on_macos`: `brew style` only allows `url` in arch blocks
  # nested under an OS block, and a top-level `url` is required for
  # `brew readall`'s Linux simulation (see the comment above).
  on_macos do
    on_intel do
      url "https://github.com/mostlygeek/llama-swap/releases/download/v#{version}/llama-swap_#{version}_darwin_amd64.tar.gz"
      sha256 "8a68d20330df73a71a91bbd9e90ab3cf88ff28cc99df1cfe0026eb1354078de8"
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
    # time -- "~" is not expanded inside the generated launchd plist, so an
    # absolute path is required here. Bind to loopback only by
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
