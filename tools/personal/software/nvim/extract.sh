version=0.10.3
if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi

if [ -z $PERSONAL_SOFTWARE ]; then
  echo "PERSONAL_SOFTWARE is not defined"
  exit 1
fi

if [ -d ./nvim-$version ]; then
  echo "nvim-$version is found"
else
  if [ -f $OMW_HOME/packages/software/nvim-linux64.tar.gz ]; then
    echo "nvim-linux64.tar.gz is found"
    echo "Extracting nvim-linux64.tar.gz"
    tar xf $OMW_HOME/packages/software/nvim-linux64.tar.gz
    mv nvim-linux64 nvim-$version
  else
    echo "nvim-linux64.tar.gz is not found"
    exit 1
  fi
fi
echo "Installing neovim to $PERSONAL_SOFTWARE/nvim/nvim-$version" 