version=3.5a
if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $PERSONAL_SOFTWARE ]; then
  echo "PERSONAL_SOFTWARE is not defined"
  exit 1
fi
if [ -f $OMW_HOME/packages/software/tmux-$version.tar.gz ]; then
  echo "tmux-$version.tar.gz is found"
else
  echo "tmux-$version.tar.gz is not found"
  exit 1
fi
if [ -d ./tmux-$version ]; then
  echo "tmux-$version is found"
else 
  if [ -f $OMW_HOME/packages/software/tmux-$version.tar.gz ]; then
    echo "tmux-$version.tar.gz is found"
    echo "Extracting tmux-$version.tar.gz"
    tar xf $OMW_HOME/packages/software/tmux-$version.tar.gz
  else
    echo "tmux-$version.tar.gz is not found"
    exit 1
  fi
fi
cd tmux-$version
echo "Load ncurses/ncurses-6.5 and libevent/libevent-2.1.12"
module load ncurses/ncurses-6.5 libevent/libevent-2.1.12
echo "Building tmux-$version"
./configure --prefix=$PERSONAL_SOFTWARE/tmux/tmux-$version
make -j $(($(nproc) / 2)) && make install
echo "Installing tmux to $PERSONAL_SOFTWARE/tmux/tmux-$version"

