require 'formula'

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

class Distribute < Formula
  url 'http://pypi.python.org/packages/source/d/distribute/distribute-0.6.27.tar.gz'
  md5 'ecd75ea629fee6d59d26f88c39b2d291'
end

class Pip < Formula
  url 'http://pypi.python.org/packages/source/p/pip/pip-1.1.tar.gz'
  md5 '62a9f08dd5dc69d76734568a6c040508'
end

class Python < Formula
  homepage 'http://www.python.org/'
  url 'http://www.python.org/ftp/python/2.7.3/Python-2.7.3.tar.bz2'
  md5 'c57477edd6d18bd9eeca2f21add73919'

  depends_on 'pkg-config' => :build
  depends_on 'readline' => :optional # Prefer over OS X's libedit
  depends_on 'sqlite'   => :optional # Prefer over OS X's older version
  depends_on 'gdbm'     => :optional

  def options
    [
      ["--no-framework", "Do a 'Framework' build instead of a UNIX-style build."],
      ["--universal", "Build for both 32 & 64 bit Intel."],
      ["--static", "Build static libraries."],
      ["--quicktest", "Run `make quicktest` after build."]
    ]
  end

  # Skip binaries so modules will load; skip lib because it is mostly Python files
  skip_clean ['bin', 'lib']

  # The Cellar location of site-packages (different for Framework builds)
  def site_packages_cellar
    if as_framework?
      # If we're installed or installing as a Framework, then use that location.
      return prefix+"Frameworks/Python.framework/Versions/2.7/lib/python2.7/site-packages"
    else
      # Otherwise, use just the lib path.
      return lib+"python2.7/site-packages"
    end
  end

  # The HOMEBREW_PREFIX location of site-packages.
  def site_packages
    HOMEBREW_PREFIX+"lib/python2.7/site-packages"
  end

  # Where distribute/pip will install executable scripts.
  def scripts_folder
    HOMEBREW_PREFIX+"share/python"
  end

  # lib folder,taking into account whether we are a Framework build or not
  def effective_lib
    if as_framework?
      prefix+"Frameworks/Python.framework/Versions/2.7/lib"
    else
      lib
    end
  end

  def install
    args = [ "--prefix=#{prefix}",
             "--enable-ipv6",
             "--with-sqlite-dynamic-extensions"
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
      # Building with --enable-shared (can) link the wrong (system) Python lib:
      # Prepending `-L.` does no harm. (http://bugs.python.org/issue11445)
      ENV.prepend 'LDFLAGS',  '-L.'
    end

    # Allow sqlite3 module to load extensions:
    # http://docs.python.org/library/sqlite3.html#f1
    inreplace "setup.py", 'sqlite_defines.append(("SQLITE_OMIT_LOAD_EXTENSION", "1"))', ''

    system "./configure", *args

    # HAVE_POLL is "broken" on OS X
    # See: http://trac.macports.org/ticket/18376
    inreplace 'pyconfig.h', /.*?(HAVE_POLL[_A-Z]*).*/, '#undef \1'

    system "make"
    ENV.j1 # Installs must be serialized
    # Tell Python not to install into /Applications (default for framework builds)
    system "make", "install", "PYTHONAPPSDIR=#{prefix}"
    system "make", "quicktest" if ARGV.include? '--quicktest'

    # Post-install, fix up the site-packages and install-scripts folders
    # so that user-installed Python software survives minor updates, such
    # as going from 2.7.0 to 2.7.1.

    # Remove the site-packages that Python created in its Cellar.
    site_packages_cellar.rmtree
    # Create a site-packages in `brew --prefix`/lib/python/site-packages
    site_packages.mkpath
    # Symlink the prefix site-packages into the cellar.
    ln_s site_packages, site_packages_cellar

    # This is a fix for better interoperability with pyqt. See:
    # https://github.com/mxcl/homebrew/issues/6176
    if not as_framework?
      (bin+"pythonw").make_link bin+"python"
      (bin+"pythonw2.7").make_link bin+"python2.7"
    end

    # Python 3 has a 2to3, too. (https://github.com/mxcl/homebrew/issues/12581)
    rm bin/"2to3" if (HOMEBREW_PREFIX/bin/"2to3").exist?

    # Tell distutils-based installers where to put scripts
    scripts_folder.mkpath
    (effective_lib+"python2.7/distutils/distutils.cfg").write <<-EOF.undent
      [install]
      install-scripts=#{scripts_folder}
    EOF

    # Install distribute and pip
    Distribute.new.brew { system "#{bin}/python", "setup.py", "install" }
    Pip.new.brew { system "#{bin}/python", "setup.py", "install" }
  end

  def caveats
    s = ""
    framework_caveats = <<-EOS.undent
      Python was built in framework style.

      You can `brew linkapps` to symlink "Idle" and the "Python Launcher".

    EOS

    general_caveats = <<-EOS.undent
      A "distutils.cfg" has been written, specifying the install-scripts folder as:
        #{scripts_folder}

      If you install Python packages via "pip install x" or "python setup.py install"
      (or the outdated easy_install), any provided scripts will go into the
      install-scripts folder above, so you may want to add it to your PATH.

      Distribute and Pip have been installed. To update them
          #{scripts_folder}/pip install --upgrade distribute
          #{scripts_folder}/pip install --upgrade pip

      See: https://github.com/mxcl/homebrew/wiki/Homebrew-and-Python

    EOS

    s += framework_caveats if as_framework?
    s += general_caveats
    return s
  end

  def test
    # See: https://github.com/mxcl/homebrew/pull/10487
    # Fixed [upstream](http://bugs.python.org/issue11149), but still nice to have.
    `#{bin}/python -c 'from decimal import Decimal; print Decimal(4) / Decimal(2)'`.chomp == '2'
    # Check if sqlite is ok, because we build with --enable-loadable-sqlite-extensions
    # and it can occur that building sqlite silently fails if OSX's sqlite is used.
    system "#{bin}/python", "-c", "import sqlite3"
  end
end
