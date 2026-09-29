class Tessera < Formula
  desc "Menu bar app that tiles your windows on a grid you choose"
  homepage "https://github.com/giacolaiacomo/tessera"
  url "https://github.com/giacolaiacomo/tessera/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "fab3e21ce09ab402c6e9daf5f0813a296b1b1b358a9129c4ef0e3d1e3c47110b"
  license "MIT"

  depends_on :macos

  def install
    # Built from source on your Mac with the Swift compiler from the Xcode Command Line Tools.
    system "./scripts/build-app.sh", prefix/"Tessera.app"
    bin.install_symlink prefix/"Tessera.app/Contents/MacOS/Tessera" => "tessera"
  end

  service do
    run [opt_prefix/"Tessera.app/Contents/MacOS/Tessera"]
    keep_alive successful_exit: false
    process_type :interactive
  end

  def caveats
    <<~EOS
      Tessera needs Accessibility access to move other apps' windows. Allow it in
        System Settings › Privacy & Security › Accessibility
      It works the moment you tick the box; no restart needed.
    EOS
  end

  test do
    # --icon draws the app icon offscreen and exits, so it needs no Accessibility access.
    # (--diagnose would: it talks to the running, authorised app.)
    system bin/"tessera", "--icon", testpath/"icon.png", "128"
    assert_path_exists testpath/"icon.png"
  end
end
