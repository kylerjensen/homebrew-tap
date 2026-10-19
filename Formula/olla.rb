class Olla < Formula
  desc "Proxy and load balancer for self-hosted LLM inference backends"
  homepage "https://github.com/thushan/olla"

  # No explicit `version`: Homebrew scans it (0.0.29) from the release URL below,
  # and `brew audit` flags a declared version that duplicates the URL-scanned one
  # (this is why llama-swap, whose bare-integer version is NOT cleanly scannable
  # from its URL, does declare one). Bump by editing the v0.0.29 / olla_v0.0.29_
  # literals in each URL below; the detected version follows automatically.
  # The arm64 archive is the top-level `url` and only the Intel one sits in an
  # `on_macos` block (see below): `brew test-bot --only-tap-syntax` runs
  # `brew readall`, which loads every formula under a Linux tag too and fails
  # with "formula requires at least a URL" if every `url` hides behind
  # `on_macos`, and `brew style` rejects `url` inside a top-level
  # `on_arm`/`on_intel` block. `depends_on :macos` keeps the Linux evaluation
  # from ever installing anything.
  url "https://github.com/thushan/olla/releases/download/v0.0.29/olla_v0.0.29_macos_arm64.zip"
  sha256 "a879d1247090b3d85a774e0890241234b7055ec87904292313ea42c6ce7fe0b4"
  license "Apache-2.0"

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
    rebuild 2
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "b0cc438af90f0b7a8503a2a82a7d1f76886a9b2abc9b7b6b9b75d351068d636c"
  end

  # macOS only: the tap ships macOS installs by owner decision. olla is
  # cross-platform upstream, but Linux archives aren't fetched or tested here.
  depends_on :macos

  # Upstream ships prebuilt, per-arch release archives via goreleaser (no
  # `go build` needed), so select the right darwin .zip by CPU rather than
  # vendoring + compiling. The source sha256s are the upstream release
  # checksums (checksums.txt). CI still bottles whatever `install` lays down
  # and publishes it to GHCR (see the bottle block + CLAUDE.md), so
  # private-repo users get a working `brew install` without re-fetching the
  # GitHub release. The Intel archive overrides the top-level arm64 `url`
  # above, from inside `on_macos` (the one place `brew style` allows an
  # arch-conditional `url`).
  on_macos do
    on_intel do
      url "https://github.com/thushan/olla/releases/download/v0.0.29/olla_v0.0.29_macos_amd64.zip"
      sha256 "b70b6bdcb9b182ed2019bb2634f7752feb6c7c316df938cf2a1b679d8f5ba464"
    end
  end

  def install
    bin.install "olla"
    # No mkpath for a config dir here: it lives at ~/.olla (see the service
    # block), and Homebrew's build sandbox denies writes outside its own prefix,
    # so the directory + config.yaml must be created by the user before starting
    # the service (see caveats).
  end

  service do
    # olla is configless-until-configured like llama-swap: with no config it starts
    # but routes nothing, so the service points it at ~/.olla/config.yaml, which
    # the user must create first (see caveats). Dir.home resolves to the
    # installing user's home at formula-eval time -- "~" is not expanded inside
    # the generated launchd plist, so an absolute path is required.
    # working_dir is the same dir so olla's relative ./logs (it MkdirAll's it)
    # stays under the user's home. It binds to localhost:40114 by default
    # (loopback only); widen it by setting server.host in the config.
    run [opt_bin/"olla", "--config", "#{Dir.home}/.olla/config.yaml"]
    keep_alive true
    working_dir "#{Dir.home}/.olla"
    log_path var/"log/olla.log"
    error_log_path var/"log/olla.log"
  end

  def caveats
    <<~EOS
      olla reads a YAML config and will not route any traffic without at least one
      backend endpoint defined in it. Before starting the service, create the
      directory and a config file at:
        ~/.olla/config.yaml

      A minimal config routes to a single local Ollama instance, e.g.:
        mkdir -p ~/.olla
        cat > ~/.olla/config.yaml <<'YAML'
        server:
          host: "localhost"
          port: 40114
        discovery:
          type: "static"
          static:
            endpoints:
              - url: "http://localhost:11434"
                name: "local-ollama"
                type: "ollama"
                priority: 100
        YAML

      Add one endpoint per backend you run (Ollama, vLLM, llama.cpp, LM Studio,
      SGLang, LiteLLM, ...). The full reference config, per-provider profiles, and
      documentation are upstream:
        https://github.com/thushan/olla/blob/main/config/config.yaml
        https://thushan.github.io/olla/configuration/overview/

      olla exposes an OpenAI-compatible API at http://localhost:40114/olla/proxy/
      and an Anthropic Messages API at http://localhost:40114/olla/anthropic/.

      Security:
        By default olla listens on localhost:40114 (loopback only). To expose it on
        the network, set server.host: "0.0.0.0" in your config; there is no
        built-in API auth, so keep it to a trusted network if you do.

      Homebrew service:
        brew services start olla
        brew services info olla
        brew services stop olla

      Running manually (any host/port you choose in the config):
        olla --config ~/.olla/config.yaml
    EOS
  end

  test do
    # --version prints the version banner and exits 0 before any config is loaded,
    # so it is a config-free, deterministic check that the binary unpacked and runs.
    # The banner goes to stderr, hence 2>&1.
    assert_match version.to_s, shell_output("#{bin}/olla --version 2>&1")
  end
end
