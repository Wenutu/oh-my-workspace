version="9.1.0973"

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

if [ -d ./vim-$version ]; then
  echo "vim-$version is found"
else
  if [ -f $OMW_HOME/packages/software/vim-$version.tar.gz ]; then
    echo "vim-$version.tar.gz is found"
    echo "Extracting vim-$version.tar.gz"
    tar -xzf $OMW_HOME/packages/software/vim-$version.tar.gz
  else
    echo "vim-$version.tar.gz is not found"
    exit 1
  fi
fi

cd vim-$version || exit 1
module load ncurses/ncurses-6.5 python/python-3.9.21 local/local-1.0.0
./configure --prefix=$PERSONAL_SOFTWARE/vim/vim-$version \
            --with-features=huge --enable-multibyte \
            --enable-perlinterp \
            --enable-luainterp=yes --with-lua-prefix=$PUBLIC_SOFTWARE/lua/lua-5.4.7 \
            --enable-pythoninterp --enable-python3interp \
            --enable-gui=gtk3 --with-tlib=ncursesw \
            --enable-cscope --enable-fontset --with-compiledby="Wentao Shi"

make -j $(($(nproc) / 2)) && make install
echo "Installing vim to $PERSONAL_SOFTWARE/vim/vim-$version"