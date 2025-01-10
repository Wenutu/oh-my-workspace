version=5.9
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
if [ -f $OMW_HOME/packages/software/zsh-$version.tar.xz ]; then
  echo "zsh-$version.tar.xz is found"
else
  echo "zsh-$version.tar.xz is not found"
  exit 1
fi
if [ -d ./zsh-$version ]; then
  echo "zsh-$version is found"
else
  if [ -f $OMW_HOME/packages/software/zsh-$version.tar.xz ]; then
    echo "zsh-$version.tar.xz is found"
    echo "Extracting zsh-$version.tar.xz"
    tar xf $OMW_HOME/packages/software/zsh-$version.tar.xz
  else
    echo "zsh-$version.tar.xz is not found"
    exit 1
  fi
fi
echo "Building zsh-$version"
cd ./zsh-$version
echo "Load ncurses/ncurses-6.5"
module load ncurses/ncurses-6.5
./configure \
  --prefix=$PERSONAL_SOFTWARE/zsh/zsh-$version \
  --enable-multibyte \
  --enable-pcre \
  --enable-zsh-mem \

make -j $(($(nproc) / 2)) && make install
echo "Installing zsh to $PERSONAL_SOFTWARE/zsh/zsh-$version"
