class Kk < Formula
  desc "Fast, git-aware ls replacement"
  homepage "https://github.com/dongminkim/kk"
  url "https://github.com/dongminkim/kk/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "cba19005c59ec49f61c03bc2f6cbf16093dea8c93bdeb1ffc9ea72af98ef9205"
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
