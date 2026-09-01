class HeadroomAi < Formula
  desc "Context optimization layer for LLM applications"
  homepage "https://headroom-docs.vercel.app"
  license "Apache-2.0"

  depends_on "python@3.13"

  def install
    python = Formula["python@3.13"].opt_bin/"python3"
    system python, "-m", "pip", "install", "headroom-ai[all]", "--target", libexec/"lib/python3.13/site-packages"
    (bin/"headroom").write <<~SCRIPT
      #!/usr/bin/env bash
      exec #{Formula["python@3.13"].opt_bin}/python3 -m headroom "$@"
    SCRIPT
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/headroom --version")
    assert_match "Usage:", shell_output("#{bin}/headroom --help")
  end
end
