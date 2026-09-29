class Tessera < Formula
  desc "Menu bar app that tiles your windows on a grid you choose"
  homepage "https://github.com/giacolaiacomo/tessera"
  url "https://github.com/giacolaiacomo/tessera/archive/refs/tags/v1.1.1.tar.gz"
  sha256 "f85cb23e1b561b6ad821f7553fd284c1439ecdfe647728d89d95a87c5edbfa59"
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
