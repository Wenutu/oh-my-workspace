# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_node_*.

_omw_node_cache_dir() {
	if [[ -n "${OMW_NODE_CACHE_DIR_OVERRIDE:-}" ]]; then
		printf '%s' "$OMW_NODE_CACHE_DIR_OVERRIDE"
		return 0
	fi
	printf '%s/node/npm-cache' "$BUILDS_PATH"
}

_omw_node_cache_archive_path() {
	printf '%s/node/npm-cache.tar.gz' "$PACKAGES_PATH"
}

_omw_node_prefix() {
	local node_version="$1"
	printf '%s/node/node-%s' "$SOFTWARE_INSTALL_PATH" "$node_version"
}

_omw_node_modulefile() {
	local node_version="$1"
	printf '%s/node/node-%s' "$MODULEFILES_PATH" "$node_version"
}

_omw_node_package_spec() {
	local alias="$1"
	printf '%s@%s' "${NODE_PACKAGE_NAMES[$alias]}" "${NODE_PACKAGE_VERSIONS[$alias]}"
}

_omw_node_cache_package_spec() {
	local alias="$1"
	printf '%s@%s' "${NODE_CACHE_PACKAGE_NAMES[$alias]}" "${NODE_CACHE_PACKAGE_VERSIONS[$alias]}"
}

_omw_node_has_packages() {
	((${#NODE_PACKAGE_LIST[@]} > 0))
}

_omw_node_has_cache_packages() {
	((${#NODE_CACHE_PACKAGE_LIST[@]} > 0))
}

_omw_node_has_any_packages() {
	_omw_node_has_packages || _omw_node_has_cache_packages
}

omw_node_has_any_packages() {
	_omw_node_has_any_packages
}

omw_node_cache_available() {
	_omw_node_cache_ready || _omw_node_cache_archive_ready
}

_omw_node_require_alias() {
	local alias="$1"
	if [[ -z "${NODE_PACKAGE_NAMES[$alias]:-}" ]]; then
		omw_log "Unknown Node package alias: $alias" "ERROR"
		return 1
	fi
}

_omw_node_require_cache_alias() {
	local alias="$1"
	if [[ -z "${NODE_CACHE_PACKAGE_NAMES[$alias]:-}" ]]; then
		omw_log "Unknown Node cache-only package alias: $alias" "ERROR"
		return 1
	fi
}

_omw_node_unique_versions() {
	local alias node_version seen=" "
	for alias in "${NODE_PACKAGE_LIST[@]}"; do
		node_version="${NODE_PACKAGE_NODE_VERSIONS[$alias]:-}"
		[[ -n "$node_version" ]] || continue
		if [[ "$seen" != *" $node_version "* ]]; then
			printf '%s\n' "$node_version"
			seen+="$node_version "
		fi
	done
	for alias in "${NODE_CACHE_PACKAGE_LIST[@]}"; do
		node_version="${NODE_CACHE_PACKAGE_NODE_VERSIONS[$alias]:-}"
		[[ -n "$node_version" ]] || continue
		if [[ "$seen" != *" $node_version "* ]]; then
			printf '%s\n' "$node_version"
			seen+="$node_version "
		fi
	done
}

_omw_node_aliases_for_version() {
	local node_version="$1"
	local alias
	for alias in "${NODE_PACKAGE_LIST[@]}"; do
		[[ "${NODE_PACKAGE_NODE_VERSIONS[$alias]:-}" == "$node_version" ]] && printf '%s\n' "$alias"
	done
}

_omw_node_cache_aliases_for_version() {
	local node_version="$1"
	local alias
	for alias in "${NODE_CACHE_PACKAGE_LIST[@]}"; do
		[[ "${NODE_CACHE_PACKAGE_NODE_VERSIONS[$alias]:-}" == "$node_version" ]] && printf '%s\n' "$alias"
	done
}

_omw_node_load_version() {
	local node_version="$1"
	local module_name="node/node-$node_version"

	omw_ensure_module_command || return 1
	if [[ ! -f "$(_omw_node_modulefile "$node_version")" ]]; then
		omw_log "Node modulefile is missing: $(_omw_node_modulefile "$node_version")" "ERROR"
		return 1
	fi
	omw_log "Loading Node module: $module_name" "INFO"
	module purge || return 1
	module load "$module_name" || return 1
	if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
		omw_log "Node module '$module_name' did not expose both node and npm." "ERROR"
		return 1
	fi
	omw_log "Using $(node --version) with npm $(npm --version)" "INFO"
}

_omw_node_ensure_node_for_pack() {
	local node_version="$1"
	local prefix
	prefix=$(_omw_node_prefix "$node_version")

	if [[ -x "$prefix/bin/node" && -x "$prefix/bin/npm" && -f "$(_omw_node_modulefile "$node_version")" ]]; then
		return 0
	fi

	omw_log "Node $node_version is needed for npm cache packing; building OMW Node first." "WARN"
	omw_build_software "node@$node_version" "false" "false"
}

_omw_node_cache_ready() {
	local cache_dir
	cache_dir=$(_omw_node_cache_dir)
	[[ -d "$cache_dir" ]] || return 1
	find "$cache_dir" -mindepth 1 -print -quit | grep -q .
}

_omw_node_cache_archive_ready() {
	local archive_path
	archive_path=$(_omw_node_cache_archive_path)
	[[ -f "$archive_path" ]] || return 1
	tar -tzf "$archive_path" >/dev/null
}

_omw_node_restore_cache_archive() {
	local cache_dir archive_path
	cache_dir=$(_omw_node_cache_dir)
	archive_path=$(_omw_node_cache_archive_path)

	if ! _omw_node_cache_archive_ready; then
		return 1
	fi

	omw_log "Restoring npm cache from $archive_path to $cache_dir" "INFO"
	mkdir -p "$(dirname "$cache_dir")"
	omw_safe_rm_rf "$cache_dir"
	if ! tar -xzf "$archive_path" -C "$(dirname "$cache_dir")"; then
		omw_log "Failed to restore npm cache archive: $archive_path" "ERROR"
		return 1
	fi
	_omw_node_cache_ready
}

_omw_node_write_cache_archive() {
	local cache_dir archive_path tmp_archive
	cache_dir=$(_omw_node_cache_dir)
	archive_path=$(_omw_node_cache_archive_path)

	if ! _omw_node_cache_ready; then
		omw_log "Cannot archive missing or empty npm cache: $cache_dir" "ERROR"
		return 1
	fi

	mkdir -p "$(dirname "$archive_path")"
	tmp_archive="$(dirname "$archive_path")/.npm-cache.tar.gz.$$"
	omw_log "Compressing npm cache to $archive_path" "INFO"
	if ! tar -czf "$tmp_archive" -C "$(dirname "$cache_dir")" "$(basename "$cache_dir")"; then
		rm -f "$tmp_archive"
		omw_log "Failed to compress npm cache." "ERROR"
		return 1
	fi
	mv -f "$tmp_archive" "$archive_path"
	omw_log "npm cache archive created: $archive_path" "SUCCESS"
}

_omw_node_restore_cache_override() {
	local old_cache_override="$1"
	local temp_root="${2:-}"

	[[ -n "$temp_root" ]] && omw_safe_rm_rf "$temp_root"
	if [[ -n "$old_cache_override" ]]; then
		OMW_NODE_CACHE_DIR_OVERRIDE="$old_cache_override"
	else
		unset OMW_NODE_CACHE_DIR_OVERRIDE
	fi
}

omw_node_package_status() {
	local alias="$1"
	local node_version="${NODE_PACKAGE_NODE_VERSIONS[$alias]:-}"
	local bin_name="${NODE_PACKAGE_BINS[$alias]:-}"
	local package_name="${NODE_PACKAGE_NAMES[$alias]:-}"
	local prefix package_dir

	_omw_node_require_alias "$alias" || {
		printf 'missing'
		return 0
	}
	prefix=$(_omw_node_prefix "$node_version")
	package_dir="$prefix/lib/node_modules/$package_name"

	if [[ ! -f "$(_omw_node_modulefile "$node_version")" ]]; then
		printf 'missing'
	elif [[ -n "$bin_name" && -x "$prefix/bin/$bin_name" && -d "$package_dir" ]]; then
		printf 'installed'
	elif [[ -z "$bin_name" && -d "$package_dir" ]]; then
		printf 'installed'
	elif [[ -n "$bin_name" && ( -e "$prefix/bin/$bin_name" || -d "$package_dir" ) ]]; then
		printf 'partial'
	else
		printf 'available'
	fi
}

omw_node_cache_package_status() {
	local alias="$1"
	local node_version="${NODE_CACHE_PACKAGE_NODE_VERSIONS[$alias]:-}"

	_omw_node_require_cache_alias "$alias" || {
		printf 'missing'
		return 0
	}
	if [[ ! -f "$(_omw_node_modulefile "$node_version")" ]]; then
		printf 'missing'
	elif _omw_node_cache_ready || _omw_node_cache_archive_ready; then
		printf 'cached'
	else
		printf 'available'
	fi
}

omw_node_pack() {
	local cache_dir node_version alias tmp_dir specs spec
	local -a versions aliases

	if ! _omw_node_has_any_packages; then
		omw_log "No Node packages are declared in packages.sh. Skipping npm cache packing." "INFO"
		return 0
	fi

	cache_dir=$(_omw_node_cache_dir)
	_omw_node_restore_cache_archive || true
	mkdir -p "$cache_dir"
	mapfile -t versions < <(_omw_node_unique_versions)

	for node_version in "${versions[@]}"; do
		_omw_node_ensure_node_for_pack "$node_version" || return 1
		_omw_node_load_version "$node_version" || return 1

		mapfile -t aliases < <(_omw_node_aliases_for_version "$node_version")
		specs=()
		for alias in "${aliases[@]}"; do
			spec=$(_omw_node_package_spec "$alias")
			specs+=("$spec")
		done
		mapfile -t aliases < <(_omw_node_cache_aliases_for_version "$node_version")
		for alias in "${aliases[@]}"; do
			spec=$(_omw_node_cache_package_spec "$alias")
			specs+=("$spec")
		done
		((${#specs[@]} > 0)) || continue

		tmp_dir="$BUILDS_PATH/.node-pack-$node_version"
		omw_safe_rm_rf "$tmp_dir"
		mkdir -p "$tmp_dir"
		omw_log "Packing npm cache for Node $node_version: ${specs[*]}" "INFO"
		pushd "$tmp_dir" >/dev/null
		if ! npm install "${specs[@]}" --cache "$cache_dir" --package-lock=false --audit=false --fund=false; then
			popd >/dev/null
			omw_safe_rm_rf "$tmp_dir"
			omw_log "Failed to populate npm cache for Node $node_version." "ERROR"
			return 1
		fi
		popd >/dev/null
		omw_safe_rm_rf "$tmp_dir"

		if ! npm cache verify --cache "$cache_dir"; then
			omw_log "npm cache verification failed for $cache_dir." "ERROR"
			return 1
		fi
	done

	if ! omw_node_verify; then
		return 1
	fi
	if ! _omw_node_write_cache_archive; then
		return 1
	fi
}

omw_node_verify() {
	local mode="${1:-restore}"
	local cache_dir alias node_version spec tmp_prefix verify_cache_dir old_cache_override

	if ! _omw_node_has_any_packages; then
		omw_log "No Node packages are declared in packages.sh. Skipping npm cache verification." "INFO"
		return 0
	fi

	cache_dir=$(_omw_node_cache_dir)
	if [[ "$mode" == "temp" ]] && ! _omw_node_cache_ready && _omw_node_cache_archive_ready; then
		verify_cache_dir="$BUILDS_PATH/.node-cache-verify/npm-cache"
		old_cache_override="${OMW_NODE_CACHE_DIR_OVERRIDE:-}"
		omw_safe_rm_rf "$BUILDS_PATH/.node-cache-verify"
		mkdir -p "$(dirname "$verify_cache_dir")"
		OMW_NODE_CACHE_DIR_OVERRIDE="$verify_cache_dir"
		if ! _omw_node_restore_cache_archive; then
			_omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
			return 1
		fi
		cache_dir=$(_omw_node_cache_dir)
	elif ! _omw_node_cache_ready; then
		_omw_node_restore_cache_archive || true
	fi

	if ! _omw_node_cache_ready; then
		omw_log "npm cache is missing or empty: $cache_dir; expected $(_omw_node_cache_archive_path) or an expanded cache directory." "ERROR"
		[[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]] && _omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
		return 1
	fi

	for alias in "${NODE_PACKAGE_LIST[@]}"; do
		_omw_node_require_alias "$alias" || return 1
		node_version="${NODE_PACKAGE_NODE_VERSIONS[$alias]}"
		spec=$(_omw_node_package_spec "$alias")

		if ! _omw_node_load_version "$node_version"; then
			[[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]] && _omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
			return 1
		fi
		if ! npm cache verify --cache "$cache_dir"; then
			omw_log "npm cache verification failed for $cache_dir." "ERROR"
			[[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]] && _omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
			return 1
		fi

		tmp_prefix="$BUILDS_PATH/.node-verify-$alias"
		omw_safe_rm_rf "$tmp_prefix"
		mkdir -p "$tmp_prefix"
		omw_log "Verifying offline install for $alias ($spec) with Node $node_version" "INFO"
		if ! NPM_CONFIG_PREFIX="$tmp_prefix" npm install -g "$spec" --offline --cache "$cache_dir" --audit=false --fund=false; then
			omw_safe_rm_rf "$tmp_prefix"
			omw_log "Offline npm install simulation failed for $alias." "ERROR"
			[[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]] && _omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
			return 1
		fi
		omw_safe_rm_rf "$tmp_prefix"
	done

	for alias in "${NODE_CACHE_PACKAGE_LIST[@]}"; do
		_omw_node_require_cache_alias "$alias" || return 1
		node_version="${NODE_CACHE_PACKAGE_NODE_VERSIONS[$alias]}"
		spec=$(_omw_node_cache_package_spec "$alias")

		if ! _omw_node_load_version "$node_version"; then
			[[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]] && _omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
			return 1
		fi
		if ! npm cache verify --cache "$cache_dir"; then
			omw_log "npm cache verification failed for $cache_dir." "ERROR"
			[[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]] && _omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
			return 1
		fi

		tmp_prefix="$BUILDS_PATH/.node-verify-cache-$alias"
		omw_safe_rm_rf "$tmp_prefix"
		mkdir -p "$tmp_prefix"
		omw_log "Verifying cache-only offline install for $alias ($spec) with Node $node_version" "INFO"
		pushd "$tmp_prefix" >/dev/null
		if ! npm install "$spec" --offline --cache "$cache_dir" --package-lock=false --audit=false --fund=false; then
			popd >/dev/null
			omw_safe_rm_rf "$tmp_prefix"
			omw_log "Offline npm install simulation failed for cache-only package $alias." "ERROR"
			[[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]] && _omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
			return 1
		fi
		popd >/dev/null
		omw_safe_rm_rf "$tmp_prefix"
	done

	if [[ "$mode" == "temp" && -n "${verify_cache_dir:-}" ]]; then
		_omw_node_restore_cache_override "$old_cache_override" "$BUILDS_PATH/.node-cache-verify"
	fi

	omw_log "Node package offline cache looks complete." "SUCCESS"
}

omw_node_restore_cache() {
	local cache_dir archive_path

	cache_dir=$(_omw_node_cache_dir)
	archive_path=$(_omw_node_cache_archive_path)
	if ! _omw_node_restore_cache_archive; then
		omw_log "npm cache archive is missing or unreadable: $archive_path" "ERROR"
		return 1
	fi
	omw_log "Expanded npm cache is ready: $cache_dir" "SUCCESS"
}

omw_node_install() {
	local alias="$1"
	local cache_dir node_version spec bin_name

	_omw_node_require_alias "$alias" || return 1
	cache_dir=$(_omw_node_cache_dir)
	if ! _omw_node_cache_ready; then
		_omw_node_restore_cache_archive || true
	fi
	if ! _omw_node_cache_ready; then
		omw_log "npm cache is missing or empty: $cache_dir. Run './omw node pack' on an online machine first and transfer $(_omw_node_cache_archive_path)." "ERROR"
		return 1
	fi

	node_version="${NODE_PACKAGE_NODE_VERSIONS[$alias]}"
	spec=$(_omw_node_package_spec "$alias")
	bin_name="${NODE_PACKAGE_BINS[$alias]:-}"
	_omw_node_load_version "$node_version" || return 1

	omw_log "Installing Node package offline: $spec" "INFO"
	if ! npm install -g "$spec" --offline --cache "$cache_dir" --audit=false --fund=false; then
		omw_log "Failed to install Node package: $alias" "ERROR"
		return 1
	fi
	if [[ -n "$bin_name" && ! -e "$(_omw_node_prefix "$node_version")/bin/$bin_name" ]]; then
		omw_log "Expected Node package bin was not found after install: $bin_name" "WARN"
	fi
	omw_log "Node package '$alias' installed successfully." "SUCCESS"
}

omw_node_install_all() {
	local alias

	if ! _omw_node_has_packages; then
		omw_log "No Node packages are declared in packages.sh. Skipping Node package install." "INFO"
		return 0
	fi
	for alias in "${NODE_PACKAGE_LIST[@]}"; do
		omw_node_install "$alias" || return 1
	done
}
