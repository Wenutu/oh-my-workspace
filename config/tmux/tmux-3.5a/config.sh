if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $CONFIG_PATH ]; then
  echo "CONFIG_PATH is not defined"
  exit 1
fi

if [ -f $OMW_HOME/packages/config/tmux.tar.gz ]; then
  echo "tmux.tar.gz is found"
else
  echo "tmux.tar.gz is not found"
  exit 1
fi

if [ -d $CONFIG_PATH/tmux/tmux-3.5a/.tmux ]; then
  echo ".tmux is found"
  echo "Remove the existing .tmux"
  rm -rf $CONFIG_PATH/tmux/tmux-3.5a/.tmux
fi

echo "Extracting tmux.tar.gz"
tar -xf $OMW_HOME/packages/config/tmux.tar.gz -C $CONFIG_PATH/tmux/tmux-3.5a
echo "Installing .tmux to $CONFIG_PATH/tmux/tmux-3.5a/.tmux"