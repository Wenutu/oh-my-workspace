#!/bin/bash
# This script sets up the necessary environment for OMW.
# Source it in your ~/.bashrc or ~/.zshrc: source /path/to/your/omw/env.sh

if [[ -n "${ZSH_VERSION:-}" ]]; then
	_omw_env_path="${(%):-%x}"
else
	_omw_env_path="${BASH_SOURCE[0]:-$0}"
fi

OMW_HOME=$(builtin cd "$(dirname "$_omw_env_path")" && pwd)
export OMW_HOME
unset _omw_env_path

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
