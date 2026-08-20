class IcloudSync < Formula
  desc "Symlink directories in $HOME into iCloud Drive, with a safe backup"
  homepage "https://github.com/kylerjensen/icloud-sync"
  url "https://github.com/kylerjensen/icloud-sync/releases/download/v1.0.0/icloud-sync-1.0.0.tar.gz"
  sha256 "c8ef52779ef8a1ede949374a22bbf30fae4ba06007b7ea7f25a02262eb133418"
  license "MIT"

  # macOS only: the whole point is iCloud Drive at
  # ~/Library/Mobile Documents/com~apple~CloudDocs, and the tool relies on
  # macOS-specific `chmod -a#` (ACLs) and `chflags hidden`.
  depends_on :macos

  # The release ships a single pre-bundled ESM file with its dependencies
  # (@inquirer/prompts, picocolors) already inlined, so there is no
  # `node_modules` to install here -- only a Node runtime to execute it.
  depends_on "node"

  def install
    libexec.install "dist/icloud-sync.mjs"

    # The bundle has a `#!/usr/bin/env node` shebang, which would resolve
    # whatever `node` happens to be on the user's PATH at runtime. Writing a
    # wrapper instead pins execution to the Node that Homebrew depends on, so
    # the formula keeps working even with a different node on PATH (nvm, asdf,
    # a system install).
    (bin/"icloud-sync").write <<~EOS
      #!/bin/bash
      exec "#{formula_opt_bin("node")}/node" "#{libexec}/icloud-sync.mjs" "$@"
    EOS
  end

  def caveats
    <<~EOS
      Installing does not link anything. Homebrew runs formula installs inside a
      macOS sandbox that denies writes to $HOME, so the linking has to be a
      command you run yourself:

        icloud-sync Downloads

      That backs up ~/Downloads to a hidden ~/Downloads.bak, then symlinks
      ~/Downloads to iCloud Drive. To undo it:

        icloud-sync --restore Downloads

      Preview any run without touching disk:

        icloud-sync --dry-run Downloads

      On a second Mac, run with no arguments to pick from what you have already
      synced (the manifest is stored in iCloud Drive):

        icloud-sync

      Never run this with sudo. It refuses to run as root, because root-owned
      files in $HOME break later unelevated operations. If a rename ever failed
      for you with "Operation not permitted", that is an inherited
      "group:everyone deny delete" ACL rather than a need for elevation, and
      icloud-sync strips it for you as the owner.
    EOS
  end

  test do
    # Both of these short-circuit before any filesystem work, so the test block
    # cannot touch $HOME. Anything that actually syncs is deliberately not
    # exercised here: `brew test` would run it against the real home directory.
    assert_match version.to_s, shell_output("#{bin}/icloud-sync --version")

    help = shell_output("#{bin}/icloud-sync --help")
    assert_match "Usage:", help
    assert_match "--restore", help
    assert_match "--on-conflict", help
  end
end
