class Olla < Formula
  desc "Proxy and load balancer for self-hosted LLM inference backends"
  homepage "https://github.com/thushan/olla"
  license "Apache-2.0"

  # No explicit `version`: Homebrew scans it (0.0.29) from the release URL below,
  # and `brew audit` flags a declared version that duplicates the URL-scanned one
  # (this is why llama-swap, whose bare-integer version is NOT cleanly scannable
  # from its URL, does declare one). Bump by editing the v0.0.29 / olla_v0.0.29_
  # literals in each URL below; the detected version follows automatically.

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:  "7ba575a5236dae453a31267b18829d8f799c640fa8e6d3bbefc8e9b575c54a25"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "0cfecb6cdbb03c438685a832db2a97a7f5b91d9fc09e5e3a832c12fc5be669f2"
  end

  # Upstream ships prebuilt, per-OS/per-arch release archives via goreleaser (no
  # `go build` needed), so select the right archive by platform rather than
  # vendoring + compiling. macOS archives are .zip; Linux are .tar.gz. The
  # source sha256s are the upstream release checksums (checksums.txt). CI still
  # bottles whatever `install` lays down and publishes it to GHCR (see the
  # bottle block + CLAUDE.md), so private-repo users get a working `brew install`
  # without re-fetching the GitHub release.
  on_macos do
    on_arm do
      url "https://github.com/thushan/olla/releases/download/v0.0.29/olla_v0.0.29_macos_arm64.zip"
      sha256 "a879d1247090b3d85a774e0890241234b7055ec87904292313ea42c6ce7fe0b4"
    end
    on_intel do
      url "https://github.com/thushan/olla/releases/download/v0.0.29/olla_v0.0.29_macos_amd64.zip"
      sha256 "b70b6bdcb9b182ed2019bb2634f7752feb6c7c316df938cf2a1b679d8f5ba464"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/thushan/olla/releases/download/v0.0.29/olla_v0.0.29_linux_arm64.tar.gz"
      sha256 "7a632ba3bf53a1b37b9de57d7d472099134c96f0d0b6f644379012e57c8efda7"
    end
    on_intel do
      url "https://github.com/thushan/olla/releases/download/v0.0.29/olla_v0.0.29_linux_amd64.tar.gz"
      sha256 "fafb482e50def1f56f210ef28b46c67021bb6e25b0ff0a595682e2aac214fcc4"
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
    # the generated launchd plist/systemd unit, so an absolute path is required.
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
