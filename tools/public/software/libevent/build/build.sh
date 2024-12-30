if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $PUBLIC_SOFTWARE ]; then
  echo "PUBLIC_SOFTWARE is not defined"
  exit 1
fi
if [ -f $OMW_HOME/packages/software/libevent-2.1.12-stable.tar.gz ]; then
  echo "libevent-2.1.12-stable.tar.gz is found"
else
  echo "libevent-2.1.12-stable.tar.gz is not found"
  exit 1
fi
if [ -d ./libevent-2.1.12-stable ]; then
  echo "libevent-2.1.12-stable is found"
  echo "Remove the existing libevent-2.1.12-stable"
  rm -rf ./libevent-2.1.12-stable
fi
echo "Extracting libevent-2.1.12-stable"
tar xf $OMW_HOME/packages/software/libevent-2.1.12-stable.tar.gz
cd ./libevent-2.1.12-stable
echo "Building libevent-2.1.12-stable"
PKG_CONFIG_PATH=$PUBLIC_SOFTWARE/openssl/openssl-1.1.1w/lib/pkgconfig ./configure --prefix=$PUBLIC_SOFTWARE/libevent/libevent-2.1.12 --enable-shared
make -j $(($(nproc) / 2)) && make install
echo "Installing libevent to $PUBLIC_SOFTWARE/libevent/libevent-2.1.12"

