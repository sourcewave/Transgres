#!/bin/sh

# This script is to build back-versions of Postgres to get the postgres executable
# to be used in pg_updating older database versions.

# there is a way to set PROJECT_DIR if it is not set
export PROJECT_DIR=`pwd`  #assuming I'm in Transgres

# JAVA_HOME must be set -- only for pljava/pg_jinx
#export JAVA_HOME=${PROJECT_DIR}/Vendor/jdk1.7.jdk/Contents/Home
#export JAVA_LCPATH=@loader_path/../../PlugIns/jdk1.7.jdk/Contents/Home/jre/lib/server

# this is just for building the postgres part -- not the pljava/pg_jinx parts
function buildver {
#!/bin/sh

  cd ${PROJECT_DIR}/postgres-project
  make distclean
  sh ./configure --prefix="${PROJECT_DIR}/Vendor/postgres"$1 --enable-thread-safety --with-openssl --with-gssapi --with-bonjour --with-krb5 --with-libxml --with-libxslt --with-perl --with-python --enable-debug LDFLAGS_SL=-headerpad_max_install_names

  git checkout r0ml$1
  /usr/bin/make -C src uninstall
  #/usr/bin/make -C contrib uninstall

  /usr/bin/make -C src install CFLAGS=-g
  #/usr/bin/make -C contrib install CFLAGS=-g

  mv "${PROJECT_DIR}/Vendor/postgres$1/bin/postgres" "${PROJECT_DIR}/Vendor/postgres/bin/postgres$1"

  # since I only want the postgres executable, I don't need to fix the
  # dynamic loading paths, since the postgres executable doesn't use them?
  # of course, it might use dlopen -- so hang on...

#  export LC_LPATH="@loader_path/../lib"

# directories=( "bin" "lib" )
# for directory in ${directories[@]}
# do
#
#cd "${PROJECT_DIR}/Vendor/postgres/${directory}"
#
#for file in *
#do
#
#( /usr/bin/install_name_tool -add_rpath "${LC_LPATH}" $file || true)
#
#for lib in libpq.5.dylib libecpg.6.dylib libpgtypes.3.dylib
#do
#( /usr/bin/install_name_tool -change "${PROJECT_DIR}/Vendor/postgres/lib/${lib}" "@rpath/${lib}" $file || true)
#
#done
#done

#for file in *.dylib
#do
#basename=`basename $file`
#if [[ -f $file ]]
#then
#/usr/bin/install_name_tool -id "@rpath/${basename}" $file
## codesign --verbose -f -s "${CODE_SIGN_IDENTITY}" --entitlements "${PROJECT_DIR}/App/Tool.entitlements" "$file"
#fi
#done
#
#done

}

buildver 9_2

