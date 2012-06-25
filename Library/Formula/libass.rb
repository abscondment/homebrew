require 'formula'

class Libass < Formula
  homepage 'http://code.google.com/p/libass/'
  url 'http://libass.googlecode.com/files/libass-0.10.0.tar.gz'
  sha1 '82bfda2b78f74cf75a4dd0283d090ad1a71a697f'

  depends_on 'pkg-config' => :build
  depends_on 'fribidi'

  def install
    # libass needs "ft2build.h" which is in X11
    ENV.x11

    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"
    system "make install"
  end
end
