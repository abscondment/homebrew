require 'formula'

# Python3 is the new language standard, not just a new revision.
# It's somewhat incompatible to Python 2.x, therefore, the executable
# "python" will always point to the 2.x version which you can get by
# `brew install python`.

# Was a non-framework build requested?
def build_framework?; not ARGV.include? '--no-framework'; end

# Are we installed or installing as a Framework?
def as_framework?
  if self.installed?
    File.exists? prefix+"Frameworks/Python.framework"
  else
    build_framework?
  end
end

class Distribute3 < Formula
  url 'http://pypi.python.org/packages/source/d/distribute/distribute-0.6.27.tar.gz'
  md5 'ecd75ea629fee6d59d26f88c39b2d291'
end

# Recommended way of installing python modules (http://pypi.python.org/pypi)
class Pip3 < Formula
  url 'http://pypi.python.org/packages/source/p/pip/pip-1.1.tar.gz'
  md5 '62a9f08dd5dc69d76734568a6c040508'
end

class Python3 < Formula
  homepage 'http://www.python.org/'
  url 'http://python.org/ftp/python/3.2.3/Python-3.2.3.tar.bz2'
  md5 'cea34079aeb2e21e7b60ee82a0ac286b'

  depends_on 'pkg-config' => :build
  depends_on 'readline' => :optional  # Prefer over OS X's libedit
  depends_on 'sqlite'   => :optional  # Prefer over OS X's older version
  depends_on 'gdbm'     => :optional

  def options
    [
      ["--no-framework", "UNIX-style build. Beware: wxPython (wxmac) won't work."],
      ["--universal", "Build for both 32 & 64 bit Intel."],
      ["--static", "Build static libraries."],
      ["--quicktest", "Run `make quicktest` after build. Takes some minutes."]
    ]
  end

  # Skip binaries so modules will load; skip lib because it is mostly Python files
  skip_clean ['bin', 'lib']

  # The Cellar location of site-packages (different for Framework builds)
  def site_packages_cellar
    if as_framework?
      # If we're installed or installing as a Framework, then use that location.
      return prefix+"Frameworks/Python.framework/Versions/3.2/lib/python3.2/site-packages"
    else
      # Otherwise, use just the lib path.
      return lib+"python3.2/site-packages"
    end
  end

  # The HOMEBREW_PREFIX location of site-packages.
  def site_packages
    HOMEBREW_PREFIX+"lib/python3.2/site-packages"
  end

  # Where distribute/pip will install executable scripts.
  def scripts_folder
    HOMEBREW_PREFIX+"share/python3"
  end

  # lib folder,taking into account whether we are a Framework build or not
  def effective_lib
    if as_framework?
      prefix+"Frameworks/Python.framework/Versions/3.2/lib" if as_framework?
    else
      lib
    end
  end

  def install
    args = [ "--prefix=#{prefix}",
             "--enable-ipv6",
             "--enable-loadable-sqlite-extensions"
           ]

    # We need to enable warnings because the configure.in uses -Werror to detect
    # "whether gcc supports ParseTuple" (https://github.com/mxcl/homebrew/issues/12194)
    ENV.enable_warnings
    # http://docs.python.org/devguide/setup.html#id8 suggests to disable some Warnings.
    ENV.append_to_cflags '-Wno-unused-value'
    ENV.append_to_cflags '-Wno-empty-body'
    ENV.append_to_cflags '-Qunused-arguments'

    # We can remove this, if the doctor carse about it.
    if File.exist? '/Library/Frameworks/Tk.framework'
      opoo <<-EOS.undent
        Tk.framework detected in /Library/Frameworks
        and that can make python builds to fail.
        https://github.com/mxcl/homebrew/issues/11602
      EOS
    end

    if build_framework? and ARGV.include? "--static"
      onoe "Cannot specify both framework and static."
      exit 99
    end

    if ARGV.build_universal?
      args << "--enable-universalsdk=/" << "--with-universal-archs=intel"
    end

    if build_framework?
      args << "--enable-framework=#{prefix}/Frameworks"
    else
      args << "--enable-shared" unless ARGV.include? '--static'
    end

    # Allow sqlite3 module to load extensions:
    # http://docs.python.org/library/sqlite3.html#f1
    inreplace "setup.py", 'sqlite_defines.append(("SQLITE_OMIT_LOAD_EXTENSION", "1"))', 'pass'

    system "./configure", *args
    system "make"
    ENV.j1 # Installs must be serialized
    # Tell Python not to install into /Applications (default for framework builds)
    system "make", "install", "PYTHONAPPSDIR=#{prefix}"
    system "make", "quicktest" if ARGV.include? "--quicktest"

    # Any .app get a " 3" attached, so it does not conflict with python 2.x.
    if build_framework?
      Dir.glob(prefix/"*.app").each do |app|
        mv app, app.gsub(".app", " 3.app")
      end
    end

    # Post-install, fix up the site-packages and install-scripts folders
    # so that user-installed Python software survives minor updates, such
    # as going from 3.2.2 to 3.2.3.

    # Remove the site-packages that Python created in its Cellar.
    site_packages_cellar.rmtree
    # Create a site-packages in `brew --prefix`/lib/python3/site-packages
    site_packages.mkpath
    # Symlink the prefix site-packages into the cellar.
    ln_s site_packages, site_packages_cellar

    # "python3" and executable is forgotten for framework builds.
    # Make sure homebrew symlinks it to `brew --prefix`/bin.
    ln_s "#{bin}/python3.2", "#{bin}/python3" unless (bin/"python3").exist?

    # Python 2 has a 2to3, too. (https://github.com/mxcl/homebrew/issues/12581)
    rm bin/"2to3" if (HOMEBREW_PREFIX/bin/"2to3").exist?

    # Tell distutils-based installers where to put scripts
    scripts_folder.mkpath
    (effective_lib/"python3.2/distutils/distutils.cfg").write <<-EOF.undent
      [install]
      install-scripts=#{scripts_folder}
    EOF

    # Install distribute for python3
    Distribute3.new.brew do
      system "#{bin}/python3.2", "setup.py", "install"
      # Symlink to easy_install3 to match python3 command.
      unless (scripts_folder/'easy_install3').exist?
        ln_s scripts_folder/"easy_install", scripts_folder/"easy_install3"
      end
    end
    # Install pip-3.2 for python3
    Pip3.new.brew { system "#{bin}/python3.2", "setup.py", "install" }
  end

  def caveats
    s = ""
    framework_caveats = <<-EOS.undent
      Python was built in framework style.

      You can `brew linkapps` to symlink "Idle" and the "Python Launcher".

    EOS

    # Tk warning only for 10.6 (not for Lion)
    tk_caveats = <<-EOS.undent
      Apple's Tcl/Tk is not recommended for use with Python on Mac OS X 10.6.
      For more information see: http://www.python.org/download/mac/tcltk/

    EOS

    general_caveats = <<-EOS.undent
      A "distutils.cfg" has been written, specifying the install-scripts directory as:
        #{scripts_folder}

      If you install Python packages via "pip-3.2 install x" or "python3 setup.py install"
      (or the outdated easy_install3), any provided scripts will go into the
      install-scripts folder above, so you may want to add it to your PATH.

      Distribute and Pip have been installed. To update them:
      #{scripts_folder}/pip-3.2 install --upgrade distribute
      #{scripts_folder}/pip-3.2 install --upgrade pip

      See: https://github.com/mxcl/homebrew/wiki/Homebrew-and-Python

    EOS

    s += framework_caveats if as_framework?
    s += tk_caveats if not MacOS.lion?
    s += general_caveats
    return s
  end

  def test
    # See: https://github.com/mxcl/homebrew/pull/10487
    # Fixed [upstream](http://bugs.python.org/issue11149), but still nice to have.
    `#{bin}/python3 -c 'from decimal import Decimal; print(Decimal(4) / Decimal(2))'`.chomp == '2'
    # Check if sqlite is ok, because we build with --enable-loadable-sqlite-extensions
    # and it can occur that building sqlite silently fails.
    system "#{bin}/python3", "-c", "import sqlite3"
  end
end
