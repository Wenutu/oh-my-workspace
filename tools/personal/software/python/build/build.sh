version=3.9.21

if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $PERSONAL_SOFTWARE ]; then
  echo "PERSONAL_SOFTWARE is not defined"
  exit 1
fi
if [ -z $CONFIG_PATH ]; then
  echo "CONFIG_PATH is not defined"
  exit 1
fi
if [ -d ./Python-$version ]; then
  echo "Python-$version is found"
else
  if [ -f $OMW_HOME/packages/software/Python-$version.tgz ]; then
    echo "Python-$version.tgz is found"
    echo "Extracting Python-$version.tgz"
    tar xf $OMW_HOME/packages/software/Python-$version.tgz
  else
    echo "Python-$version.tgz is not found"
    exit 1
  fi
fi
echo "Installing Python-$version"
cd Python-$version || exit 1
echo "Load openssl/openssl-1.1.1w"
module load openssl/openssl-1.1.1w
./configure --prefix=$PERSONAL_SOFTWARE/python/python-$version --with-openssl=$PUBLIC_SOFTWARE/openssl/openssl-1.1.1w --with-ensurepip=install
echo "Make and install Python-$version"
make -j $(($(nproc) / 2)) && make install
echo "Installing Python to $PERSONAL_SOFTWARE/python/python-$version"