#!/bin/bash
# shellcheck shell=bash disable=SC2034,SC2016
# OMW (Oh My Workspace) package definitions.
#
# This file is sourced from omw_init_globals(). The main script declares the
# array types globally; this file only resets and fills those containers.

declare -p SOFTWARE_LIST >/dev/null 2>&1 || declare -a SOFTWARE_LIST
declare -p APP_LIST >/dev/null 2>&1 || declare -a APP_LIST
declare -p NODE_PACKAGE_LIST >/dev/null 2>&1 || declare -a NODE_PACKAGE_LIST
declare -p NODE_CACHE_PACKAGE_LIST >/dev/null 2>&1 || declare -a NODE_CACHE_PACKAGE_LIST
declare -p SOFTWARE_VERSIONS >/dev/null 2>&1 || declare -A SOFTWARE_VERSIONS SOFTWARE_URLS SOFTWARE_DEPS SOFTWARE_CONFIG_CMDS SOFTWARE_CFLAGS SOFTWARE_LDFLAGS
declare -p APP_VERSIONS >/dev/null 2>&1 || declare -A APP_VERSIONS APP_URLS APP_EXECUTABLE_NAME APP_SOURCE_URLS APP_BIN_DIRS
declare -p NODE_PACKAGE_NAMES >/dev/null 2>&1 || declare -A NODE_PACKAGE_NAMES NODE_PACKAGE_VERSIONS NODE_PACKAGE_BINS NODE_PACKAGE_NODE_VERSIONS
declare -p NODE_CACHE_PACKAGE_NAMES >/dev/null 2>&1 || declare -A NODE_CACHE_PACKAGE_NAMES NODE_CACHE_PACKAGE_VERSIONS NODE_CACHE_PACKAGE_NODE_VERSIONS

SOFTWARE_LIST=()
SOFTWARE_VERSIONS=()
SOFTWARE_URLS=()
SOFTWARE_DEPS=()
SOFTWARE_CONFIG_CMDS=()
SOFTWARE_CFLAGS=()
SOFTWARE_LDFLAGS=()

APP_LIST=()
APP_VERSIONS=()
APP_URLS=()
APP_EXECUTABLE_NAME=()
APP_SOURCE_URLS=()
APP_BIN_DIRS=()

NODE_PACKAGE_LIST=()
NODE_PACKAGE_NAMES=()
NODE_PACKAGE_VERSIONS=()
NODE_PACKAGE_BINS=()
NODE_PACKAGE_NODE_VERSIONS=()

NODE_CACHE_PACKAGE_LIST=()
NODE_CACHE_PACKAGE_NAMES=()
NODE_CACHE_PACKAGE_VERSIONS=()
NODE_CACHE_PACKAGE_NODE_VERSIONS=()

OMW_NONE="-"

_omw_packages_has_word() {
	local needle="$1"
	local haystack="${2:-}"
	local item

	for item in $haystack; do
		[[ "$item" == "$needle" ]] && return 0
	done
	return 1
}

_omw_packages_value() {
	local value="${1:-}"

	[[ "$value" == "$OMW_NONE" ]] && value=""
	printf '%s' "$value"
}

software() {
	if (($# != 7)); then
		echo "ERROR: software requires 7 fields: name version url deps build_cmd cflags ldflags" >&2
		return 1
	fi

	local name="$1"
	local version="$2"
	local url
	local deps
	local build_cmd
	local cflags
	local ldflags

	url=$(_omw_packages_value "$3")
	deps=$(_omw_packages_value "$4")
	build_cmd=$(_omw_packages_value "$5")
	cflags=$(_omw_packages_value "$6")
	ldflags=$(_omw_packages_value "$7")

	if ! _omw_packages_has_word "$name" "${SOFTWARE_LIST[*]:-}"; then
		SOFTWARE_LIST+=("$name")
	fi
	if ! _omw_packages_has_word "$version" "${SOFTWARE_VERSIONS[$name]:-}"; then
		SOFTWARE_VERSIONS["$name"]+="${SOFTWARE_VERSIONS[$name]:+ }$version"
	fi

	SOFTWARE_URLS["$name"]="$url"
	SOFTWARE_DEPS["$name@$version"]="$deps"
	SOFTWARE_CONFIG_CMDS["$name"]="$build_cmd"
	[[ -n "$cflags" ]] && SOFTWARE_CFLAGS["$name"]="$cflags"
	[[ -n "$ldflags" ]] && SOFTWARE_LDFLAGS["$name"]="$ldflags"
	return 0
}

app() {
	if (($# != 6)); then
		echo "ERROR: app requires 6 fields: name version url executable source_url bin_dirs" >&2
		return 1
	fi

	local name="$1"
	local version="$2"
	local url
	local executable
	local source_url
	local bin_dirs

	url=$(_omw_packages_value "$3")
	executable=$(_omw_packages_value "$4")
	source_url=$(_omw_packages_value "$5")
	bin_dirs=$(_omw_packages_value "$6")

	if ! _omw_packages_has_word "$name" "${APP_LIST[*]:-}"; then
		APP_LIST+=("$name")
	fi

	APP_VERSIONS["$name"]="$version"
	APP_URLS["$name"]="$url"
	APP_EXECUTABLE_NAME["$name"]="$executable"
	[[ -n "$source_url" ]] && APP_SOURCE_URLS["$name"]="$source_url"
	[[ -n "$bin_dirs" ]] && APP_BIN_DIRS["$name"]="$bin_dirs"
	return 0
}

node_package() {
	if (($# != 5)); then
		echo "ERROR: node_package requires 5 fields: alias package version bin node_version" >&2
		return 1
	fi

	local alias="$1"
	local package_name
	local version
	local bin_name
	local node_version

	package_name=$(_omw_packages_value "$2")
	version=$(_omw_packages_value "$3")
	bin_name=$(_omw_packages_value "$4")
	node_version=$(_omw_packages_value "$5")

	if ! _omw_packages_has_word "$alias" "${NODE_PACKAGE_LIST[*]:-}"; then
		NODE_PACKAGE_LIST+=("$alias")
	fi

	NODE_PACKAGE_NAMES["$alias"]="$package_name"
	NODE_PACKAGE_VERSIONS["$alias"]="$version"
	NODE_PACKAGE_BINS["$alias"]="$bin_name"
	NODE_PACKAGE_NODE_VERSIONS["$alias"]="$node_version"
	return 0
}

node_cache_package() {
	if (($# != 4)); then
		echo "ERROR: node_cache_package requires 4 fields: alias package version node_version" >&2
		return 1
	fi

	local alias="$1"
	local package_name
	local version
	local node_version

	package_name=$(_omw_packages_value "$2")
	version=$(_omw_packages_value "$3")
	node_version=$(_omw_packages_value "$4")

	if ! _omw_packages_has_word "$alias" "${NODE_CACHE_PACKAGE_LIST[*]:-}"; then
		NODE_CACHE_PACKAGE_LIST+=("$alias")
	fi

	NODE_CACHE_PACKAGE_NAMES["$alias"]="$package_name"
	NODE_CACHE_PACKAGE_VERSIONS["$alias"]="$version"
	NODE_CACHE_PACKAGE_NODE_VERSIONS["$alias"]="$node_version"
	return 0
}

# software fields:
#   1. name       Package name used by `omw build <name>`.
#   2. version    One concrete version; repeat `software` for multiple versions.
#   3. url        Source/archive URL. Use {VERSION} as the version placeholder. Use "-" when not applicable.
#   4. deps       Space-separated dependencies in name@version form. Use "-" for no dependencies.
#   5. build_cmd  Configure command template, or "special" for a dedicated _omw_build_<name> function.
#   6. cflags     Modulefile CFLAGS additions. Use "-" when not needed.
#   7. ldflags    Modulefile LDFLAGS additions. Use "-" when not needed.
#
# Use "-" as the only empty-field placeholder. Do not omit positional fields.
#
# app fields:
#   1. name        App name used by `omw app install <name>`.
#   2. version     One concrete app version.
#   3. url         Prebuilt archive URL.
#   4. executable  Executable name to expose, or "special" for a dedicated installer.
#   5. source_url  Optional source archive URL for offline bundles. Use "-" when not needed.
#   6. bin_dirs    Optional space-separated bin directories to link wholesale. Use "-" when not needed.
#
# node_package fields:
#   1. alias        Short name used by `omw node install <alias>`.
#   2. package      npm package name, scoped names allowed.
#   3. version      Fixed npm package version. Do not use latest or ranges.
#   4. bin          Expected executable name, or "-" when no bin should be checked.
#   5. node_version OMW Node version to load before npm operations.
#
# node_cache_package fields:
#   1. alias        Short name shown in status and verify output.
#   2. package      npm package name, scoped names allowed.
#   3. version      Fixed npm package version. Do not use latest or ranges.
#   4. node_version OMW Node version to load before npm cache operations.

###############################################################################
# Source Builds
###############################################################################

software "openssl" \
	"1.1.1w" \
	"https://www.openssl.org/source/openssl-{VERSION}.tar.gz" \
	"-" \
	"./config --prefix=\$prefix --openssldir=\$prefix" \
	'-I$prefix/include' \
	'-L$prefix/lib -lssl -lcrypto'

software "ncurses" \
	"6.6" \
	"https://ftp.gnu.org/gnu/ncurses/ncurses-{VERSION}.tar.gz" \
	"-" \
	"special" \
	'-I$prefix/include' \
	'-L$prefix/lib -lncursesw -ltinfow'

software "lua" \
	"5.4.7" \
	"https://www.lua.org/ftp/lua-{VERSION}.tar.gz" \
	"-" \
	"special" \
	"-" \
	"-"

software "local" \
	"1.0.0" \
	"-" \
	"-" \
	"special" \
	'-I$prefix/include -I/usr/include' \
	'-L$prefix/lib -L/usr/lib64 -lffi -ltcl8.5 -ltk8.5'

software "libevent" \
	"2.1.12" \
	"https://github.com/libevent/libevent/releases/download/release-{VERSION}-stable/libevent-{VERSION}-stable.tar.gz" \
	"openssl@1.1.1w" \
	"./configure --prefix=\$prefix --enable-shared" \
	"-" \
	"-"

# Optional GCC support. Uncomment to enable; the dedicated builder remains in lib/build.sh.
# software "gcc" \
# 	"13.2.0" \
# 	"https://ftp.gnu.org/gnu/gcc/gcc-{VERSION}/gcc-{VERSION}.tar.gz" \
# 	"-" \
# 	"special" \
# 	"-" \
# 	"-"

software "python" \
	"3.12.12" \
	"https://www.python.org/ftp/python/{VERSION}/Python-{VERSION}.tgz" \
	"openssl@1.1.1w local@1.0.0" \
	"./configure --prefix=\$prefix --with-openssl=\${SOFTWARE_INSTALL_PATH}/openssl/openssl-1.1.1w --with-system-ffi --with-ensurepip=install" \
	"-" \
	"-"

software "node" \
	"22.22.3" \
	"https://unofficial-builds.nodejs.org/download/release/v{VERSION}/node-v{VERSION}-linux-x64-glibc-217.tar.xz" \
	"-" \
	"special" \
	"-" \
	"-"

software "tmux" \
	"3.6b" \
	"https://github.com/tmux/tmux/releases/download/{VERSION}/tmux-{VERSION}.tar.gz" \
	"ncurses@6.6 libevent@2.1.12" \
	"./configure --prefix=\$prefix" \
	"-" \
	"-"

software "zsh" \
	"5.9" \
	"https://sourceforge.net/projects/zsh/files/zsh/{VERSION}/zsh-{VERSION}.tar.xz" \
	"ncurses@6.6" \
	"./configure --prefix=\$prefix --enable-multibyte --enable-pcre --enable-zsh-mem --enable-zsh-debug --with-tcsetpgrp" \
	"-" \
	"-"

software "vim" \
	"9.2.0530" \
	"https://github.com/vim/vim/archive/refs/tags/v{VERSION}.tar.gz" \
	"ncurses@6.6 lua@5.4.7 local@1.0.0 python@3.12.12" \
	"special" \
	"-" \
	"-"

software "ctags" \
	"6.2.1" \
	"https://github.com/universal-ctags/ctags/releases/download/v{VERSION}/universal-ctags-{VERSION}.tar.gz" \
	"-" \
	"special" \
	"-" \
	"-"

###############################################################################
# Prebuilt Apps
###############################################################################

app "exa" \
	"0.10.1" \
	"https://github.com/ogham/exa/releases/download/v0.10.1/exa-linux-x86_64-musl-v0.10.1.zip" \
	"exa" \
	"-" \
	"-"

app "rg" \
	"15.1.0" \
	"https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-unknown-linux-musl.tar.gz" \
	"rg" \
	"-" \
	"-"

app "fzf" \
	"0.72.0" \
	"https://github.com/junegunn/fzf/releases/download/v0.72.0/fzf-0.72.0-linux_amd64.tar.gz" \
	"fzf" \
	"https://github.com/junegunn/fzf/archive/refs/tags/v0.72.0.tar.gz" \
	"-"

app "yazi" \
	"26.5.6" \
	"https://github.com/sxyazi/yazi/releases/download/v26.5.6/yazi-x86_64-unknown-linux-musl.zip" \
	"yazi" \
	"-" \
	"-"

app "fd" \
	"10.4.2" \
	"https://github.com/sharkdp/fd/releases/download/v10.4.2/fd-v10.4.2-x86_64-unknown-linux-musl.tar.gz" \
	"fd" \
	"-" \
	"-"

app "autojump" \
	"22.5.3" \
	"https://github.com/wting/autojump/archive/refs/tags/release-v22.5.3.zip" \
	"special" \
	"-" \
	"-"

app "hack-nerd-font" \
	"3.4.0" \
	"https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Hack.tar.xz" \
	"special" \
	"-" \
	"-"

app "verible" \
	"0.0-4053-g89d4d98a" \
	"https://github.com/chipsalliance/verible/releases/download/v0.0-4053-g89d4d98a/verible-v0.0-4053-g89d4d98a-linux-static-x86_64.tar.gz" \
	"verible-verilog-ls" \
	"-" \
	"bin"

###############################################################################
# Node Global Packages
###############################################################################

# Pin concrete versions for reproducible offline npm cache packing.
node_package "codex" "@openai/codex" "0.133.0" "codex" "22.22.3"
node_package "claude-code" "@anthropic-ai/claude-code" "2.1.150" "claude" "22.22.3"

###############################################################################
# Node Cache-Only Packages
###############################################################################

# Cache-only packages are included in packages/node/npm-cache.tar.gz but are not
# installed by `omw node install-all` or `omw all`.
# node_cache_package "typescript" "typescript" "5.9.3" "22.22.3"
