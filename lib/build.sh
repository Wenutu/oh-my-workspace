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
		if ! bash -c "$cmd" &>"$log_file"; then
			omw_log "Step '$step' failed. See details below." "ERROR"
			tail -n 20 "$log_file" >&2
			popd >/dev/null
			return 1
		fi
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
	mapfile -t prereq_pkgs < <(omw_gcc_prereq_packages_from_script "$build_dir/contrib/download_prerequisites")
	for pkg in "${prereq_pkgs[@]}"; do
		local pkg_path="$PACKAGES_PATH/$pkg"
		if [[ ! -f "$pkg_path" ]]; then
			omw_log "Prerequisite package '$pkg' not found. Please run 'offline pack' or prefetch." "ERROR"
			popd >/dev/null
			return 1
		fi
		# GCC expects prerequisites at fixed short names: gmp, mpfr, mpc, isl.
		local prereq_name
		prereq_name="${pkg%%.tar.*}"
		if ! omw_extract_package "$pkg_path" "$build_dir/$prereq_name" 1; then
			popd >/dev/null
			return 1
		fi
		local prereq_link="${prereq_name%%-*}"
		rm -f "$build_dir/$prereq_link"
		ln -s "$prereq_name" "$build_dir/$prereq_link"
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
	local version
	local key
	version=$(basename "$prefix")
	version=${version#"$appname"-}
	key="$appname@$version"
	local config_cmd_template="${SOFTWARE_CONFIG_CMDS[$key]:-${SOFTWARE_CONFIG_CMDS[$appname]:-}}"
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
	local system_lib64="${3:-/lib64}"
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
		if [[ -d "$system_lib64" && -e "$system_lib64/$basename" ]]; then
			ln -snf "$system_lib64/$basename" "$link"
			omw_log "Repaired $(basename "$link") -> $system_lib64/$basename" "INFO"
			((++repaired))
			continue
		fi

		omw_log "Broken lib64 link unresolved: $link -> $target" "WARN"
		((++unresolved))
	done < <(find "$lib64_dir" -xtype l -print0)

	omw_log "lib64 link repair complete: repaired=$repaired unresolved=$unresolved" "SUCCESS"
}

omw_local_rpm_bundle_path() {
	local version="$1"
	printf '%s/local-%s-rpms.tar.gz' "$PACKAGES_PATH" "$version"
}

_omw_build_merge_rpm_file() {
	local source="$1"
	local dest_dir="$2"
	local dest="$dest_dir/$(basename "$source")"
	local source_sha dest_sha

	if [[ -f "$dest" ]]; then
		source_sha=$(omw_file_sha256 "$source") || return 1
		dest_sha=$(omw_file_sha256 "$dest") || return 1
		if [[ "$source_sha" == "$dest_sha" ]]; then
			omw_log "Skipping duplicate RPM with matching sha256: $(basename "$source")" "INFO"
			return 0
		fi
		omw_log "RPM name collision with different sha256: $(basename "$source")" "ERROR"
		return 1
	fi
	cp -p "$source" "$dest"
}

_omw_build_merge_rpms_from_archive() {
	local archive_path="$1"
	local rpm_dir="$2"
	local merge_dir="$BUILDS_PATH/.tmp-merge-local-rpms-$$"
	local rpm

	[[ -f "$archive_path" ]] || return 0
	omw_safe_rm_rf "$merge_dir"
	mkdir -p "$merge_dir"
	if ! omw_extract_package "$archive_path" "$merge_dir" 0; then
		omw_safe_rm_rf "$merge_dir"
		return 1
	fi
	while IFS= read -r -d $'\0' rpm; do
		_omw_build_merge_rpm_file "$rpm" "$rpm_dir" || {
			omw_safe_rm_rf "$merge_dir"
			return 1
		}
	done < <(find "$merge_dir" -maxdepth 1 -name "*.rpm" -print0)
	omw_safe_rm_rf "$merge_dir"
}

_omw_build_download_rpm_urls_with_wget() {
	local dest_dir="$1"
	local yum_log="$2"
	shift 2
	local urls_file="$BUILDS_PATH/.tmp-local-rpm-urls-$$"
	local url dest seen_url duplicate_url
	local -a missing_urls=()
	local -a seen_urls=()

	: >"$urls_file"
	if ! yumdownloader --urls --resolve "--archlist=x86_64,noarch" "--exclude=*.i686" "--exclude=*.i386" "$@" >"$urls_file" 2>>"$yum_log"; then
		omw_log "Failed to resolve RPM URLs with yumdownloader --urls." "ERROR"
		rm -f "$urls_file"
		return 1
	fi
	while IFS= read -r url; do
		[[ "$url" == http://* || "$url" == https://* || "$url" == ftp://* ]] || continue
		duplicate_url=false
		for seen_url in "${seen_urls[@]+"${seen_urls[@]}"}"; do
			if [[ "$seen_url" == "$url" ]]; then
				duplicate_url=true
				break
			fi
		done
		if [[ "$duplicate_url" == "true" ]]; then
			continue
		fi
		seen_urls+=("$url")
		dest="$dest_dir/$(basename "$url")"
		if [[ -f "$dest" && $(_omw_fs_file_size "$dest") -gt 100 ]]; then
			continue
		fi
		missing_urls+=("$url")
	done <"$urls_file"

	omw_log "Downloading ${#missing_urls[@]} missing RPM(s) with wget." "INFO"
	for url in "${missing_urls[@]}"; do
		dest="$dest_dir/$(basename "$url")"
		if ! wget --tries=3 --timeout="$DOWNLOAD_TIMEOUT" -O "$dest" "$url" >>"$yum_log" 2>&1; then
			omw_log "Failed to download RPM URL: $url" "ERROR"
			rm -f "$urls_file"
			return 1
		fi
	done
	rm -f "$urls_file"
}

_omw_build_clean_rpm_tmp_files() {
	local rpm_dir="$1"

	[[ -d "$rpm_dir" ]] || return 0
	find "$rpm_dir" -maxdepth 1 -type f -name "*.tmp" -delete
}

_omw_build_replace_local_rpm_dir() {
	local source_dir="$1"
	local dest_dir="$2"

	omw_safe_rm_rf "$dest_dir" || return 1
	mv "$source_dir" "$dest_dir"
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

	local prefix
	prefix=$(omw_software_prefix "$appname" "$version")
	if [[ -d "$prefix" && "$force" == "false" ]]; then
		if ! _omw_build_write_modulefile "$appname" "$version"; then
			return 1
		fi
		omw_log "$appname@$version already installed. Skipping." "INFO"
		return 0
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
	pkg_path=$(omw_software_package_path "$appname" "$version")
	if ! omw_download_package "$url" "$pkg_path" || ! omw_extract_package "$pkg_path" "$build_dir"; then
		omw_safe_rm_rf "$build_dir"
		return 1
	fi

	omw_tx_begin || return 1
	omw_tx_backup_internal "$prefix" || {
		omw_tx_rollback
		return 1
	}

	# Use a declared command when present; otherwise require the conventional hook.
	local build_func="_omw_build_$appname"
	local build_cmd="${SOFTWARE_CONFIG_CMDS["$appname@$version"]:-}"
	if [[ -n "$build_cmd" ]]; then
		omw_log "Using declared build command for $appname." "DEBUG"
		if ! _omw_build_default "$appname" "$build_dir" "$prefix"; then
			omw_tx_rollback
			return 1
		fi
	elif declare -F "$build_func" >/dev/null; then
		omw_log "Using dedicated build function for $appname." "DEBUG"
		if ! "$build_func" "$build_dir" "$prefix"; then
			omw_tx_rollback
			return 1
		fi
	else
		omw_log "No build command or hook defined for $appname@$version." "ERROR"
		omw_tx_rollback
		return 1
	fi

	if [[ "$appname" == "python" ]] && ! _omw_build_ensure_python_bin_symlink "$prefix" "$version"; then
		omw_tx_rollback
		return 1
	fi

	if ! _omw_build_write_modulefile "$appname" "$version"; then
		omw_tx_rollback
		return 1
	fi
	omw_tx_commit
	omw_log "$appname@$version build process completed." "SUCCESS"
}

omw_prepare_build_software() {
	local target_str="$1"
	local appname version key deps dep url pkg_path

	read -r appname version < <(omw_parse_target "$target_str")
	if [[ -z "$appname" || -z "$version" ]]; then
		omw_log "Build prepare requires a versioned target: $target_str" "ERROR"
		return 1
	fi
	if [[ -z "${SOFTWARE_VERSIONS[$appname]:-}" ]]; then
		omw_log "No versions defined for '$appname' in packages.sh." "ERROR"
		return 1
	fi
	if ! omw_contains_word "$version" "${SOFTWARE_VERSIONS[$appname]}"; then
		omw_log "Version '$version' is not defined for '$appname' in packages.sh." "ERROR"
		return 1
	fi

	key="$appname@$version"
	[[ "${OMW_BUILD_PREPARE_SEEN[$key]:-false}" == "true" ]] && return 0
	OMW_BUILD_PREPARE_SEEN[$key]=true

	deps="${SOFTWARE_DEPS[$key]:-}"
	for dep in $deps; do
		omw_prepare_build_software "$dep" || return 1
	done

	if [[ "$appname" == "local" ]]; then
		omw_log "Preparing build packages for local@$version." "INFO"
		omw_check_sys_deps local || return 1
		omw_prepare_local_rpm_bundle "$version"
		return
	fi

	url=$(omw_get_software_url "$appname" "$version")
	if [[ -z "$url" ]]; then
		omw_log "No URL template defined for $appname@$version in configuration." "ERROR"
		return 1
	fi
	pkg_path=$(omw_software_package_path "$appname" "$version") || return 1
	omw_log "Preparing build package for $appname@$version." "INFO"
	omw_download_package "$url" "$pkg_path" || return 1

	if [[ "$appname" == "gcc" ]] && declare -F omw_prepare_gcc_prereq_packages >/dev/null; then
		omw_prepare_gcc_prereq_packages "$version" || return 1
	fi
}

omw_build_local() {
	local force="${1:-false}"
	local refresh="${2:-false}"
	local version="${3}" # Version is now passed in
	local prefix
	prefix=$(omw_software_prefix "local" "$version")
	local rpm_dir="$BUILDS_PATH/local-${version}-rpms"
	local pkg_path
	pkg_path=$(omw_local_rpm_bundle_path "$version")
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
	omw_tx_begin || return 1
	omw_tx_backup_internal "$prefix" || {
		omw_tx_rollback
		return 1
	}

	if ! omw_prepare_local_rpm_bundle "$version"; then
		omw_tx_rollback
		return 1
	fi
	pkg_path=$(omw_local_rpm_bundle_path "$version")
	omw_safe_rm_rf "$rpm_dir"
	if ! omw_extract_package "$pkg_path" "$rpm_dir" 0; then
		omw_tx_rollback
		return 1
	fi

	local rpm_count
	rpm_count=$(find "$rpm_dir" -maxdepth 1 -name "*.rpm" | wc -l)
	if ((rpm_count == 0)); then
		omw_log "No RPM files found in $rpm_dir." "ERROR"
		omw_tx_rollback
		return 1
	fi

	if ! omw_extract_rpms_to_prefix "$rpm_dir" "$prefix"; then
		omw_safe_rm_rf "$prefix"
		omw_tx_rollback
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
		omw_tx_rollback
		omw_log "Failed to adjust pkg-config files for local dependencies." "ERROR"
		return 1
	fi

	if ! _omw_build_write_modulefile "local" "$version"; then
		omw_safe_rm_rf "$prefix"
		omw_tx_rollback
		return 1
	fi
	if ! _omw_build_finalize_local_modulefile "$version"; then
		omw_safe_rm_rf "$prefix"
		omw_tx_rollback
		return 1
	fi
	omw_tx_commit
}

omw_prepare_local_rpm_bundle() {
	local version="${1:-${SOFTWARE_VERSIONS[local]}}"
	local rpm_dir="$BUILDS_PATH/local-${version}-rpms"
	local rpm_stage="$BUILDS_PATH/.tmp-local-${version}-rpms-$$"
	local pkg_path
	pkg_path=$(omw_local_rpm_bundle_path "$version")

	if [[ -f "$pkg_path" ]] && omw_archive_is_readable "$pkg_path"; then
		omw_log "Using pre-packaged RPMs from $pkg_path" "INFO"
		return 0
	fi
	omw_safe_rm_rf "$rpm_stage"
	mkdir -p "$rpm_stage"
	omw_log "Downloading system RPMs..." "INFO"
	local rpms_to_download=(
		"gtk3-devel" "libX11-devel" "libXt-devel" "libSM-devel" "libICE-devel" "libXpm-devel" "libXft-devel" "xorg-x11-proto-devel"
		"perl-ExtUtils-Embed" "perl-ExtUtils-ParseXS" "perl-ExtUtils-MakeMaker"
		"help2man"
		"freetype-devel" "zlib-devel" "bzip2-devel"
		"libffi-devel" "sqlite-devel" "tkinter" "tcl-devel" "tk-devel" "readline-devel"
		"python3-tkinter" "xz-devel" "lzma" "autoconf" "automake"
		"binutils" "bison" "flex" "gettext" "libtool" "patch"
		"pkgconfig" "xsel"
	)
	local yum_log
	yum_log="$BUILDS_PATH/local-rpms-yumdownloader.log"
	: >"$yum_log"
	omw_log "RPM download staging directory: $rpm_stage" "INFO"
	omw_log "yumdownloader log: $yum_log" "INFO"
	local yumdownloader_cmd=(
		yumdownloader
		--downloadonly
		--destdir="$rpm_stage"
		--resolve
		"--archlist=x86_64,noarch"
		"--exclude=*.i686"
		"--exclude=*.i386"
		"${rpms_to_download[@]}"
	)
	local yumdownloader_ok=false
	local yumdownloader_attempt
	for yumdownloader_attempt in 1 2 3; do
		: >"$yum_log"
		if "${yumdownloader_cmd[@]}" >"$yum_log" 2>&1; then
			yumdownloader_ok=true
			break
		fi
		if ((yumdownloader_attempt < 3)); then
			omw_log "RPM dependency download failed; cleaning partial RPM downloads before retry." "WARN"
			_omw_build_clean_rpm_tmp_files "$rpm_stage"
			yum --enablerepo=base clean metadata >>"$yum_log" 2>&1 || true
			yum -y makecache >>"$yum_log" 2>&1 || true
		fi
	done
	if [[ "$yumdownloader_ok" != "true" ]]; then
		omw_log "yumdownloader file download failed; using wget to download missing RPMs." "WARN"
		_omw_build_clean_rpm_tmp_files "$rpm_stage"
		if _omw_build_download_rpm_urls_with_wget "$rpm_stage" "$yum_log" "${rpms_to_download[@]}"; then
			yumdownloader_ok=true
		fi
	fi
	if [[ "$yumdownloader_ok" != "true" ]]; then
		omw_log "RPM dependency download failed." "ERROR"
		omw_log "Command: ${yumdownloader_cmd[*]}" "ERROR"
		omw_log "Requested RPM dependencies (${#rpms_to_download[@]}): ${rpms_to_download[*]}" "ERROR"
		omw_log "Full yumdownloader log: $yum_log" "ERROR"
		if command -v yum >/dev/null 2>&1; then
			omw_log "Enabled yum repositories:" "ERROR"
			yum repolist enabled 2>&1 | sed 's/^/  /' >&2 || true
		fi
		omw_log "Last 80 lines from yumdownloader:" "ERROR"
		tail -n 80 "$yum_log" >&2 || true
		omw_safe_rm_rf "$rpm_stage"
		return 1
	fi
	_omw_build_clean_rpm_tmp_files "$rpm_stage"
	find "$rpm_stage" -name "*.i686.rpm" -delete

	local rpm_count
	rpm_count=$(find "$rpm_stage" -maxdepth 1 -name "*.rpm" | wc -l)
	if ((rpm_count == 0)); then
		omw_log "No RPM files found in $rpm_stage." "ERROR"
		omw_safe_rm_rf "$rpm_stage"
		return 1
	fi

	omw_log "Writing local RPM bundle to $pkg_path." "INFO"
	mkdir -p "$(dirname "$pkg_path")"
	if [[ -f "$pkg_path" ]] && ! _omw_build_merge_rpms_from_archive "$pkg_path" "$rpm_stage"; then
		omw_log "Failed to merge existing local RPM bundle." "ERROR"
		omw_safe_rm_rf "$rpm_stage"
		return 1
	fi
	if ! tar -czf "$pkg_path" -C "$rpm_stage" .; then
		omw_log "Failed to write local RPM bundle." "ERROR"
		omw_safe_rm_rf "$rpm_stage"
		return 1
	fi
	_omw_build_replace_local_rpm_dir "$rpm_stage" "$rpm_dir"
}

omw_clean_source_builds() {
	local dry_run="${1:-false}"
	if [[ "$dry_run" == "true" ]]; then
		printf 'Would remove: %s\n' "$BUILDS_PATH"
	else
		omw_safe_rm_rf "$BUILDS_PATH"
	fi
}

omw_clean_software_installs() {
	local dry_run="${1:-false}"
	local path
	for path in "$SOFTWARE_INSTALL_PATH" "$MODULEFILES_PATH"; do
		if [[ "$dry_run" == "true" ]]; then
			printf 'Would remove: %s\n' "$path"
		else
			omw_safe_rm_rf "$path"
		fi
	done
}

_omw_build_finalize_local_modulefile() {
	local version="$1"
	local modulefile_path
	modulefile_path=$(omw_software_modulefile "local" "$version")

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
	local modulefile_path
	modulefile_path=$(omw_software_modulefile "$appname" "$version")
	local tmp_modulefile="${modulefile_path}.tmp-$$"
	omw_log "Generating modulefile for $appname@$version" "INFO"
	mkdir -p "$(dirname "$modulefile_path")"
	cat >"$tmp_modulefile" <<-EOF
		#%Module1.0
		proc ModulesHelp { } { puts stderr "Loads $appname version $version" }
		module-whatis "Software: $appname $version"
		set base    \$env(OMW_HOME)/tools/software
		set prefix  \$base/$appname/$appname-$version
		conflict $appname
	EOF
	# Load dependencies before this module prepends its own paths.
	local deps="${SOFTWARE_DEPS["$appname@$version"]:-}"
	if [[ -n "$deps" ]]; then
		echo "" >>"$tmp_modulefile"
		local dep_target
		for dep_target in $deps; do
			local dep_name dep_version
			read -r dep_name dep_version < <(omw_parse_target "$dep_target")
			echo "module load $dep_name/$dep_name-${dep_version}" >>"$tmp_modulefile"
		done
		echo "" >>"$tmp_modulefile"
	fi
	cat >>"$tmp_modulefile" <<-EOF
		prepend-path PATH              \$prefix/bin
		prepend-path LIBRARY_PATH      \$prefix/lib
		prepend-path LD_LIBRARY_PATH   \$prefix/lib
		prepend-path PKG_CONFIG_PATH   \$prefix/lib/pkgconfig
		prepend-path MANPATH           \$prefix/share/man
		prepend-path C_INCLUDE_PATH    \$prefix/include
		prepend-path CPLUS_INCLUDE_PATH \$prefix/include
	EOF
	if [[ "$appname" == "node" ]]; then
		cat >>"$tmp_modulefile" <<-EOF
			setenv NPM_CONFIG_PREFIX     \$prefix
			setenv npm_config_prefix     \$prefix
		EOF
	fi
	# Add custom compiler flags if defined in packages.sh
	local key="$appname@$version"
	local cflags="${SOFTWARE_CFLAGS[$key]:-${SOFTWARE_CFLAGS[$appname]:-}}"
	local ldflags="${SOFTWARE_LDFLAGS[$key]:-${SOFTWARE_LDFLAGS[$appname]:-}}"
	if [[ -n "$cflags" || -n "$ldflags" ]]; then
		cat >>"$tmp_modulefile" <<-EOF

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
	mv -f "$tmp_modulefile" "$modulefile_path"
}
