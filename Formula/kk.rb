class Kk < Formula
  desc "Fast, git-aware ls replacement"
  homepage "https://github.com/dongminkim/kk"
  url "https://github.com/dongminkim/kk/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "8b0118eeda41aeb11d5e5ec1aa5989111445edb0032cf550d7d8c5ff6a595369"
  license "MIT"
  head "https://github.com/dongminkim/kk.git", branch: "main"

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    mkdir "test_dir" do
      (testpath/"test_dir/hello.txt").write("hello")
      output = shell_output("#{bin}/kk --no-vcs .")
      assert_match "total", output
      assert_match "hello.txt", output
    end
  end
end
