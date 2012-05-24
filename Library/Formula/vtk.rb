require 'formula'

class Vtk < Formula
  homepage 'http://www.vtk.org'
  url 'http://www.vtk.org/files/release/5.10/vtk-5.10.0.tar.gz'
  md5 'a0363f78910f466ba8f1bd5ab5437cb9'

  depends_on 'cmake' => :build
  depends_on 'qt' if ARGV.include? '--qt'
  depends_on 'hdf5' => :optional

  def options
  [
    ['--python', "Enable python wrapping."],
    ['--qt', "Enable Qt extension."],
    ['--qt-extern', "Enable Qt extension (via external Qt)"],
    ['--tcl', "Enable Tcl wrapping."],
    ['--x11', "Enable X11 extension."]
  ]
  end

  def which_python
    "python" + `python -c 'import sys;print(sys.version[:3])'`.strip
  end
  
  # To avoid the vtkpython binary fail with "dyld: Symbol not found: _environ":
  skip_clean :all

  def install
    args = std_cmake_args + [
             "-DVTK_REQUIRED_OBJCXX_FLAGS:STRING=''",
             "-DBUILD_TESTING:BOOL=OFF",
             "-DBUILD_EXAMPLES:BOOL=OFF",
             "-DBUILD_SHARED_LIBS:BOOL=ON",
             "-DCMAKE_INSTALL_RPATH:STRING='#{lib}/vtk-5.10'",
             "-DCMAKE_INSTALL_NAME_DIR:STRING='#{lib}/vtk-5.10'"]

    if ARGV.include? '--python'
      python_prefix = `python-config --prefix`.strip
      python_version = `python -c 'import sys;print(sys.version[:3])'`.strip

      # Install to lib and let installer symlink to global python site-packages.
      # The path in lib needs to exist first and be listed in PYTHONPATH.
      pydir = lib/which_python/'site-packages'
      pydir.mkpath
      ENV.prepend 'PYTHONPATH', pydir, ':'
      args << "-DVTK_PYTHON_SETUP_ARGS='--prefix=#{prefix}'"

      args << "-DVTK_WRAP_PYTHON:BOOL=ON"

      # Python is actually a library. The libpythonX.Y.dylib points to this lib, too.
      if File.exist? "#{python_prefix}/Python"
        # Python was compiled with --framework. "Python" is actually a library:
        args << "-DPYTHON_LIBRARY='#{python_prefix}/Python'"
        args << "-DPYTHON_INCLUDE_DIR=#{python_prefix}/Headers"
      else
        python_lib = "#{python_prefix}/lib/libpython#{python_version}"
        args << "-DPYTHON_INCLUDE_DIR=#{python_prefix}/include/python#{python_version}"
        if File.exists? "#{python_lib}.a"
          args << "-DPYTHON_LIBRARY='#{python_lib}.a'"
        else
          args << "-DPYTHON_LIBRARY='#{python_lib}.dylib'"
        end
      end
      # Avoid error with python and tk:
      #  In file included from VTK/Utilities/TclTk/internals/tk8.5/tkMacOSXPort.h:73:
      #  Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.7.sdk/usr/include/tkIntXlibDecls.h:657:14: error: 
      #  functions that differ only in their return type cannot be overloaded
      args << "-DVTK_USE_TK:BOOL=OFF"
    end

    if ARGV.include? '--qt' or ARGV.include? '--qt-extern'
      args << "-DVTK_USE_GUISUPPORT:BOOL=ON"
      args << "-DVTK_USE_QT:BOOL=ON"
      args << "-DVTK_USE_QVTK:BOOL=ON"
    end

    if ARGV.include? '--tcl'
      args << "-DVTK_WRAP_TCL:BOOL=ON"
    end

    if ARGV.include? '--x11'
      ENV.x11
      args << "-DVTK_USE_COCOA:BOOL=OFF"
      args << "-DVTK_USE_X:BOOL=ON"
    end

    # Hack suggested at http://www.vtk.org/pipermail/vtk-developers/2006-February/003983.html
    # to get the right RPATH in the python libraries (the .so files in the vtk egg).
    # Also readable: http://vtk.1045678.n5.nabble.com/VTK-Python-Wrappers-on-Red-Hat-td1246159.html
    args << "-DCMAKE_BUILD_WITH_INSTALL_RPATH:BOOL=ON"
    ENV['DYLD_LIBRARY_PATH'] = buildpath/'build/bin'

    args << ".."

    mkdir 'build' do
      system "cmake", *args
      # Work-a-round to avoid (http://vtk.org/Bug/view.php?id=12876):
      #   ld: file not found: /usr/local/Cellar/vtk/5.8.0/lib/vtk-5.8/libvtkDICOMParser.5.8.dylib for architecture x86_64"
      #   collect2: ld returned 1 exit status
      #   make[2]: *** [bin/vtkpython] Error 1
      # We symlink such that the DCMAKE_INSTALL_NAME_DIR is available and points to the current build/bin
      lib.mkpath # create empty directories, because we need it here
      ln_s buildpath/'build/bin', lib/'vtk-5.10'
      system "make"
      rm lib/'vtk-5.10' # Remove our symlink, was only needed to make make succeed.
      # end work-a-round
      system "make install" # Finally move libs in their places.
    end

    # Remove duplicate files that will cause the final link phase to fail.
    %w(easy-install.pth site.py site.pyc).each do |f|
      rm pydir/f
    end
  end
end
