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
if [ -f $OMW_HOME/packages/software/zsh-5.9.tar.xz ]; then
  echo "zsh-5.9.tar.xz is found"
else
  echo "zsh-5.9.tar.xz is not found"
  exit 1
fi
if [ -d ./zsh-5.9 ]; then
  echo "zsh-5.9 is found"
  echo "Remove the existing zsh-5.9"
  rm -rf ./zsh-5.9
fi
echo "Extracting zsh-5.9.tar.xz"
tar xf $OMW_HOME/packages/zsh-5.9.tar.xz
echo "Building zsh-5.9"
cd ./zsh-5.9
echo "Load ncurses/ncurses-6.5"
module load ncurses/ncurses-6.5
./configure \
  --prefix=$PERSONAL_SOFTWARE/zsh/zsh-5.9 \
  --enable-multibyte \
  --enable-pcre \
  --enable-zsh-mem \
  --enable-etcdir=$CONFIG_PATH/zsh/zsh-5.9/.zsh \
  --enable-zshenv=$CONFIG_PATH/zsh/zsh-5.9/.zshenv \
  --enable-zshrc=$CONFIG_PATH/zsh/zsh-5.9/.zshrc \
  --enable-zprofile=$CONFIG_PATH/zsh/zsh-5.9/.zprofile \
  --enable-zlogin=$CONFIG_PATH/zsh/zsh-5.9/.zlogin \
  --enable-zlogout=$CONFIG_PATH/zsh/zsh-5.9/.zlogout

make -j $(($(nproc) / 2)) && make install
echo "Installing zsh to $PERSONAL_SOFTWARE/zsh/zsh-5.9"
