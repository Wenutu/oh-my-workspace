if [ -z $OMW_HOME ]; then
  echo "OMW_HOME is not defined"
  exit 1
fi
if [ -z $CONFIG_PATH ]; then
  echo "CONFIG_PATH is not defined"
  exit 1
fi

if [ -f $OMW_HOME/packages/config/oh-my-zsh.tar.gz ]; then
  echo "oh-my-zsh.tar.gz is found"
else
  echo "oh-my-zsh.tar.gz is not found"
  exit 1
fi
if [ -d $CONFIG_PATH/zsh/zsh-5.9/oh-my-zsh ]; then
  echo "oh-my-zsh is found"
  echo "Remove the existing oh-my-zsh"
  rm -rf $CONFIG_PATH/zsh/zsh-5.9/oh-my-zsh
fi

echo "Extracting oh-my-zsh.tar.gz"
tar xf $OMW_HOME/packages/config/oh-my-zsh.tar.gz -C $CONFIG_PATH/zsh/zsh-5.9
echo "Installing oh-my-zsh to $CONFIG_PATH/zsh/zsh-5.9/oh-my-zsh"