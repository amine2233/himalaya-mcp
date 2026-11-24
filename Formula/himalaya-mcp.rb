class HimalayaMcp < Formula
  desc "Himalaya email helper usable both as a CLI and as an MCP server"
  homepage "https://github.com/amine2233/himalaya-mcp"
  version "1.2.1"
  license "MIT"

  depends_on "himalaya"

  on_macos do
    depends_on macos: :sequoia

    on_arm do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-darwin-arm64.tar.gz"
      sha256 "79c58d7d35502c52363abd7a9839dfa7bc570653ef8f77dd99e1a9b55feb3c18"
    end

    on_intel do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-darwin-amd64.tar.gz"
      sha256 "722ff690a431e077370e2c47f3ee4105a4308ffc38cebac796d0eede20869455"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-linux-arm64.tar.gz"
      sha256 "dee33e15856f0036f887ea3a2da5d90887d64de25f1d52fe98b8ca0d8eee82f5"
    end

    on_intel do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-linux-x86_64.tar.gz"
      sha256 "fe9474ed19722d52d41aedbee727f90dda5cb67369c1667328b3740f1c94efd9"
    end
  end

  def install
    bin.install "himalaya-mcp"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/himalaya-mcp --version")
  end
end
