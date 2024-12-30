echo "Step1: package config"
echo "package tmux config"
if [ -d $CONFIG_PATH/zsh/zsh-5.9/oh-my-zsh ]; then
  echo "oh-my-zsh is found"
  echo "package oh-my-zsh"
  if [ -f $OMW_HOME/packages/config/oh-my-zsh.tar.gz ]; then
    echo "oh-my-zsh package is found"
    echo "Remove the existing oh-my-zsh package"
    rm -f $OMW_HOME/packages/config/oh-my-zsh.tar.gz
  fi
  tar czf $OMW_HOME/packages/config/oh-my-zsh.tar.gz -C $CONFIG_PATH/zsh/zsh-5.9 oh-my-zsh
  echo "oh-my-zsh package added"
fi

if [ -d $CONFIG_PATH/tmux/tmux-3.5a/.tmux ]; then
  echo ".tmux is found"
  echo "package .tmux"
  if [ -f $OMW_HOME/packages/config/tmux.tar.gz ]; then
    echo ".tmux package is found"
    echo "Remove the existing .tmux package"
    rm -f $OMW_HOME/packages/config/tmux.tar.gz
  fi
  tar czf $OMW_HOME/packages/config/tmux.tar.gz -C $CONFIG_PATH/tmux/tmux-3.5a .tmux
  echo ".tmux package added"
fi

if [ -d packages ]; then
  echo "packages is found"
  echo "package packages"
  if [ -f $OMW_HOME/packages.tar.gz ]; then
    echo "packages package is found"
    echo "Remove the existing packages package"
    rm -f $OMW_HOME/packages.tar.gz
  fi
  tar czf $OMW_HOME/packages.tar.gz -C $OMW_HOME packages
  echo "packages package added"
fi

echo "Step2: add config.sh and build.sh"
git add config/*/*/config.sh -f
git add tools/*/*/*/build/build.sh -f
git add tools/*/*/*/build/fix.sh -f