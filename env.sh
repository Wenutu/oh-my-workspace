#!/bin/bash
OMW_HOME=$(cd $(dirname $0); pwd)

echo -e "# OMW Configuration"
export OMW_HOME=$OMW_HOME

if [[ ":$PATH:" != *":$OMW_HOME:"* ]]; then
    export PATH="$OMW_HOME:$PATH"
fi

if [[ ":$PATH:" != *":$OMW_HOME/scripts/bin:"* ]]; then
    export PATH="$OMW_HOME/scripts/bin:$PATH"
fi

if [[ ":$MODULEPATH:" != *":$OMW_HOME/tools/public/modulefiles:"* ]]; then
    export MODULEPATH="$OMW_HOME/tools/public/modulefiles:$MODULEPATH"
fi

if [[ ":$MODULEPATH:" != *":$OMW_HOME/tools/personal/modulefiles:"* ]]; then
   export MODULEPATH="$OMW_HOME/tools/personal/modulefiles:$MODULEPATH"
fi