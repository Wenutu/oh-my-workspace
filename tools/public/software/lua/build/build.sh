if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $PUBLIC_SOFTWARE ]; then
  echo "PUBLIC_SOFTWARE is not defined"
  exit 1
fi
if [ -f $OMW_HOME/packages/software/lua-5.4.7.tar.gz ]; then
  echo "lua-5.4.7.tar.gz is found"
else
  echo "lua-5.4.7.tar.gz is not found"
  exit 1
fi
if [ -d ./lua-5.4.7 ]; then
  echo "lua-5.4.7 is found"
  echo "Remove the existing lua-5.4.7"
  rm -rf ./lua-5.4.7
fi
echo "Extract lua-5.4.7.tar.gz"
tar xf $OMW_HOME/packages/software/lua-5.4.7.tar.gz
cd lua-5.4.7
echo "Configure lua-5.4.7"
# Makefile
sed -i 's/INSTALL_TOP= \/usr\/local/INSTALL_TOP= ${PUBLIC_SOFTWARE}\/lua\/lua-5.4.7/g' Makefile
make linux test
make install
echo "lua-5.4.7 installed successfully"
