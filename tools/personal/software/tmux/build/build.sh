if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $PERSONAL_SOFTWARE ]; then
  echo "PERSONAL_SOFTWARE is not defined"
  exit 1
fi
if [ -f $OMW_HOME/packages/software/tmux-3.5a.tar.gz ]; then
  echo "tmux-3.5a.tar.gz is found"
else
  echo "tmux-3.5a.tar.gz is not found"
  exit 1
fi
if [ -d ./tmux-3.5a ]; then
  echo "tmux-3.5a is found"
  echo "Remove the existing tmux-3.5a"
  rm -rf ./tmux-3.5a
fi
echo "Extracting tmux-3.5a.tar.gz"
tar xf $OMW_HOME/packages/software/tmux-3.5a.tar.gz -C .
cd tmux-3.5a
echo "Load ncurses/ncurses-6.5 and libevent/libevent-2.1.12"
module load ncurses/ncurses-6.5 libevent/libevent-2.1.12
echo "Building tmux-3.5a"
./configure --prefix=$PERSONAL_SOFTWARE/tmux/tmux-3.5a
make -j $(($(nproc) / 2)) && make install
echo "Installing tmux to $PERSONAL_SOFTWARE/tmux/tmux-3.5a"

