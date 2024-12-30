if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $PUBLIC_SOFTWARE ]; then
  echo "PUBLIC_SOFTWARE is not defined"
  exit 1
fi
if [ -f $OMW_HOME/packages/software/openssl-1.1.1w.tar.gz ]; then
  echo "openssl-1.1.1w.tar.gz is found"
else
  echo "openssl-1.1.1w.tar.gz is not found"
  exit 1
fi
if [ -d ./openssl-1.1.1w ]; then
  echo "openssl-1.1.1w is found"
  echo "Remove the existing openssl-1.1.1w"
  rm -rf ./openssl-1.1.1w
fi
echo "Extracting openssl-1.1.1w.tar.gz"
tar -zxf $OMW_HOME/packages/software/openssl-1.1.1w.tar.gz
cd openssl-1.1.1w
echo "Configuring openssl-1.1.1w"
./config --prefix=$PUBLIC_SOFTWARE/openssl/openssl-1.1.1w --openssldir=$PUBLIC_SOFTWARE/openssl/openssl-1.1.1w
echo "Building openssl-1.1.1w"
make -j $(($(nproc) / 2)) && make install
echo "Installing openssl-1.1.1w to $PUBLIC_SOFTWARE/openssl/openssl-1.1.1w"
