if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi

if [ -z $PERSONAL_SOFTWARE ]; then
  echo "PERSONAL_SOFTWARE is not defined"
  exit 1
fi

if [ -d ./node-22.1.0 ]; then
  echo "node-22.1.0 is found"
else
  if [ -f $OMW_HOME/packages/software/node-v22.1.0-linux-x64-glibc-217.tar.gz ]; then
    echo "node-v22.1.0-linux-x64-glibc-217.tar.gz is found"
    echo "Extracting node-v22.1.0-linux-x64-glibc-217.tar.gz"
    tar -xzf $OMW_HOME/packages/software/node-v22.1.0-linux-x64-glibc-217.tar.gz
    mv node-v22.1.0-linux-x64-glibc-217 node-22.1.0
  else
    echo "node-v22.1.0-linux-x64-glibc-217.tar.gz is not found"
    exit 1
  fi
fi 
echo "Installing npm to $PERSONAL_SOFTWARE/node/node-22.1.0"
