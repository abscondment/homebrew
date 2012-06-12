require 'formula'

class Bind < Formula
  homepage 'http://www.isc.org/software/bind/'
  url 'ftp://ftp.isc.org/isc/bind9/9.9.1-P1/bind-9.9.1-P1.tar.gz'
  version '9.9.1-p1'
  sha256 '2dc5886b3eb6768d312b43dbe1e23a5b67b4f4dcfa1a65b1017e7710bb764627'

  depends_on "openssl" if MacOS.leopard?
  depends_on "botan"
  depends_on "python3"

  def install

    ENV.libxml2
    # libxml2 sets CPPFLAGS but bind ignores them, so merge with CFLAGS
    ENV['CFLAGS'] += ENV['CPPFLAGS']

    ENV['STD_CDEFINES'] = '-DDIG_SIGCHASE=1'

    # Not needed but for my debugging purposed
    #ENV['STD_CINCLUDES'] = "#{MacOS.sdk_path.to_s}/usr"


    system "./configure", "--prefix=#{prefix}",
                          "--enable-threads",
                          "--enable-ipv6",
                          "--with-openssl=#{MacOS.sdk_path.to_s}/usr"

    # From the bind9 README: "Do not use a parallel 'make'."
    ENV.deparallelize
    system "make"
    system "make install"
  end
end
