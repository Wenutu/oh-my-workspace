#!/bin/bash
echo -e "# OMW Configuration"
export OMW_HOME=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

echo -e "OMW_HOME=$OMW_HOME"
echo -e "PATH=$PATH"
echo -e "MODULEPATH=$MODULEPATH"
echo -e "# End of OMW Configuration"