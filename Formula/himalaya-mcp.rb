class HimalayaMcp < Formula
  desc "Himalaya email helper usable both as a CLI and as an MCP server"
  homepage "https://github.com/amine2233/himalaya-mcp"
  version "1.1.0"
  license "MIT"

  depends_on "himalaya"

  on_macos do
    depends_on macos: :sequoia

    on_arm do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-darwin-arm64.tar.gz"
      sha256 "baf977927f3ba6cc22006b66c547fe2dda0aff966adbe33a925a6ebf9caacb35"
    end

    on_intel do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-darwin-amd64.tar.gz"
      sha256 "bfc77d81c9035fff787ac9aa041b0d2c3b05011308723df8dd8c900d2572a6b2"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-linux-arm64.tar.gz"
      sha256 "e4024f666ec50ce09e9fcf7c40cda4dceb809656cfe40411a01915cf9a577d3b"
    end

    on_intel do
      url "https://github.com/amine2233/himalaya-mcp/releases/download/#{version}/himalaya-mcp-linux-x86_64.tar.gz"
      sha256 "484688f5bf54d59abf5a48d5e44755eb0e72e632794fd9a10a259591162df1b1"
    end
  end

  def install
    bin.install "himalaya-mcp"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/himalaya-mcp --version")
  end
end
