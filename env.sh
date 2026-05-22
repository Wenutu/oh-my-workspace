#!/bin/bash
# This script sets up the necessary environment for OMW.
# Source it in your ~/.bashrc or ~/.zshrc: source /path/to/your/omw/env.sh

export OMW_HOME
OMW_HOME=$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Add the main OMW script directory to the PATH
if [[ ":$PATH:" != *":$OMW_HOME:"* ]]; then
	export PATH="$OMW_HOME:$PATH"
fi

# Add the symlinked apps bin directory to the PATH
if [[ ":$PATH:" != *":$OMW_HOME/bin:"* ]]; then
	export PATH="$OMW_HOME/bin:$PATH"
fi

# Add the unified OMW module path for the 'module' command
if [[ ":$MODULEPATH:" != *":$OMW_HOME/tools/modulefiles:"* ]]; then
	export MODULEPATH="$OMW_HOME/tools/modulefiles:$MODULEPATH"
fi
