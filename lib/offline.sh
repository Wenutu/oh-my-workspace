# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_offline_*.

_omw_offline_gcc_prereq_packages() {
	local version="$1"
	local gcc_pkg="$2"
	local tmp_dir="$3"
	local prereq_script="$BUILDS_PATH/.gcc-download-prerequisites-$version"
	local -a prereq_pkgs=()

	omw_safe_rm_rf "$tmp_dir"
	rm -f "$prereq_script"
	if omw_download_package "$(omw_gcc_prereq_script_url "$version")" "$prereq_script"; then
		mapfile -t prereq_pkgs < <(omw_gcc_prereq_packages_from_script "$prereq_script")
		rm -f "$prereq_script"
		if ((${#prereq_pkgs[@]} == 4)); then
			printf '%s\n' "${prereq_pkgs[@]}"
			return 0
		fi
		omw_log "Downloaded GCC prerequisites script for $version could not be parsed; falling back to source extraction." "WARN"
	else
		rm -f "$prereq_script"
		omw_log "Could not download GCC prerequisites script for $version; falling back to source extraction." "WARN"
	fi

	omw_safe_rm_rf "$tmp_dir"
	if ! omw_extract_package "$gcc_pkg" "$tmp_dir" 1; then
		omw_safe_rm_rf "$tmp_dir"
		return 1
	fi

	mapfile -t prereq_pkgs < <(omw_gcc_prereq_packages_from_script "$tmp_dir/contrib/download_prerequisites")
	omw_safe_rm_rf "$tmp_dir"
	if ((${#prereq_pkgs[@]} != 4)); then
		omw_log "Could not determine GCC prerequisites for $version." "ERROR"
		return 1
	fi
	printf '%s\n' "${prereq_pkgs[@]}"
}

omw_prepare_gcc_prereq_packages() {
	local version="$1"
	local url
	url=$(omw_get_software_url "gcc" "$version")
	local gcc_pkg
	gcc_pkg=$(omw_software_package_path "gcc" "$version")
	local tmp_dir="$BUILDS_PATH/.prefetch-gcc-$version"

	# Ensure GCC main package is downloaded.
	if ! omw_download_package "$url" "$gcc_pkg"; then
		return 1
	fi

	local -a prereq_pkgs=()
	mapfile -t prereq_pkgs < <(_omw_offline_gcc_prereq_packages "$version" "$gcc_pkg" "$tmp_dir")
	if ((${#prereq_pkgs[@]} != 4)); then
		return 1
	fi

	for pkg in "${prereq_pkgs[@]}"; do
		local dest="$PACKAGES_PATH/$pkg"
		if ! omw_download_package "${GCC_PREREQ_BASE_URL}${pkg}" "$dest"; then
			return 1
		fi
	done
}

# Prefetch GCC prerequisites for all defined versions
_omw_offline_prefetch_gcc_prereqs() {
	local versions_str="${SOFTWARE_VERSIONS[gcc]}"
	[[ -z "$versions_str" ]] && return 0 # Skip if GCC is not defined

	omw_log "Prefetching GCC prerequisites for all defined versions..." "INFO"

	for version in $versions_str; do
		omw_prepare_gcc_prereq_packages "$version" || return 1
	done
	omw_log "All GCC prerequisites prefetched." "SUCCESS"
}

_omw_offline_verify_package() {
	local path="$1"
	if [[ ! -f "$path" ]]; then
		OMW_OFFLINE_MISSING+=("$path")
		return 0
	fi
	if ! omw_archive_is_readable "$path"; then
		OMW_OFFLINE_CORRUPT+=("$path")
	fi
}

_omw_offline_verify_software_packages() {
	local sw version versions_str url package_path

	for sw in "${SOFTWARE_LIST[@]}"; do
		versions_str="${SOFTWARE_VERSIONS[$sw]}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			url=$(omw_get_software_url "$sw" "$version")
			[[ -z "$url" ]] && continue
			package_path=$(omw_software_package_path "$sw" "$version")
			_omw_offline_verify_package "$package_path"
		done
	done
}

_omw_offline_verify_app_packages() {
	local app url package_path source_url source_package_path

	for app in "${APP_LIST[@]}"; do
		url=$(omw_get_app_url "$app") || continue
		[[ -z "$url" ]] && continue
		package_path=$(omw_app_package_path "$url")
		_omw_offline_verify_package "$package_path"

		source_url=$(omw_get_app_source_url "$app" 2>/dev/null || true)
		[[ -z "$source_url" ]] && continue
		source_package_path=$(omw_app_package_path "$source_url")
		_omw_offline_verify_package "$source_package_path"
	done
}

_omw_offline_verify_gcc_prereqs() {
	local gcc_versions_str="${SOFTWARE_VERSIONS[gcc]}"
	local version gcc_pkg tmp_dir pkg package_path
	local -a prereq_pkgs=()

	[[ -z "$gcc_versions_str" ]] && return 0
	for version in $gcc_versions_str; do
		gcc_pkg=$(omw_software_package_path "gcc" "$version")
		if [[ ! -f "$gcc_pkg" ]]; then
			OMW_OFFLINE_MISSING+=("$gcc_pkg")
			continue
		fi

		tmp_dir="$BUILDS_PATH/.verify-gcc-prereqs-$version"
		omw_safe_rm_rf "$tmp_dir"
		if omw_extract_package "$gcc_pkg" "$tmp_dir" 1; then
			mapfile -t prereq_pkgs < <(omw_gcc_prereq_packages_from_script "$tmp_dir/contrib/download_prerequisites")
			omw_safe_rm_rf "$tmp_dir"
			for pkg in "${prereq_pkgs[@]}"; do
				package_path="$PACKAGES_PATH/$pkg"
				_omw_offline_verify_package "$package_path"
			done
		else
			omw_safe_rm_rf "$tmp_dir"
			OMW_OFFLINE_MISSING+=("$gcc_pkg (could not inspect GCC prerequisites)")
		fi
	done
}

_omw_offline_download_software_packages() {
	local app versions_str version url package_path

	for app in "${SOFTWARE_LIST[@]}"; do
		versions_str="${SOFTWARE_VERSIONS[$app]}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			url=$(omw_get_software_url "$app" "$version")
			[[ -z "$url" ]] && continue
			package_path=$(omw_software_package_path "$app" "$version")
			omw_download_package "$url" "$package_path" || return 1
		done
	done
}

_omw_offline_download_app_packages() {
	local app app_url source_url

	for app in "${APP_LIST[@]}"; do
		app_url=$(omw_get_app_url "$app") || return 1
		omw_download_package "$app_url" "$(omw_app_package_path "$app_url")" || return 1

		source_url=$(omw_get_app_source_url "$app" 2>/dev/null || true)
		[[ -z "$source_url" ]] && continue
		omw_download_package "$source_url" "$(omw_app_package_path "$source_url")" || return 1
	done
}

_omw_offline_planned_url_assets() {
	local sw version versions_str url app app_url source_url

	for sw in "${SOFTWARE_LIST[@]}"; do
		versions_str="${SOFTWARE_VERSIONS[$sw]}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			url=$(omw_get_software_url "$sw" "$version")
			[[ -z "$url" ]] && continue
			printf 'software:%s@%s\t%s\t%s\n' "$sw" "$version" "$url" "$(omw_software_package_path "$sw" "$version")"
		done
	done
	for app in "${APP_LIST[@]}"; do
		app_url=$(omw_get_app_url "$app") || continue
		[[ -n "$app_url" ]] && printf 'app:%s\t%s\t%s\n' "$app" "$app_url" "$(omw_app_package_path "$app_url")"
		source_url=$(omw_get_app_source_url "$app" 2>/dev/null || true)
		[[ -n "$source_url" ]] && printf 'app-source:%s\t%s\t%s\n' "$app" "$source_url" "$(omw_app_package_path "$source_url")"
	done
}

_omw_offline_check_flat_package_name_conflicts() {
	local label source dest basename
	local -A basename_sources=()

	while IFS=$'\t' read -r label source dest; do
		[[ -n "$source" && -n "$dest" ]] || continue
		basename=$(basename "$dest")
		if [[ -n "${basename_sources[$basename]:-}" && "${basename_sources[$basename]}" != "$source" ]]; then
			omw_log "Flat packages basename conflict: $basename" "ERROR"
			omw_log "First source: ${basename_sources[$basename]}" "ERROR"
			omw_log "Other source: $source" "ERROR"
			return 1
		fi
		basename_sources["$basename"]="$source"
	done < <(_omw_offline_planned_url_assets)
}

_omw_offline_prepare_required_assets() {
	local force="$1"

	omw_log "Step 0: Checking flat package basename conflicts..."
	_omw_offline_check_flat_package_name_conflicts || return 1

	omw_log "Step 1: Downloading all software and app packages..."
	_omw_offline_download_software_packages || return 1
	_omw_offline_download_app_packages || return 1
	_omw_offline_prefetch_gcc_prereqs || return 1

	omw_log "Step 2: Preparing local dependencies (RPMs)..."
	omw_prepare_local_rpm_bundle || return 1

	omw_log "Step 3: Preparing and packaging configurations..."
	omw_prepare_all_config_packages "$force" || return 1
	omw_ensure_valid_cwd

	omw_log "Step 4: Preparing Node package npm cache..."
	omw_node_pack || return 1
	omw_ensure_valid_cwd

	omw_log "Step 5: Verifying offline completeness..."
	omw_verify_offline || {
		omw_log "Offline verification failed. Please fix missing items before packing." "ERROR"
		return 1
	}
}

_omw_offline_archive_items() {
	local item

	for item in VERSION omw env.sh packages.sh README.md README.zh-CN.md LICENSE docs compose.yaml packages lib; do
		[[ -e "$OMW_HOME/$item" ]] && printf '%s\n' "$item"
	done
}

_omw_offline_prepare_bundle_root() {
	local bundle_root="$1"
	local item old_lib_dir

	mkdir -p "$bundle_root" || return 1
	while IFS= read -r item; do
		cp -a "$OMW_HOME/$item" "$bundle_root/" || return 1
	done < <(_omw_offline_archive_items)
	mkdir -p "$bundle_root/lib/$OMW_VERSION" || return 1
	mv -f "$bundle_root/lib/"*.sh "$bundle_root/lib/$OMW_VERSION/" || return 1
	for old_lib_dir in "$bundle_root/lib"/*; do
		[[ -d "$old_lib_dir" && ! -L "$old_lib_dir" && "$(basename "$old_lib_dir")" != "$OMW_VERSION" ]] || continue
		omw_safe_rm_rf "$old_lib_dir" || return 1
	done
	omw_log "Writing bundle metadata and manifest." "INFO"
	omw_write_bundle_metadata "$bundle_root" "$bundle_root/.omw-bundle-meta" || return 1
	omw_write_bundle_manifest "$bundle_root" "$bundle_root/.omw-bundle-manifest" || return 1
}

_omw_offline_write_bundle_archive() {
	local archive_path="$1"
	local staging_dir="$2"

	tar -czf "$archive_path" -C "$staging_dir" oh-my-workspace || return 1
	if tar -tzf "$archive_path" | grep -Eq '^oh-my-workspace/packages/.*/'; then
		omw_log "Offline bundle unexpectedly contains nested packages directories." "ERROR"
		return 1
	fi
}

_omw_offline_verify_config_packages() {
	local cfg cfg_package

	for cfg in "${CONFIG_TARGET_LIST[@]}"; do
		cfg_package=$(omw_config_package_path "$cfg")
		if [[ ! -f "$cfg_package" ]]; then
			omw_log "Optional $cfg config package not found; $cfg config will be skipped offline." "WARN"
			continue
		fi
		_omw_offline_verify_package "$cfg_package"
	done
}

_omw_offline_verify_node_cache() {
	if omw_node_has_any_packages; then
		_omw_offline_verify_package "$(_omw_node_cache_archive_path)"
	fi
}

_omw_offline_report_verification_failures() {
	local item

	if ((${#OMW_OFFLINE_MISSING[@]} > 0)); then
		omw_log "Missing offline assets:" "ERROR"
		for item in "${OMW_OFFLINE_MISSING[@]}"; do echo "  - $item" >&2; done
		return 1
	fi
	if ((${#OMW_OFFLINE_CORRUPT[@]} > 0)); then
		omw_log "Unreadable or corrupt offline archives:" "ERROR"
		for item in "${OMW_OFFLINE_CORRUPT[@]}"; do echo "  - $item" >&2; done
		return 1
	fi
}

# Verify offline completeness for all defined software versions
omw_verify_offline() {
	omw_log "--- Verifying offline completeness ---" "INFO"
	OMW_OFFLINE_MISSING=()
	OMW_OFFLINE_CORRUPT=()

	_omw_offline_verify_software_packages
	_omw_offline_verify_app_packages
	_omw_offline_verify_gcc_prereqs
	_omw_offline_verify_package "$(omw_local_rpm_bundle_path "${SOFTWARE_VERSIONS[local]}")"
	_omw_offline_verify_config_packages
	_omw_offline_verify_node_cache
	_omw_offline_report_verification_failures || return 1
	omw_log "Offline assets look complete." "SUCCESS"
}

omw_prepare_config_package() {
	local target="$1"
	local force="${2:-false}"
	local source_target package_path
	local tmp_package
	local -a excludes=()
	source_target=$(omw_config_source_target_dir "$target")
	package_path=$(omw_config_package_path "$target")
	tmp_package="${package_path}.tmp-$$"
	omw_ensure_valid_cwd

	omw_log "Preparing $target config dependencies for packaging..." "INFO"
	if ! omw_prepare_config_for_package "$target" "$force"; then
		return 1
	fi
	if [[ ! -d "$source_target" ]]; then
		omw_log "Config source target not found: $source_target" "ERROR"
		return 1
	fi

	mkdir -p "$(dirname "$package_path")" || return 1
	rm -f "$tmp_package"
	if ! COPYFILE_DISABLE=1 tar "${excludes[@]}" -czf "$tmp_package" -C "$CONFIG_PATH" "$target"; then
		rm -f "$tmp_package"
		omw_log "Failed to create config package: $package_path" "ERROR"
		return 1
	fi
	mv -f "$tmp_package" "$package_path" || return 1
	omw_log "Config package created: $package_path" "SUCCESS"
}

omw_prepare_all_config_packages() {
	local force="${1:-false}"
	local cfg
	for cfg in "${CONFIG_TARGET_LIST[@]}"; do
		omw_prepare_config_package "$cfg" "$force" || return 1
	done
}

omw_create_offline_bundle() {
	local force="${1:-false}"
	omw_log "--- Creating OMW Offline Bundle ---" "INFO"
	omw_ensure_valid_cwd
	_omw_offline_prepare_required_assets "$force" || return 1

	local archive_name
	archive_name="omw-offline-bundle-v${OMW_VERSION}.tar.gz"
	omw_log "Step 6: Creating final archive: $archive_name"
	cd "$OMW_HOME"
	local archive_path="$OMW_HOME/$archive_name"
	local tmp_archive="$OMW_HOME/.${archive_name}.tmp"
	local staging_dir="$BUILDS_PATH/.offline-bundle-$$"
	local bundle_root="$staging_dir/oh-my-workspace"
	omw_safe_rm_rf "$staging_dir" || return 1
	rm -f "$tmp_archive" "$archive_path"
	if ! _omw_offline_prepare_bundle_root "$bundle_root"; then
		omw_safe_rm_rf "$staging_dir"
		rm -f "$tmp_archive"
		omw_log "Failed to prepare offline bundle root." "ERROR"
		return 1
	fi
	if ! _omw_offline_write_bundle_archive "$tmp_archive" "$staging_dir"; then
		omw_safe_rm_rf "$staging_dir"
		rm -f "$tmp_archive"
		omw_log "Failed to create offline bundle archive." "ERROR"
		return 1
	fi
	omw_safe_rm_rf "$staging_dir"
	mv -f "$tmp_archive" "$archive_path" || return 1
	omw_log "Offline bundle created successfully!" "SUCCESS"
	omw_log "To use, transfer '$archive_path' to an offline machine, extract it, and run './omw all'" "INFO"
}
