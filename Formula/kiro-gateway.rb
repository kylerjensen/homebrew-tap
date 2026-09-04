class KiroGateway < Formula
  include Language::Python::Virtualenv

  desc "OpenAI/Anthropic-compatible API gateway that bridges to kiro-cli over ACP"
  homepage "https://github.com/ankitcharolia/kiro-gateway"
  # Tracked via a git-tag checkout (not a GitHub tarball download) so `.git`
  # metadata survives into `buildpath` -- upstream derives its package version
  # from git tags via hatch-vcs/setuptools-scm at build time, and a plain
  # tarball has no `.git` for it to read, which makes `pip install .` fail
  # with "setuptools-scm was unable to detect version".
  url "https://github.com/ankitcharolia/kiro-gateway.git",
      using:    :git,
      tag:      "v2.4.1",
      revision: "94f75c13a383b022be82142ae0c09834d0c45016"
  license "AGPL-3.0-only"

  depends_on "rust" => :build
  depends_on "libyaml"
  depends_on "python@3.14"

  resource "annotated-doc" do
    url "https://files.pythonhosted.org/packages/5a/8e/38aa427ed5402449e226975b649c5dc73ccadfefeb95e6aecb8f8ea4b6b6/annotated_doc-0.0.5.tar.gz"
    sha256 "c7e58ce09192557605d8bbd92836d7e1d520ac9580096042c0bfd197efacf1bb"
  end

  resource "annotated-types" do
    url "https://files.pythonhosted.org/packages/5f/56/a8120250d128bed162cd73c76d45f6ef9991f3e068f62a8ee060afa3104a/annotated_types-0.8.0.tar.gz"
    sha256 "13b2beaad985e05e2d6407ee4c4f35590b11f8d693a258a561055cac8f64cab7"
  end

  resource "anyio" do
    url "https://files.pythonhosted.org/packages/ea/9a/c15a60547004a3f3cea20296c934f827ddd7bdba225a2e7e9fcb5ec48c80/anyio-4.15.0.tar.gz"
    sha256 "b5c620ed540725e2579c31b17bb995b3bf02c9281c9cace04c7d186380bab85e"
  end

  resource "certifi" do
    url "https://files.pythonhosted.org/packages/a3/c2/24167ea9858356b47a87a50d39908bfdb72ceeefe0041586e704e5376b3a/certifi-2026.7.22.tar.gz"
    sha256 "741e2c3b351ddf169a738da9f2c048608ff7f2c5cc02f1ebc6b118bb090d5d55"
  end

  resource "charset-normalizer" do
    url "https://files.pythonhosted.org/packages/e5/3f/143b048436775b0f76ac3eec145c019e8173ccc2885c8f20319b996d5e83/charset_normalizer-3.5.1.tar.gz"
    sha256 "6117b84ea48435e5356dc737f5121485c30920ba43375fa7b434fd753df0eac3"
  end

  resource "click" do
    url "https://files.pythonhosted.org/packages/c7/0e/7fa0ef50764b67090eca4114772a2abf8b6148198475e54c660b97caeee6/click-8.5.0.tar.gz"
    sha256 "ba0d2089de75ea0310e2dde03160e6ca10009947fb95a182f9b54021bb272e34"
  end

  resource "fastapi" do
    url "https://files.pythonhosted.org/packages/8a/02/91e3416a8fdd715abb903a952a6bec7cdd8d14eed55d415fc8595524c319/fastapi-0.141.1.tar.gz"
    sha256 "e8822fc40db1e1858054d7a949a888695bc9bdce70139178e33bd2871a453ca1"
  end

  resource "h11" do
    url "https://files.pythonhosted.org/packages/01/ee/02a2c011bdab74c6fb3c75474d40b3052059d95df7e73351460c8588d963/h11-0.16.0.tar.gz"
    sha256 "4e35b956cf45792e4caa5885e69fba00bdbc6ffafbfa020300e549b208ee5ff1"
  end

  resource "httpcore" do
    url "https://files.pythonhosted.org/packages/06/94/82699a10bca87a5556c9c59b5963f2d039dbd239f25bc2a63907a05a14cb/httpcore-1.0.9.tar.gz"
    sha256 "6e34463af53fd2ab5d807f399a9b45ea31c3dfa2276f15a2c3f00afff6e176e8"
  end

  resource "httptools" do
    url "https://files.pythonhosted.org/packages/43/e5/d471fcb0e14523fe1c3f4ba58ca52480e7bd70ad7109a3846bc75892f7fb/httptools-0.8.0.tar.gz"
    sha256 "6b2a32f18d97e16e90827d7a819ffa8dbd8cc245fc4e1fa9d1095b54ef4bd999"
  end

  resource "httpx" do
    url "https://files.pythonhosted.org/packages/b1/df/48c586a5fe32a0f01324ee087459e112ebb7224f646c0b5023f5e79e9956/httpx-0.28.1.tar.gz"
    sha256 "75e98c5f16b0f35b567856f597f06ff2270a374470a5c2392242528e3e3e42fc"
  end

  resource "idna" do
    url "https://files.pythonhosted.org/packages/5f/f7/abb373e5757eaec4b922b92f97ec8d6d7e057cf06778247604fbc4e7c3f3/idna-3.19.tar.gz"
    sha256 "5e0811a4383b21dc5838069f801c4fb62113b7447663d2530d2bd6e77b49bf15"
  end

  resource "loguru" do
    url "https://files.pythonhosted.org/packages/3a/05/a1dae3dffd1116099471c643b8924f5aa6524411dc6c63fdae648c4f1aca/loguru-0.7.3.tar.gz"
    sha256 "19480589e77d47b8d85b2c827ad95d49bf31b0dcde16593892eb51dd18706eb6"
  end

  resource "pydantic" do
    url "https://files.pythonhosted.org/packages/53/ef/fc4f868f4e2cee79f863883abffceff107875f569b848507319842d2a681/pydantic-2.13.5.tar.gz"
    sha256 "51a9c5f7b2f8e636f04c6cada605d9b6a3bf1348fdf945a3d8869b19bba0ee08"
  end

  resource "pydantic-core" do
    url "https://files.pythonhosted.org/packages/af/f9/8a06bea35ef8daf588f707784c973a7046e0034c8d8cfb08828eeffb8b75/pydantic_core-2.46.5.tar.gz"
    sha256 "10416c15b8839ecc4ef4d0885da76da6fd0f67333a0eb8aff6d93c4b8f2910fc"
  end

  resource "pypdf" do
    url "https://files.pythonhosted.org/packages/44/66/54212e75406afd9f3e933d0dda23072f6aecc55c5a273077dc2e0b028b23/pypdf-6.16.2.tar.gz"
    sha256 "595647f6191de6f402cfde1d0c455d6cbccbd509aac32b34783009c032de5d6e"
  end

  resource "python-dotenv" do
    url "https://files.pythonhosted.org/packages/6a/53/ed9d74092561d4b01a2ef1349d52cdbc135e526c245f366b089cfca6de49/python_dotenv-1.2.3.tar.gz"
    sha256 "a20a594dabeaa385725aa239d5244871c143ecb356add8a20fcf23773a6c3a35"
  end

  resource "pyyaml" do
    url "https://files.pythonhosted.org/packages/05/8e/961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/pyyaml-6.0.3.tar.gz"
    sha256 "d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f"
  end

  resource "regex" do
    url "https://files.pythonhosted.org/packages/19/c1/6b30b775c7bcc6cf6506a4d4741c2123e8d99cd50f3fe8cbd731f5fef526/regex-2026.9.3.tar.gz"
    sha256 "aabd43208e335f4c3f0b56de3464b066dd425983a58f6eeb5738bcd7465403db"
  end

  resource "requests" do
    url "https://files.pythonhosted.org/packages/ac/c3/e2a2b89f2d3e2179abd6d00ebd70bff6273f37fb3e0cc209f48b39d00cbf/requests-2.34.2.tar.gz"
    sha256 "f288924cae4e29463698d6d60bc6a4da69c89185ad1e0bcc4104f584e960b9ed"
  end

  resource "starlette" do
    url "https://files.pythonhosted.org/packages/b5/b4/205b0d5241d934e8add0c38aa924c4f9fb7330834ff11e5444db964ec3f9/starlette-1.6.0.tar.gz"
    sha256 "d4e3ac5e546444960c710297a3c9fc3f7ebae1b7e963f3d36173b49da535be9b"
  end

  resource "tiktoken" do
    url "https://files.pythonhosted.org/packages/66/62/167a842aa0429d45f5e797354fd4343a96f6043d67d0513c675c7b8d36e6/tiktoken-0.14.0.tar.gz"
    sha256 "231dec90efcdccf1b565a1416107736f1e09b1a08fe736ef9d6363e626d03874"
  end

  resource "typing-extensions" do
    url "https://files.pythonhosted.org/packages/f6/cc/6253133b5bb138fc3306cebfbda2c520f545d36b5be2c7255cc528bb45d6/typing_extensions-4.16.0.tar.gz"
    sha256 "dc983d19a509c94dba722ee6abd33940f7c05a89e243c47e907eb4db6f1a43e5"
  end

  resource "typing-inspection" do
    url "https://files.pythonhosted.org/packages/a3/26/b09b8010994eccc3c09092e6b34058f36a460eea2d4c3e8b910c695975a0/typing_inspection-0.4.4.tar.gz"
    sha256 "547274fa6b0a561ccf549cc9524b999a578e737d015d8709d021f9d0d13bea47"
  end

  resource "urllib3" do
    url "https://files.pythonhosted.org/packages/53/0c/06f8b233b8fd13b9e5ee11424ef85419ba0d8ba0b3138bf360be2ff56953/urllib3-2.7.0.tar.gz"
    sha256 "231e0ec3b63ceb14667c67be60f2f2c40a518cb38b03af60abc813da26505f4c"
  end

  resource "uvicorn" do
    url "https://files.pythonhosted.org/packages/f2/0f/3f86e61397dd33bf2ccf28188c40db6a740658aeebbbf6e7dbc101a1f487/uvicorn-0.52.4.tar.gz"
    sha256 "73acfee47a0b133c5de13d219492d62d8a31e935f4fe6e41a232451a15379f86"
  end

  resource "uvloop" do
    url "https://files.pythonhosted.org/packages/06/f0/18d39dbd1971d6d62c4629cc7fa67f74821b0dc1f5a77af43719de7936a7/uvloop-0.22.1.tar.gz"
    sha256 "6c84bae345b9147082b17371e3dd5d42775bddce91f885499017f4607fdaf39f"
  end

  resource "watchfiles" do
    url "https://files.pythonhosted.org/packages/cd/41/5e1a4bb12aac5f1493fa1bdc11154eca3b258ca4eba65d39c473fe19d8e9/watchfiles-1.2.0.tar.gz"
    sha256 "c995fba777f1ea992f090f9236e9284cf7a5d1a0130dd5a3d82c598cacd76838"
  end

  resource "websockets" do
    url "https://files.pythonhosted.org/packages/18/72/fba934cb3dff7a85d811820efffcd141ddd52b5a2a01637f64551373ff4d/websockets-17.1.tar.gz"
    sha256 "acfea4c20bf54384883ea33b1240fc1db4f52e190823a4e2b334bc3e8bfca96a"
  end

  def install
    virtualenv_install_with_resources

    # kiro.cli's `serve` subcommand runs `uvicorn.run("main:app", ...)`, which
    # imports `main` as a top-level module by name -- but the wheel only
    # packages the `kiro/` package (per upstream's
    # [tool.hatch.build.targets.wheel]), not the repo-root main.py. Install a
    # copy next to the venv so it's importable when the launcher below runs
    # with libexec as its working directory.
    libexec.install "main.py"

    # virtualenv_install_with_resources already symlinked the venv's raw
    # "kiro-gateway" console script (kiro.cli:main) into bin -- replace it
    # with a wrapper that runs main.py directly instead, since the console
    # script's `serve` subcommand can't import "main" (see above).
    (bin/"kiro-gateway").unlink
    (bin/"kiro-gateway").write <<~EOS
      #!/bin/bash
      # main.py must be importable by module name (see the comment in
      # `install` above), so run from libexec rather than "exec"ing the venv's
      # installed console script directly. virtualenv_install_with_resources
      # creates the venv at libexec itself (not libexec/venv).
      cd "#{libexec}" || exit 1
      exec "#{libexec}/bin/python3" main.py "$@"
    EOS
  end

  def post_install
    (var/"kiro-gateway").mkpath
    env_file = var/"kiro-gateway/.env"
    unless env_file.exist?
      # Homebrew installs are single-user, single-machine, so this binds to
      # loopback only. KIRO_GATEWAY_API_KEY has no safe default upstream
      # (ships as literal "change-me"), so generate a random secret rather
      # than leaving it guessable.
      require "securerandom"
      env_file.write <<~EOS
        SERVER_HOST=127.0.0.1
        SERVER_PORT=8000
        KIRO_GATEWAY_API_KEY=#{SecureRandom.hex(32)}

        # KIRO_CLI_PATH defaults to "kiro-cli" resolved via $PATH. Set this to
        # an absolute path if kiro-cli isn't on PATH for services started by
        # launchd (see caveats).
        #KIRO_CLI_PATH=kiro-cli
      EOS
    end
    ln_sf env_file, libexec/".env"
  end

  service do
    run [opt_bin/"kiro-gateway"]
    keep_alive true
    working_dir var/"kiro-gateway"
    log_path var/"log/kiro-gateway.log"
    error_log_path var/"log/kiro-gateway.log"
  end

  def caveats
    <<~EOS
      kiro-gateway v2.4.1 (ankitcharolia/kiro-gateway) is an ACP bridge, not a
      credential proxy: it never reads or stores Kiro credentials itself.
      Instead it shells out to the official kiro-cli binary, so you need:

        1. kiro-cli installed (it's a cask, not a formula in this tap):
             brew install --cask kiro-cli
        2. Authenticated once, out of band:
             kiro-cli login

      #{var}/kiro-gateway/.env binds to 127.0.0.1 only and has a randomly
      generated KIRO_GATEWAY_API_KEY -- clients must send this as their
      bearer/x-api-key. Find it with:
        grep KIRO_GATEWAY_API_KEY #{var}/kiro-gateway/.env

      By default the gateway looks for "kiro-cli" on $PATH. brew services
      runs under launchd with a minimal PATH, so if `kiro-cli` isn't on it,
      set KIRO_CLI_PATH in the .env above to kiro-cli's absolute path, e.g.:
        KIRO_CLI_PATH="/Applications/Kiro CLI.app/Contents/MacOS/kiro-cli"

      See upstream's README for the full list of tunable options (MCP,
      ACP engine/agent/model pins, tool-call surfacing, etc.):
        https://github.com/ankitcharolia/kiro-gateway#configuration

      Homebrew service:
        brew services start kiro-gateway
        brew services info kiro-gateway
        brew services stop kiro-gateway
    EOS
  end

  test do
    # No Kiro-credentials fail-fast path exists in this fork (auth lives
    # entirely inside kiro-cli), so the only environment-independent thing to
    # assert is that the interpreter, venv, and vendored `kiro` package all
    # wired up correctly and agree on the version derived from the git tag.
    assert_match version.to_s, shell_output("#{bin}/kiro-gateway --version 2>&1")
  end
end
