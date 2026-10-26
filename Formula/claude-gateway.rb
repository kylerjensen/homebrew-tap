class ClaudeGateway < Formula
  desc "Anthropic Messages gateway that routes by model to local and remote backends"
  homepage "https://github.com/kylerjensen/claude-gateway"
  url "https://github.com/kylerjensen/homebrew-tap/releases/download/claude-gateway-0.1.0.3/claude-gateway"
  version "0.1.0.3"

  # The repository has no LICENSE file yet, so there is nothing truthful to
  # declare here. Resolve by adding one upstream rather than by asserting a
  # license in this formula; `brew audit --strict` will keep complaining until then.
  sha256 "4855028e504a996d6cfa1576e1722b1841c19fc9400fd012b95fd5c039a7599c"
  license :cannot_represent

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
  end

  # url, version and sha256 above are rewritten by the gateway's publish-formula
  # workflow on every merge to its main. The gateway source is private, so the
  # workflow builds the binary there and uploads it as a release asset on this
  # (public) tap repo; url points at that asset, version is `<base>.<commit-count>`,
  # and the binary is a single self-contained file (bun compile). The project ships
  # no git tags or GitHub releases of its own. Homebrew keys a bottle by version and
  # rebuild, never by the asset SHA, so the per-commit version keeps bottles distinct
  # (see CLAUDE.md).

  depends_on :macos

  def install
    # The release asset is the bare compiled binary, and its download URL ends in
    # `/claude-gateway`, so Homebrew stages it under that name. Install it straight
    # into bin; there is no build step and no bun here.
    bin.install "claude-gateway"
  end

  def caveats
    <<~EOS
      One-time setup. The gateway reads ~/Library/Application Support/claude-gateway/
      gateway.yaml when given no --config, and a service with no config exits
      non-zero, so create it first:
        claude-gateway init

      `init` writes the built-in example config to the default path and prints
      where it wrote. It refuses to overwrite an existing file. Edit the result to
      change ports, upstreams or models, then:
        brew services start claude-gateway

      It listens on 127.0.0.1:8001, which is what ANTHROPIC_BASE_URL in
      ~/.claude/settings.json already points at. Point Claude Code at it with:
        export ANTHROPIC_BASE_URL=http://127.0.0.1:8001
        export ANTHROPIC_AUTH_TOKEN=any-non-empty-string

      Print the Claude Desktop profile and paste it into
      Developer > Configure Third-Party Inference:
        claude-gateway desktop-config

      The menu bar app is not part of this formula. Homebrew runs builds inside
      `sandbox-exec`, and SwiftPM sandboxes its own manifest compiler, which
      cannot nest: the build dies with `sandbox_apply: Operation not permitted`.
      A formula has no opt-out in Homebrew 7, so the app is shipped separately as
      a prebuilt bundle (see packaging/build.ts and the cask that should carry it)
      or built from a checkout:
        git clone https://github.com/kylerjensen/claude-gateway && cd claude-gateway
        bun packaging/build.ts menubar   # needs the Xcode command line tools
        open dist/GatewayBar.app
    EOS
  end

  service do
    # No --config here: the binary resolves the same default path that `init`
    # writes, so the service and a manual run cannot read different files.
    # "~" is not expanded inside the generated launchd plist, so HOME and the
    # working directory are the installing user's absolute home; the config lookup
    # and the loopback upstream URLs in it both resolve through it.
    run [opt_bin/"claude-gateway"]
    run_at_load true
    keep_alive true
    working_dir Dir.home
    environment_variables HOME: Dir.home, PATH: "/usr/bin:/bin:/usr/sbin:/sbin"
    log_path var/"log/claude-gateway.log"
    error_log_path var/"log/claude-gateway.log"
  end

  test do
    # The version flag must work with no config anywhere, since that is the one
    # assertion that holds on a machine with nothing configured yet.
    assert_match version.to_s, shell_output("#{bin}/claude-gateway --version")

    # `init` must create the config at the path the service reads from the
    # example embedded in the binary, and refuse to clobber one that already
    # exists. HOME is redirected into the test sandbox so this never touches the
    # real ~/Library.
    home = testpath/"home"

    ENV["HOME"] = home.to_s

    shell_output("#{bin}/claude-gateway init")

    seeded = home/"Library/Application Support/claude-gateway/gateway.yaml"

    assert_path_exists seeded

    # The second init refuses and exits 1, so shell_output must be told to expect
    # that status; its default asserts exit 0 and would fail the test on the refusal.
    assert_match "already exists",
                 shell_output("#{bin}/claude-gateway init 2>&1", 1)

    # Answering discovery from config alone with no upstream reachable, and
    # draining on SIGTERM, are the two installed-binary properties that matter:
    # boot must not depend on a backend, and launchd relies on an orderly exit.
    config = testpath/"gateway.yaml"

    config.write <<~YAML
      server:
        port: 8231
      upstreams:
        - id: nowhere
          kind: anthropic
          baseUrl: http://127.0.0.1:8299
          discover: false
      models:
        - name: claude-test-1
          upstream: nowhere
          upstreamModel: fake
    YAML

    out = testpath/"out.log"

    # spawn's redirect value must be a String filename, not a Pathname, or Ruby
    # raises "wrong exec redirect action"; out is a Pathname, so stringify it.
    pid = spawn("#{bin}/claude-gateway", "serve", "--config", config, out: out.to_s, err: out.to_s)

    begin
      ready = false

      40.times do
        ready = quiet_system("curl", "-sf", "http://127.0.0.1:8231/v1/models")

        break if ready

        sleep 0.25
      end

      assert ready, "gateway did not come up: #{File.read(out)}"

      Process.kill("TERM", pid)

      drained = false

      40.times do
        drained = !Process.wait(pid, Process::WNOHANG).nil?

        break if drained

        sleep 0.25
      end

      assert drained, "gateway did not exit after SIGTERM"
    ensure
      Process.kill("KILL", pid) unless drained
    end
  end
end
