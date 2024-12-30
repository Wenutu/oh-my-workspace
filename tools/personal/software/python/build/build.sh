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
if [ -f $OMW_HOME/packages/software/Python-3.9.21.tgz ]; then
  echo "Python-3.9.21.tgz is found"
else
  echo "Python-3.9.21.tgz is not found"
  exit 1
fi
if [ -d ./Python-3.9.21 ]; then
  echo "Python-3.9.21 is found"
  echo "Remove the existing Python-3.9.21"
  rm -rf ./Python-3.9.21
fi
echo "Extracting Python-3.9.21.tgz"
tar xf $OMW_HOME/packages/Python-3.9.21.tgz
echo "Installing Python-3.9.21"
cd Python-3.9.21
echo "Load openssl/openssl-1.1.1w"
module load openssl/openssl-1.1.1w
./configure --prefix=$PERSONAL_SOFTWARE/python/python-3.9.21 --with-openssl=$PUBLIC_SOFTWARE/openssl/openssl-1.1.1w --with-ensurepip=install
echo "Make and install Python-3.9.21"
make -j $(($(nproc) / 2)) && make install
echo "Installing Python to $PERSONAL_SOFTWARE/python/python-3.9.21"