#!/bin/bash -x

export LC_LPATH=@loader_path/../lib
export TPATH=/Volumes/Storage/Repositories/Postgres/Transgres/Vendor/postgres/lib

for file in libXext.6.dylib libX11.6.dylib libxcb.1.dylib libXau.6.dylib libXdmcp.6.dylib; do
  ditto /opt/X11/lib/$file $TPATH/$file
  /usr/bin/install_name_tool -id "@rpath/${file}" $TPATH/$file
  for lib in libXext.6.dylib libX11.6.dylib libxcb.1.dylib libXau.6.dylib libXdmcp.6.dylib; do
    /usr/bin/install_name_tool -change "/opt/X11/lib/${lib}" "@rpath/${lib}" $TPATH/$file
  done
done

ditto mupdf/build/debug/mudraw $TPATH/../bin
/usr/bin/install_name_tool -add_rpath "${LC_LPATH}" $TPATH/../bin/mudraw
/usr/bin/install_name_tool -change "/opt/X11/lib/libXext.6.dylib" "@rpath/libXext.6.dylib" $TPATH/../bin/mudraw
/usr/bin/install_name_tool -change "/opt/X11/lib/libX11.6.dylib" "@rpath/libX11.6.dylib" $TPATH/../bin//mudraw


