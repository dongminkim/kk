class Kk < Formula
  desc "Fast, git-aware ls replacement"
  homepage "https://github.com/dongminkim/kk"
  url "https://github.com/dongminkim/kk/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "441b1fb0833ea256885b289e085e215f521fd6310e7a01a775500e5d933413ec"
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
