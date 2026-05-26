# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_build_*.
_omw_build_execute_steps() {
	local build_dir="$1"
	local configure_cmd_template="$2"
	local prefix="$3"
	omw_log "Starting build process in $(basename "$build_dir")" "INFO"
	local log_dir="$build_dir/logs"
	mkdir -p "$log_dir"
	pushd "$build_dir" >/dev/null

	omw_log "Build prefix: $prefix" "DEBUG"
	omw_log "CFLAGS: ${CFLAGS:-}" "DEBUG"
	omw_log "LDFLAGS: ${LDFLAGS:-}" "DEBUG"
	omw_log "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-}" "DEBUG"
	omw_log "PKG_CONFIG_PATH: ${PKG_CONFIG_PATH:-}" "DEBUG"

	for step in "configure" "make" "install"; do
		local cmd
		local log_file
		case "$step" in
		"configure")
			# Use eval to expand variables like $prefix within the command string template
			cmd=$(eval echo "\"$configure_cmd_template\"")
			log_file="$log_dir/configure.omw_log"
			;;
		"make")
			cmd="make -j $BUILD_JOBS"
			log_file="$log_dir/make.omw_log"
			;;
		"install")
			cmd="make install"
			log_file="$log_dir/install.omw_log"
			;;
		esac

		omw_log "Step: $step... (omw_log: $log_file)" "INFO"
		omw_log "Executing command: $cmd" "DEBUG"
		omw_start_spinner
		if ! bash -c "$cmd" &>"$log_file"; then
			omw_stop_spinner
			omw_log "Step '$step' failed. See details below." "ERROR"
			tail -n 20 "$log_file" >&2
			popd >/dev/null
			return 1
		fi
		omw_stop_spinner
		omw_log "Step '$step' completed." "SUCCESS"
	done
	popd >/dev/null
}

# --- Dedicated Build Functions for Each Software ---
_omw_build_ncurses() {
	local build_dir="$1"
	local prefix="$2"
	# local config_cmd="./configure --prefix=$prefix --with-shared --enable-pc-files --enable-widec"
	local config_cmd="./configure --prefix=$prefix --with-normal --disable-widec --with-shared --with-termlib --enable-pc-files --with-pkg-config-libdir=$prefix/lib/pkgconfig --enable-overwrite"
	_omw_build_execute_steps "$build_dir" "$config_cmd" "$prefix"
	config_cmd="./configure --prefix=$prefix --with-normal --enable-widec --with-shared --with-termlib --enable-pc-files --with-pkg-config-libdir=$prefix/lib/pkgconfig --enable-overwrite"
	_omw_build_execute_steps "$build_dir" "$config_cmd" "$prefix"
}

_omw_build_lua() {
	local build_dir="$1"
	local prefix="$2"
	pushd "$build_dir" >/dev/null
	# Lua uses a non-standard build process
	local make_cmd="make linux INSTALL_TOP=$prefix MYCFLAGS=-fPIC"
	local install_cmd="make install INSTALL_TOP=$prefix"
	omw_log "Executing command: $make_cmd" "DEBUG"
	if ! $make_cmd >"$build_dir/make.omw_log" 2>&1; then
		omw_log "make step failed for lua. Check make.omw_log" "ERROR"
		popd >/dev/null
		return 1
	fi
	omw_log "Executing command: $install_cmd" "DEBUG"
	if ! $install_cmd >>"$build_dir/make.omw_log" 2>&1; then
		omw_log "install step failed for lua. Check make.omw_log" "ERROR"
		popd >/dev/null
		return 1
	fi
	popd >/dev/null
}

_omw_build_gcc() {
	local build_dir="$1"
	local prefix="$2"
	pushd "$build_dir" >/dev/null

	omw_log "Preparing GCC prerequisites from local packages..." "INFO"
	local prereq_pkgs
	mapfile -t prereq_pkgs < <(_omw_offline_get_gcc_prereq_pkgs "$build_dir")
	for pkg in "${prereq_pkgs[@]}"; do
		local pkg_path="$PACKAGES_PATH/software/$pkg"
		if [[ ! -f "$pkg_path" ]]; then
			omw_log "Prerequisite package '$pkg' not found. Please run '--pack' or prefetch." "ERROR"
			popd >/dev/null
			return 1
		fi
		# The GCC build expects the extracted source directory, not a symlink
		local prereq_name
		prereq_name="${pkg%%.tar.*}"
		omw_extract_package "$pkg_path" "$build_dir/$prereq_name" 1
	done

	popd >/dev/null
	local config_cmd="./configure --prefix=$prefix --disable-multilib --enable-languages=c,c++,fortran"
	_omw_build_execute_steps "$build_dir" "$config_cmd" "$prefix"
}

_omw_build_vim() {
	local build_dir="$1"
	local prefix="$2"
	local _ version # Get version from prefix
	version=$(basename "$prefix")
	version=${version#vim-}
	# Dynamically find the correct Lua version based on vim's dependency
	local lua_dep
	lua_dep=$(echo "${SOFTWARE_DEPS["vim@$version"]}" | grep -o 'lua@[^ ]*' | head -n 1)
	local lua_name lua_version
	lua_name=${lua_dep%@*}
	lua_version=${lua_dep#*@}
	local py_cfg
	py_cfg=$(python3-config --configdir 2>/dev/null || echo "") # Fails gracefully
	if [[ -z "$py_cfg" ]]; then
		omw_log "python3-config not found. Building vim without python3 support." "WARN"
	fi
	local config_cmd="./configure --prefix=$prefix --with-features=huge --enable-multibyte --enable-perlinterp --with-xsubpp=${SOFTWARE_INSTALL_PATH}/local/local-${SOFTWARE_VERSIONS[local]}/usr/share/perl5/vendor_perl/ExtUtils/xsubpp --enable-luainterp=yes --with-lua-prefix=${SOFTWARE_INSTALL_PATH}/${lua_name}/${lua_name}-${lua_version} --enable-python3interp=yes --with-python3-config-dir=$py_cfg --enable-gui=gtk3 --with-tlib=ncursesw --enable-cscope --enable-fontset --with-compiledby=OMW LDFLAGS=-Wl,-export-dynamic"
	_omw_build_execute_steps "$build_dir" "$config_cmd" "$prefix"
}

_omw_build_ctags() {
	local build_dir="$1"
	local prefix="$2"
	pushd "$build_dir" >/dev/null
	./autogen.sh >"$build_dir/autogen.omw_log" 2>&1
	popd >/dev/null
	local config_cmd="./configure --prefix=$prefix"
	_omw_build_execute_steps "$build_dir" "$config_cmd" "$prefix"
}

_omw_build_node() {
	local build_dir="$1"
	local prefix="$2"

	if [[ ! -x "$build_dir/bin/node" ]]; then
		omw_log "Node binary not found or not executable: $build_dir/bin/node" "ERROR"
		return 1
	fi

	mkdir -p "$prefix"
	cp -a "$build_dir"/. "$prefix"/
	mkdir -p "$prefix/etc" "$prefix/lib/node_modules"
	printf 'prefix=%s\n' "$prefix" >"$prefix/etc/npmrc"
	omw_log "Installed Node binary distribution to $prefix." "SUCCESS"
	omw_log "Set Node package prefix to $prefix." "INFO"
}

# Default build function for software that follows the standard ./configure pattern
_omw_build_default() {
	local appname="$1"
	local build_dir="$2"
	local prefix="$3"
	local config_cmd_template="${SOFTWARE_CONFIG_CMDS[$appname]}"
	_omw_build_execute_steps "$build_dir" "$config_cmd_template" "$prefix"
}

_omw_build_ensure_python_bin_symlink() {
	local prefix="$1"
	local version="$2"
	local bin_dir="$prefix/bin"
	local python_bin="$bin_dir/python"
	local candidate
	local minor_version="${version%.*}"

	if [[ -x "$python_bin" ]]; then
		omw_log "Python executable already exists: $python_bin" "DEBUG"
		return 0
	fi
	if [[ -e "$python_bin" || -L "$python_bin" ]]; then
		omw_log "Python path exists but is not executable: $python_bin" "ERROR"
		return 1
	fi

	for candidate in "$bin_dir/python3" "$bin_dir/python$minor_version"; do
		if [[ -x "$candidate" ]]; then
			ln -s "$(basename "$candidate")" "$python_bin"
			omw_log "Created Python compatibility symlink: $python_bin -> $(basename "$candidate")" "SUCCESS"
			return 0
		fi
	done

	omw_log "No python executable candidate found under $bin_dir." "ERROR"
	return 1
}

_omw_repair_broken_lib64_links() {
	local lib64_dir="$1"
	local prefix="$2"
	local link target basename repaired=0 unresolved=0
	local prefix_lib64=""

	[[ -d "$lib64_dir" ]] || return 0
	[[ -n "$prefix" ]] && prefix_lib64="$prefix/usr/lib64"

	omw_log "Checking broken links in $lib64_dir..." "INFO"
	while IFS= read -r -d $'\0' link; do
		target=$(readlink "$link")
		[[ -n "$target" ]] || continue

		basename=$(basename "$target")
		if [[ -n "$prefix_lib64" && -e "$prefix_lib64/$basename" ]]; then
			ln -snf "$prefix_lib64/$basename" "$link"
			omw_log "Repaired $(basename "$link") -> $prefix_lib64/$basename" "INFO"
			((++repaired))
			continue
		fi

		omw_log "Broken lib64 link unresolved: $link -> $target" "WARN"
		((++unresolved))
	done < <(find "$lib64_dir" -xtype l -print0)

	omw_log "lib64 link repair complete: repaired=$repaired unresolved=$unresolved" "SUCCESS"
}

# Helper function to parse 'name@version' string
omw_parse_target() {
	local target_str="$1"
	local appname="${target_str%@*}"
	local version="${target_str#*@}"
	# If no version is specified, it's just the appname
	if [[ "$appname" == "$version" ]]; then
		version=""
	fi
	# Return as a string to be read by the caller
	echo "$appname $version"
}

# Main dispatcher for building software, now handles versioning
omw_build_software() {
	local target_str="$1" # e.g., "python@3.11.12" or "local"
	local force="${2:-false}"
	local refresh="${3:-false}"

	local appname version
	read -r appname version < <(omw_parse_target "$target_str")

	# Special handling for 'local' target which has no version
	if [[ "$appname" == "local" ]]; then
		# local version uses the key from the config file.
		omw_build_local "$force" "$refresh" "${SOFTWARE_VERSIONS[local]}"
		return $?
	fi
	if [[ -z "${SOFTWARE_VERSIONS[$appname]:-}" ]]; then
		omw_log "No versions defined for '$appname' in packages.sh." "ERROR"
		return 1
	fi
	if [[ -z "$version" ]]; then
		omw_log "No version specified for '$appname'." "ERROR"
		return 1
	fi
	if ! omw_contains_word "$version" "${SOFTWARE_VERSIONS[$appname]}"; then
		omw_log "Version '$version' is not defined for '$appname' in packages.sh." "ERROR"
		return 1
	fi

	omw_log "--- Building $appname $version ---" "INFO"

	if [[ "$refresh" == "true" ]]; then
		omw_log "Refreshing modulefile for $appname@$version." "INFO"
		if ! _omw_build_write_modulefile "$appname" "$version"; then
			return 1
		fi
		omw_log "$appname@$version modulefile refreshed." "SUCCESS"
		return 0
	fi

	# Dependency resolution now respects specific versions
	local deps="${SOFTWARE_DEPS["$appname@$version"]}"
	if [[ -n "$deps" ]]; then
		omw_log "Processing dependencies for $appname@$version: $deps" "DEBUG"
		local dep_target # e.g., "python@3.11.12"
		for dep_target in $deps; do
			local dep_name dep_version
			read -r dep_name dep_version < <(omw_parse_target "$dep_target")
			# Recursively call omw_build_software with the versioned dependency
			if ! omw_build_software "$dep_target"; then
				return 1
			fi
			omw_log "Loading module for dependency: $dep_name/$dep_name-${dep_version}" "INFO"
			omw_ensure_module_command
			if ! module load "$dep_name/$dep_name-${dep_version}"; then
				return 1
			fi
		done
	fi

	local prefix="$SOFTWARE_INSTALL_PATH/$appname/$appname-$version"
	if [[ -d "$prefix" && "$force" == "false" ]]; then
		if ! _omw_build_write_modulefile "$appname" "$version"; then
			return 1
		fi
		omw_log "$appname@$version already installed. Skipping." "INFO"
		return 0
	fi

	local backup_dir=""
	if [[ "$force" == "true" && -d "$prefix" ]]; then
		backup_dir="${prefix}-backup-$(date +%Y%m%d%H%M%S)"
		omw_log "Force build: backing up existing installation to $backup_dir" "WARN"
		mv "$prefix" "$backup_dir"
	fi

	local build_dir="$BUILDS_PATH/$appname-$version"
	omw_safe_rm_rf "$build_dir"

	local url
	url=$(omw_get_software_url "$appname" "$version")
	if [[ -z "$url" ]]; then
		omw_log "No URL template defined for $appname in configuration. Cannot proceed." "ERROR"
		return 1
	fi

	local pkg_path
	pkg_path="$PACKAGES_PATH/software/$(basename "$url")"
	if ! omw_download_package "$url" "$pkg_path" || ! omw_extract_package "$pkg_path" "$build_dir"; then
		omw_safe_rm_rf "$build_dir"
		if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
			omw_log "Restoring previous installation for $appname@$version." "WARN"
			mv "$backup_dir" "$prefix"
		fi
		return 1
	fi

	# Dynamically call the appropriate build function
	local build_func="_omw_build_$appname"
	if declare -F "$build_func" >/dev/null; then
		omw_log "Using dedicated build function for $appname." "DEBUG"
		if ! "$build_func" "$build_dir" "$prefix"; then
			omw_safe_rm_rf "$prefix"
			if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
				omw_log "Restoring previous installation for $appname@$version." "WARN"
				mv "$backup_dir" "$prefix"
			fi
			return 1
		fi
	else
		omw_log "Using default build function for $appname." "DEBUG"
		if ! _omw_build_default "$appname" "$build_dir" "$prefix"; then
			omw_safe_rm_rf "$prefix"
			if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
				omw_log "Restoring previous installation for $appname@$version." "WARN"
				mv "$backup_dir" "$prefix"
			fi
			return 1
		fi
	fi

	if [[ "$appname" == "python" ]] && ! _omw_build_ensure_python_bin_symlink "$prefix" "$version"; then
		omw_safe_rm_rf "$prefix"
		if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
			omw_log "Restoring previous installation for $appname@$version." "WARN"
			mv "$backup_dir" "$prefix"
		fi
		return 1
	fi

	if ! _omw_build_write_modulefile "$appname" "$version"; then
		omw_safe_rm_rf "$prefix"
		if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
			omw_log "Restoring previous installation for $appname@$version." "WARN"
			mv "$backup_dir" "$prefix"
		fi
		return 1
	fi
	omw_log "$appname@$version build process completed." "SUCCESS"
}

omw_build_local() {
	local force="${1:-false}"
	local refresh="${2:-false}"
	local version="${3}" # Version is now passed in
	local prefix="$SOFTWARE_INSTALL_PATH/local/local-$version"
	local rpm_dir="$BUILDS_PATH/local-rpms"
	local pkg_path="$PACKAGES_PATH/rpms.tar.gz"
	omw_log "--- Handling local system dependencies ---" "INFO"

	if [[ "$refresh" == "true" ]]; then
		omw_log "Refreshing modulefile for local." "INFO"
		if ! _omw_build_write_modulefile "local" "$version" ||
			! _omw_build_finalize_local_modulefile "$version"; then
			return 1
		fi
		omw_log "local modulefile refreshed." "SUCCESS"
		return 0
	fi
	if [[ -d "$prefix" && "$force" == "false" ]]; then
		omw_log "Local dependencies installed. Skipping." "INFO"
		return 0
	fi
	local backup_dir=""
	if [[ "$force" == "true" && -d "$prefix" ]]; then
		backup_dir="${prefix}-backup-$(date +%Y%m%d%H%M%S)"
		omw_log "Force build: backing up local dependencies to $backup_dir" "WARN"
		mv "$prefix" "$backup_dir"
	fi

	mkdir -p "$rpm_dir"
	if [[ ! -f "$pkg_path" ]]; then
		omw_log "Downloading system RPMs..."
		local rpms_to_download=(
			"gtk3" "gtk3-devel"
			"libX11" "libX11-devel" "libXt" "libXt-devel" "libSM" "libSM-devel"
			"libICE" "libICE-devel" "libXpm" "libXpm-devel" "xorg-x11-proto-devel"
			"libXau" "libXau-devel" "libXft" "libXft-devel" "libxcb" "libxcb-devel"
			"libXcomposite" "libXcomposite-devel" "libXcursor" "libXcursor-devel"
			"libXdamage" "libXdamage-devel" "libXext" "libXext-devel"
			"libXfixes" "libXfixes-devel" "libXi" "libXi-devel"
			"libXinerama" "libXinerama-devel" "libXrandr" "libXrandr-devel"
			"libXrender" "libXrender-devel" "libXtst" "libXxf86vm" "libXxf86vm-devel"
			"libglvnd" "libglvnd-devel" "libglvnd-core-devel" "libglvnd-egl"
			"libglvnd-gles" "libglvnd-glx" "libglvnd-opengl" "mesa-libEGL" "mesa-libGL"
			"mesa-libGLES" "mesa-libgbm" "mesa-libglapi"
			"libdrm" "libdrm-devel" "libepoxy" "libepoxy-devel" "perl-devel"
			"perl-ExtUtils-Embed" "perl-ExtUtils-ParseXS" "perl-ExtUtils-MakeMaker" "help2man" "freetype" "freetype-devel"
			"zlib" "zlib-devel" "bzip2-libs" "bzip2-devel" "libffi" "libffi-devel"
			"sqlite" "sqlite-devel" "tkinter" "tcl" "tcl-devel" "tk" "tk-devel"
			"readline" "readline-devel" "ncurses-libs" "ncurses-devel"
			"gdbm" "gdbm-devel" "libdb" "libdb-devel" "dbus-libs" "dbus-devel"
			"pcre" "pcre-devel"
			"python3-tkinter" "xz-devel" "lzma" "autoconf" "automake"
			"binutils" "bison" "flex" "gettext" "libtool" "patch"
			"pkgconfig"
		)
		omw_start_spinner
		if ! yumdownloader --downloadonly --destdir="$rpm_dir" --resolve --archlist=x86_64,noarch "${rpms_to_download[@]}" >/dev/null; then
			omw_stop_spinner
			omw_log "RPM dependency download failed." "ERROR"
			[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
			return 1
		fi
		omw_stop_spinner
		find "$rpm_dir" -name "*.i686.rpm" -delete
	else
		omw_log "Using pre-packaged RPMs from $pkg_path" "INFO"
		if ! omw_extract_package "$pkg_path" "$rpm_dir" 0; then
			[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
			return 1
		fi
	fi

	local rpm_count
	rpm_count=$(find "$rpm_dir" -maxdepth 1 -name "*.rpm" | wc -l)
	if ((rpm_count == 0)); then
		omw_log "No RPM files found in $rpm_dir." "ERROR"
		[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
		return 1
	fi

	if ! omw_extract_rpms_to_prefix "$rpm_dir" "$prefix"; then
		omw_safe_rm_rf "$prefix"
		[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
		return 1
	fi

	omw_log "Writing local RPM bundle to $pkg_path." "INFO"
	if ! tar -czf "$pkg_path" -C "$rpm_dir" .; then
		omw_safe_rm_rf "$prefix"
		[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
		omw_log "Failed to write local RPM bundle." "ERROR"
		return 1
	fi
	_omw_repair_broken_lib64_links "$prefix/usr/lib64" "$prefix"

	# Adjust pkg-config files after extraction.
	if ! find "$prefix" -name "*.pc" -exec sed -i \
		-e "s|=/usr|=$prefix/usr|g" \
		-e "s|-I/usr|-I$prefix/usr|g" \
		-e "s|-L/usr|-L$prefix/usr|g" \
		{} +; then
		omw_safe_rm_rf "$prefix"
		[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
		omw_log "Failed to adjust pkg-config files for local dependencies." "ERROR"
		return 1
	fi

	if ! _omw_build_write_modulefile "local" "$version"; then
		omw_safe_rm_rf "$prefix"
		[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
		return 1
	fi
	if ! _omw_build_finalize_local_modulefile "$version"; then
		omw_safe_rm_rf "$prefix"
		[[ -n "$backup_dir" && -d "$backup_dir" ]] && mv "$backup_dir" "$prefix"
		return 1
	fi
}

_omw_build_finalize_local_modulefile() {
	local version="$1"
	local modulefile_path="$MODULEFILES_PATH/local/local-$version"

	if ! sed -i "s|set prefix.*|set prefix  \$base/local/local-$version/usr|g" "$modulefile_path" ||
		! sed -i "s|\$prefix/lib|\$prefix/lib64|g" "$modulefile_path" ||
		! cat >>"$modulefile_path" <<-EOF; then
			prepend-path PKG_CONFIG_PATH    \$prefix/share/pkgconfig
			prepend-path PERL5LIB           \$prefix/share/perl5
			prepend-path PERL5LIB           \$prefix/share/perl5/vendor_perl
			# prepend-path C_INCLUDE_PATH     \$prefix/lib64/perl5/CORE
			# prepend-path CPLUS_INCLUDE_PATH \$prefix/lib64/perl5/CORE
		EOF
		omw_log "Failed to finalize local modulefile." "ERROR"
		return 1
	fi
}

# Generates a modulefile with version-specific dependencies
_omw_build_write_modulefile() {
	local appname="$1"
	local version="$2"
	local modulefile_path="$MODULEFILES_PATH/$appname/$appname-$version"
	omw_log "Generating modulefile for $appname@$version" "INFO"
	mkdir -p "$(dirname "$modulefile_path")"
	cat >"$modulefile_path" <<-EOF
		#%Module1.0
		proc ModulesHelp { } { puts stderr "Loads $appname version $version" }
		module-whatis "Software: $appname $version"
		set base    \$env(OMW_HOME)/tools/software
		set prefix  \$base/$appname/$appname-$version
	EOF
	# Load dependencies before this module prepends its own paths.
	local deps="${SOFTWARE_DEPS["$appname@$version"]:-}"
	if [[ -n "$deps" ]]; then
		echo "" >>"$modulefile_path"
		local dep_target
		for dep_target in $deps; do
			local dep_name dep_version
			read -r dep_name dep_version < <(omw_parse_target "$dep_target")
			echo "module load $dep_name/$dep_name-${dep_version}" >>"$modulefile_path"
		done
		echo "" >>"$modulefile_path"
	fi
	cat >>"$modulefile_path" <<-EOF
		prepend-path PATH              \$prefix/bin
		prepend-path LIBRARY_PATH      \$prefix/lib
		prepend-path LD_LIBRARY_PATH   \$prefix/lib
		prepend-path PKG_CONFIG_PATH   \$prefix/lib/pkgconfig
		prepend-path MANPATH           \$prefix/share/man
		prepend-path C_INCLUDE_PATH    \$prefix/include
		prepend-path CPLUS_INCLUDE_PATH \$prefix/include
	EOF
	if [[ "$appname" == "node" ]]; then
		cat >>"$modulefile_path" <<-EOF
			setenv NPM_CONFIG_PREFIX     \$prefix
			setenv npm_config_prefix     \$prefix
		EOF
	fi
	# Add custom compiler flags if defined in packages.sh
	local cflags="${SOFTWARE_CFLAGS[$appname]:-}"
	local ldflags="${SOFTWARE_LDFLAGS[$appname]:-}"
	if [[ -n "$cflags" || -n "$ldflags" ]]; then
		cat >>"$modulefile_path" <<-EOF

			# Custom compiler flags
			if {[info exists env(CFLAGS)]} {
			    setenv CFLAGS "\$env(CFLAGS) ${cflags}"
			} else {
			    setenv CFLAGS "${cflags}"
			}
			if {[info exists env(LDFLAGS)]} {
			    setenv LDFLAGS "\$env(LDFLAGS) ${ldflags}"
			} else {
			    setenv LDFLAGS "${ldflags}"
			}
		EOF
	fi
}
