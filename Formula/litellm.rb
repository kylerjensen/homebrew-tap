class Litellm < Formula
  desc "OpenAI-compatible proxy server and gateway for 100+ LLM providers"
  homepage "https://litellm.ai"

  # Upstream embeds a compiled Rust bridge (litellm/rust_bridge/_native.abi3.so),
  # so building the PyPI sdist from source would drag in a full Rust toolchain.
  # Instead install upstream's prebuilt cp310-abi3 platform wheels (stable ABI,
  # any Python >= 3.10), selected per arch like llama-swap.rb. sha256s are
  # the PyPI digests. `using: :nounzip` keeps the .whl staged as a plain file:
  # Homebrew would otherwise unzip it (zip magic) and pip needs the real wheel.
  # The arm64 wheel is the top-level `url` and only the Intel one sits in an
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
  url "https://files.pythonhosted.org/packages/40/3b/a060486a4cb637d2aff7bedd2d9bdd807793cf8820153bca74fd14d7cbd4/litellm-1.105.1-cp310-abi3-macosx_11_0_arm64.whl", using: :nounzip
  version "1.105.1"
  sha256 "3253da7d4967e367fb7e4e404b598a26037c45ba6d67a79356a81d3f8b9f9f3a"
  license "MIT"

  bottle do
    root_url "https://ghcr.io/v2/kylerjensen/tap"
    rebuild 1
    sha256 cellar: :any, arm64_tahoe: "7512a51096b6fbda3ca1119cbd623d69e70544e4d91bb679857b1c4dcdade9d7"
  end

  # macOS only: this tap ships macOS installs by owner decision. litellm
  # itself runs on Linux, but the manylinux wheel URLs and the Linuxbrew
  # zlib-linkage workarounds they needed aren't worth maintaining here.
  depends_on :macos

  depends_on "postgresql"

  depends_on "python@3.14"

  # The Intel wheel overrides the top-level arm64 `url` above. The override
  # must sit inside `on_macos`: `brew style` only allows `url` in arch blocks
  # nested under an OS block, and a top-level `url` is required for
  # `brew readall`'s Linux simulation (see the comment above).
  on_macos do
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
    # The wheel's `extra_proxy` extra is what UI/DB mode needs at runtime: the
    # proxy imports `prisma` whenever DATABASE_URL is set, and dies with
    # ModuleNotFoundError without it. That extra also carries KMS/email/redis
    # packages this tap doesn't need, and psycopg is already pulled in via
    # [proxy] (litellm-proxy-extras), so install prisma directly, at the same
    # range the wheel metadata declares for it.
    system libexec/"venv/bin/pip", "install", "--no-cache-dir", "./#{wheel}[proxy]", "prisma>=0.11.0,<1.0"

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

      # `litellm init` provisions everything UI mode needs: it makes sure a
      # PostgreSQL server is reachable (starting the tap's postgresql
      # dependency if nothing is listening yet, running initdb first if the
      # data directory has never been created), creates the `litellm`
      # database, and writes DATABASE_URL plus a generated
      # LITELLM_MASTER_KEY into ~/.litellm/.env. The URL embeds the current
      # user (Prisma's engine sends it verbatim and fails with P1010 "User ``
      # denied" on a scheme+host-only URL), and generates the Prisma client
      # the proxy imports at startup. A server this command started itself
      # gets stopped again on the way out. Safe to re-run.
      if [ "${1:-}" = "init" ]; then
        PG=""
        for f in postgresql postgresql@18 postgresql@17; do
          candidate="$(brew --prefix "$f" 2>/dev/null || true)"
          if [ -n "$candidate" ] && [ -d "$candidate/bin" ]; then
            PG="$candidate"
            break
          fi
        done
        if [ -z "$PG" ]; then
          echo "error: no PostgreSQL install found (expected via the postgresql dependency)." >&2
          exit 1
        fi

        STARTED=0
        DATA=""
        if ! "$PG/bin/pg_isready" -h localhost -q >/dev/null 2>&1; then
          for d in "$PG"/var/postgres*; do
            if [ -f "$d/PG_VERSION" ]; then
              DATA="$d"
              break
            fi
          done
          if [ -z "$DATA" ]; then
            DATA="$PG/var/postgresql"
            mkdir -p "$DATA"
            echo "initializing PostgreSQL data directory at $DATA"
            "$PG/bin/initdb" -D "$DATA" -U "$(whoami)" >/dev/null
          fi
          echo "starting PostgreSQL"
          "$PG/bin/pg_ctl" -D "$DATA" -l "$DATA/litellm-init.log" -w start >/dev/null
          STARTED=1
        fi

        echo "creating database 'litellm'"
        "$PG/bin/createdb" -h localhost litellm 2>/dev/null || echo "  (already exists)"

        mkdir -p "$HOME/.litellm"
        env_file="$HOME/.litellm/.env"
        touch "$env_file"
        grep -q '^LITELLM_MASTER_KEY=' "$env_file" || \
          echo "LITELLM_MASTER_KEY=sk-$(openssl rand -hex 32)" >> "$env_file"
        if grep -q '^DATABASE_URL=' "$env_file"; then
          sed -i '' "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://$(whoami)@localhost:5432/litellm|" "$env_file"
        else
          echo "DATABASE_URL=postgresql://$(whoami)@localhost:5432/litellm" >> "$env_file"
        fi
        chmod 600 "$env_file"

        # Upstream's Docker image bakes `prisma generate` into the build; the
        # pip-installed proxy does not, and without the generated client the
        # proxy starts, errors with "Unable to find Prisma binaries", and
        # exits. The generator shells out to `prisma-client-py`, so the venv's
        # bin dir must be on PATH; engine binaries download into ~/.cache on
        # first run. Re-run on every init (cheap) so an upgraded keg
        # self-heals.
        echo "generating Prisma client"
        SP=""
        for d in "#{libexec}"/venv/lib/python3.*/site-packages; do
          if [ -d "$d" ]; then SP="$d"; break; fi
        done
        if [ -f "$SP/litellm/proxy/schema.prisma" ]; then
          PATH="#{libexec}/venv/bin:$PATH" "#{libexec}/venv/bin/prisma" generate \
            --schema="$SP/litellm/proxy/schema.prisma" >/dev/null
        else
          echo "warning: prisma schema not found under $SP; skipped generate" >&2
        fi

        if [ "$STARTED" = "1" ]; then
          "$PG/bin/pg_ctl" -D "$DATA" -m fast stop >/dev/null
        fi

        echo "done: put 'model_list: []' in ~/.litellm/config.yaml, then brew services start litellm"
        exit 0
      fi

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
      requires a PostgreSQL database; provision everything it needs with:
        litellm init
      This starts the postgresql dependency if nothing is listening, creates
      the `litellm` database, and writes ~/.litellm/.env (DATABASE_URL +
      LITELLM_MASTER_KEY). Then use a config.yaml containing just
      `model_list: []`, start the service, and open
      http://127.0.0.1:4000/ui (log in with the master key). `litellm init`
      also generates the Prisma client and (on first run only) downloads
      Prisma's engine binaries into ~/.cache; re-run it after any version
      upgrade so the new keg gets a freshly generated client.

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
