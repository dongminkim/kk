class Kk < Formula
  desc "Fast, git-aware ls replacement"
  homepage "https://github.com/dongminkim/kk"
  url "https://github.com/dongminkim/kk/archive/refs/tags/v0.2.2.tar.gz"
  sha256 "cc6777b681f3c2677db0b5db0de44a83436bb0fd83da197d34b3a64122df07b0"
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
