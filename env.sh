#!/bin/bash
# This script sets up the necessary environment for OMW.
# Source it in your ~/.bashrc or ~/.zshrc: source /path/to/your/omw/env.sh

if [[ -n "${ZSH_VERSION:-}" ]]; then
	_omw_env_path="${(%):-%x}"
else
	_omw_env_path="${BASH_SOURCE[0]:-$0}"
fi

_omw_env_resolve_script_dir() {
	local script_path="$1"
	local dir
	local link

	while [[ -L "$script_path" ]]; do
		dir=$(builtin cd -P "$(dirname "$script_path")" && builtin pwd)
		link=$(readlink "$script_path")
		if [[ "$link" == /* ]]; then
			script_path="$link"
		else
			script_path="$dir/$link"
		fi
	done

	builtin cd -P "$(dirname "$script_path")" && builtin pwd
}

OMW_HOME=$(_omw_env_resolve_script_dir "$_omw_env_path")
export OMW_HOME
unset _omw_env_path
unset -f _omw_env_resolve_script_dir

if [[ -f "$OMW_HOME/VERSION" ]]; then
	OMW_VERSION=$(tr -d '[:space:]' <"$OMW_HOME/VERSION")
else
	OMW_VERSION="0.0.0-dev"
fi
[[ -n "$OMW_VERSION" ]] || OMW_VERSION="0.0.0-dev"
export OMW_VERSION

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
