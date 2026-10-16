class Litellm < Formula
  desc "OpenAI-compatible proxy server and gateway for 100+ LLM providers"
  homepage "https://litellm.ai"
  version "1.105.1"
  license "MIT"

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
  end

  # macOS only: this tap ships macOS installs by owner decision. litellm
  # itself runs on Linux, but the manylinux wheel URLs and the Linuxbrew
  # zlib-linkage workarounds they needed aren't worth maintaining here.
  depends_on :macos

  depends_on "python@3.14"

  # Upstream embeds a compiled Rust bridge (litellm/rust_bridge/_native.abi3.so),
  # so building the PyPI sdist from source would drag in a full Rust toolchain.
  # Instead install upstream's prebuilt cp310-abi3 platform wheels (stable ABI,
  # any Python >= 3.10), selected per arch like llama-swap.rb. sha256s are
  # the PyPI digests. `using: :nounzip` keeps the .whl staged as a plain file:
  # Homebrew would otherwise unzip it (zip magic) and pip needs the real wheel.
  on_macos do
    on_arm do
      url "https://files.pythonhosted.org/packages/40/3b/a060486a4cb637d2aff7bedd2d9bdd807793cf8820153bca74fd14d7cbd4/litellm-#{version}-cp310-abi3-macosx_11_0_arm64.whl", using: :nounzip
      sha256 "3253da7d4967e367fb7e4e404b598a26037c45ba6d67a79356a81d3f8b9f9f3a"
    end
    on_intel do
      url "https://files.pythonhosted.org/packages/d7/71/72b0e4c54a8fb0e10a35adb611f2f03febc27ac4fdf9b372c4f4a7d53442/litellm-#{version}-cp310-abi3-macosx_10_12_x86_64.whl", using: :nounzip
      sha256 "633886584ffb6421485349376f2c1666d4854fecc3ab8b1cdb24537817d4e1cc"
    end
  end

  # Compiled deps (the Rust bridge, tiktoken, granian, polars, ...) ship
  # linker-signed Mach-O with @rpath LC_ID_DYLIBs and no headerpad reserved.
  # Homebrew's install-name relocation tries to rewrite IDs it does not
  # preserve to absolute prefix paths and fails ("needs to be relinked").
  # Leaving @rpath IDs alone is harmless since Python loads extensions by
  # file path, never by their Mach-O ID (same fix as kiro-gateway.rb's
  # tiktoken). psycopg_binary's bundled dylibs arrive with /DLC/... IDs,
  # which this flag does not exempt, so install rewrites those to @rpath
  # first (see below).
  preserve_rpath

  def install
    # Private venv in libexec (the kiro-gateway pattern). litellm IS a regular
    # PyPI package, but its [proxy] extra pulls ~100 dependencies; pinning them
    # all as Homebrew `resource` blocks isn't practical, so pip resolves them
    # from PyPI at build time. The url above still pins litellm itself exactly
    # (sha256-verified wheel file); deps float within the ranges the wheel's
    # metadata declares.
    system formula_opt_bin("python@3.14")/"python3.14", "-m", "venv", libexec/"venv"
    wheel = Dir["litellm-*.whl"].fetch(0)
    system libexec/"venv/bin/pip", "install", "--no-cache-dir", "./#{wheel}[proxy]"

    # psycopg-binary (pulled in via the [proxy] extra, through litellm-proxy-
    # extras) bundles a self-contained libpq/OpenSSL/krb5/LDAP stack in
    # psycopg_binary/.dylibs/. Upstream builds each of those dylibs with a
    # /DLC/... placeholder install name: an absolute path, so the
    # preserve_rpath above does not exempt it, and Homebrew's post-install
    # rewrite to a prefix path overflows the name buffer (HeaderPadError:
    # "needs to be relinked"), failing the install. Rewrite each ID to
    # @rpath/<basename> first: shorter than the /DLC path, so it fits the
    # existing buffer, and exempt under preserve_rpath. Re-sign each file
    # afterwards, since the edit invalidates the ad-hoc signature. Runtime is
    # unaffected: the stack is resolved purely through @loader_path
    # references, and Python loads it by file path, never by Mach-O ID.
    require "macho"
    site_pkg = Dir["#{libexec}/venv/lib/python3.*/site-packages"].first
    dylib_dir = "#{site_pkg}/psycopg_binary/.dylibs" if site_pkg
    if dylib_dir && File.directory?(dylib_dir)
      Dir["#{dylib_dir}/*"].each do |dylib|
        macho_file = MachO.open(dylib)
        next unless macho_file.dylib?

        macho_file.change_dylib_id("@rpath/#{File.basename(dylib)}")
        macho_file.write!
        system "codesign", "--force", "--sign", "-", dylib
      end
    end

    # Launcher rather than a plain symlink to libexec/venv/bin/litellm so that
    # ~/.litellm/.env is loaded into the environment when the service starts.
    # Two reasons this has to happen here: (1) litellm's own import-time
    # load_dotenv() resolves relative to the calling module's directory
    # (site-packages), never the user's cwd or home, so it can't find this
    # file; (2) brew services generates a launchd plist with no user-
    # injectable environment. The file is parsed with python-dotenv
    # (already a litellm dependency) instead of bash `source`, so values
    # containing `$`, spaces, or quotes survive verbatim, matching how
    # litellm itself reads .env files.
    (bin/"litellm").write <<~EOS
      #!/bin/bash
      set -e

      env_file="$HOME/.litellm/.env"
      if [ -f "$env_file" ]; then
        eval "$("#{libexec}/venv/bin/python3" - "$env_file" <<'PY'
      import shlex, sys
      from dotenv import dotenv_values
      for key, value in dotenv_values(sys.argv[1]).items():
          if value is not None:
              print("export %s=%s" % (shlex.quote(str(key)), shlex.quote(value)))
      PY
      )"
      fi

      exec "#{libexec}/venv/bin/litellm" "$@"
    EOS
  end

  service do
    # litellm exits non-zero if the --config file is missing, and also refuses
    # to start without a master key, so the service is not configless: it
    # reads ~/.litellm/config.yaml, and the launcher loads
    # LITELLM_MASTER_KEY from ~/.litellm/.env, both created by the user first
    # (see caveats), same as llama-swap/olla. Dir.home resolves to
    # the installing user's home at formula-eval time -- "~" is not expanded
    # inside the generated launchd plist, so an absolute path is required.
    # Bind to loopback only by default: litellm's own default is
    # 0.0.0.0:4000 (all interfaces), which this tap deliberately narrows for a
    # single-user Homebrew install. Widen it by editing the --host value.
    run [opt_bin/"litellm", "--config", "#{Dir.home}/.litellm/config.yaml", "--host", "127.0.0.1", "--port", "4000"]
    keep_alive true
    working_dir "#{Dir.home}/.litellm"
    log_path var/"log/litellm.log"
    error_log_path var/"log/litellm.log"
  end

  def caveats
    <<~EOS
      litellm will not start without a config file and a master key.
      Before starting the service, create the directory and a config file at:
        ~/.litellm/config.yaml

      Config-file mode (models defined in YAML), minimal example:
        mkdir -p ~/.litellm
        cat > ~/.litellm/config.yaml <<'YAML'
        model_list:
          - model_name: my-model
            litellm_params:
              model: openai/gpt-4o
              api_key: os.environ/OPENAI_API_KEY
        YAML

      The proxy also refuses to start unless a master key is set (it would
      otherwise accept every request unauthenticated), so also create:
        echo "LITELLM_MASTER_KEY=sk-$(openssl rand -hex 32)" > ~/.litellm/.env
      The launcher loads ~/.litellm/.env automatically at service start, so
      provider keys referenced as os.environ/... can live there too. Send the
      master key as "Authorization: Bearer <key>" on each request. Full
      config reference: https://docs.litellm.ai/docs/proxy/configs

      The proxy serves an OpenAI-compatible API at http://127.0.0.1:4000.

      UI mode (manage models, keys, and budgets in a web UI instead of YAML)
      additionally requires a Postgres database:
        brew install postgresql@18
        brew services start postgresql@18
        $(brew --prefix postgresql@18)/bin/createdb litellm
      then add to ~/.litellm/.env:
        DATABASE_URL=postgresql://<your username>@localhost:5432/litellm
      use a config.yaml containing just `model_list: []`, start the service,
      and open http://127.0.0.1:4000/ui (log in with the master key).

      Security:
        The bundled service binds to 127.0.0.1:4000 only; litellm's own default
        is 0.0.0.0 (all interfaces). To expose it on the network, edit the
        --host value in the service definition; the master key is always
        required for startup and authenticates every request.

      Homebrew service:
        brew services start litellm
        brew services info litellm
        brew services stop litellm

      Running manually (any host/port you choose):
        litellm --config ~/.litellm/config.yaml --host 127.0.0.1 --port 4000
    EOS
  end

  test do
    # --version prints and exits before any config parsing, so it is a
    # config-free, deterministic check that the venv + wheel install is wired
    # up correctly. LITELLM_LOCAL_MODEL_COST_MAP=True keeps the test offline:
    # without it, importing litellm refreshes the model cost map over the
    # network (falling back to the bundled copy) and caches it under $HOME.
    assert_match version.to_s,
                 shell_output("LITELLM_LOCAL_MODEL_COST_MAP=True #{bin}/litellm --version 2>&1")
  end
end
