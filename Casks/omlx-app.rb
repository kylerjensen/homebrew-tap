# frozen_string_literal: true

cask "omlx-app" do
  on_sequoia :or_older do
    version "0.6.3rc3"
    sha256 "cee29bd62462bfb590b17247e3840d06883a46dcaab9a1416b3b65cb009b9caa"

    url "https://github.com/jundot/omlx/releases/download/v#{version}/oMLX-#{version}-macos15-sequoia.dmg"
  end
  on_tahoe :or_newer do
    version "0.6.3rc3"
    sha256 "3e75763f157cb1895c8d565d0c82fb0a2c85e885d1fe5b670a35ada4ede3b659"

    url "https://github.com/jundot/omlx/releases/download/v#{version}/oMLX-#{version}-macos26-27.dmg"
  end

  name "oMLX"
  desc "Menu bar app for the oMLX LLM inference server"
  homepage "https://github.com/jundot/omlx"

  livecheck do
    skip "Release candidate"
  end

  auto_updates true
  depends_on macos: :sequoia
  depends_on arch: :arm64

  app "oMLX.app"

  uninstall quit: "app.omlx"

  zap trash: [
    "~/Library/Application Support/omlx",
    "~/Library/Caches/omlx",
    "~/Library/HTTPStorages/app.omlx",
    "~/Library/Logs/omlx",
    "~/Library/Preferences/app.omlx.plist",
  ]
end
