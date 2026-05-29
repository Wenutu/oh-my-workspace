# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_offline_*.

# Prefetch GCC prerequisites for all defined versions
_omw_offline_prefetch_gcc_prereqs() {
	local versions_str="${SOFTWARE_VERSIONS[gcc]}"
	[[ -z "$versions_str" ]] && return 0 # Skip if GCC is not defined

	omw_log "Prefetching GCC prerequisites for all defined versions..." "INFO"

	for version in $versions_str; do
		local url
		url=$(omw_get_software_url "gcc" "$version")
		local gcc_pkg
		gcc_pkg=$(omw_software_package_path "gcc" "$version")
		local tmp_dir="$BUILDS_PATH/.prefetch-gcc-$version"

		# Ensure GCC main package is downloaded
		if ! omw_download_package "$url" "$gcc_pkg"; then
			return 1
		fi

		# Extract just to parse the prerequisites script
		omw_safe_rm_rf "$tmp_dir"
		if ! omw_extract_package "$gcc_pkg" "$tmp_dir" 1; then
			omw_safe_rm_rf "$tmp_dir"
			return 1
		fi

		local prereq_pkgs
		mapfile -t prereq_pkgs < <(omw_gcc_prereq_packages "$tmp_dir")

		for pkg in "${prereq_pkgs[@]}"; do
			local dest="$PACKAGES_PATH/software/$pkg"
			if ! omw_download_package "${GCC_PREREQ_BASE_URL}${pkg}" "$dest"; then
				omw_safe_rm_rf "$tmp_dir"
				return 1
			fi
		done

		omw_safe_rm_rf "$tmp_dir"
	done
	omw_log "All GCC prerequisites prefetched." "SUCCESS"
}

_omw_offline_write_checksums() {
	local sums_file="$PACKAGES_PATH/SHA256SUMS"
	local tmp_sums
	tmp_sums=$(mktemp "$PACKAGES_PATH/.SHA256SUMS.XXXXXX")
	if command -v sha256sum &>/dev/null; then
		omw_log "Generating checksums..." "INFO"
		# Exclude existing checksum files and any legacy expanded npm cache; only npm-cache.tar.gz is bundled.
		if ! find "$PACKAGES_PATH" \
			-path "$PACKAGES_PATH/node/npm-cache" -prune -o \
			-type f ! -name "SHA256SUMS" ! -name ".SHA256SUMS.*" -print0 | sort -z | xargs -0 sha256sum >"$tmp_sums"; then
			rm -f "$tmp_sums"
			omw_log "Failed to generate checksums." "ERROR"
			return 1
		fi
		mv "$tmp_sums" "$sums_file"
		omw_log "Checksums written to $sums_file" "SUCCESS"
	else
		rm -f "$tmp_sums"
		omw_log "sha256sum not available. Skipping checksum generation." "WARN"
	fi
}

# Verify offline completeness for all defined software versions
omw_verify_offline() {
	omw_log "--- Verifying offline completeness ---" "INFO"
	local missing=()
	local corrupt=()

	verify_package() {
		local path="$1"
		if [[ ! -f "$path" ]]; then
			missing+=("$path")
			return 0
		fi
		if ! omw_archive_is_readable "$path"; then
			corrupt+=("$path")
		fi
	}

	# 1) Source and precompiled packages
	for sw in "${SOFTWARE_LIST[@]}"; do
		local versions_str="${SOFTWARE_VERSIONS[$sw]}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			local url
			url=$(omw_get_software_url "$sw" "$version")
			[[ -z "$url" ]] && continue
			local p
			p=$(omw_software_package_path "$sw" "$version")
			verify_package "$p"
		done
	done

	for app in "${APP_LIST[@]}"; do
		local url="${APP_URLS[$app]}"
		[[ -z "$url" ]] && continue
		local p
		p=$(omw_app_package_path "$url")
		verify_package "$p"

		local source_url="${APP_SOURCE_URLS[$app]:-}"
		[[ -z "$source_url" ]] && continue
		local source_p
		source_p=$(omw_app_package_path "$source_url")
		verify_package "$source_p"
	done

	# 2) GCC prerequisites (if GCC is defined in config) for all versions
	local gcc_versions_str="${SOFTWARE_VERSIONS[gcc]}"
	if [[ -n "$gcc_versions_str" ]]; then
		for version in $gcc_versions_str; do
			local gcc_pkg
			gcc_pkg=$(omw_software_package_path "gcc" "$version")

			if [[ -f "$gcc_pkg" ]]; then
				local tmp_dir="$BUILDS_PATH/.verify-gcc-prereqs-$version"
				omw_safe_rm_rf "$tmp_dir"
				if omw_extract_package "$gcc_pkg" "$tmp_dir" 1; then
					local prereq_pkgs
					mapfile -t prereq_pkgs < <(omw_gcc_prereq_packages "$tmp_dir")
					omw_safe_rm_rf "$tmp_dir"
					for pkg in "${prereq_pkgs[@]}"; do
						local p="$PACKAGES_PATH/software/$pkg"
						verify_package "$p"
					done
				else
					omw_safe_rm_rf "$tmp_dir"
					missing+=("$gcc_pkg (could not inspect GCC prerequisites)")
				fi
			else
				missing+=("$gcc_pkg")
			fi
		done
	fi

	# 3) Local RPM packages bundle
	verify_package "$PACKAGES_PATH/rpms.tar.gz"

	# 4) Config packages required for offline fallback-free shell setup
	local cfg cfg_package
	for cfg in "${CONFIG_TARGET_LIST[@]}"; do
		cfg_package=$(omw_config_package_path "$cfg")
		if [[ "$cfg" == "vim" && ! -f "$cfg_package" ]]; then
			omw_log "Optional Vim config package not found; Vim config will be skipped offline." "WARN"
			continue
		fi
		verify_package "$cfg_package"
	done

	if omw_node_has_any_packages; then
		verify_package "$PACKAGES_PATH/node/npm-cache.tar.gz"
	fi
	if ! omw_node_verify "temp"; then
		missing+=("$PACKAGES_PATH/node/npm-cache.tar.gz (Node package offline verification failed)")
	fi

	if ((${#missing[@]} > 0)); then
		omw_log "Missing offline assets:" "ERROR"
		for m in "${missing[@]}"; do echo "  - $m" >&2; done
		return 1
	fi
	if ((${#corrupt[@]} > 0)); then
		omw_log "Unreadable or corrupt offline archives:" "ERROR"
		for c in "${corrupt[@]}"; do echo "  - $c" >&2; done
		return 1
	fi
	omw_log "Offline assets look complete." "SUCCESS"
}

_omw_offline_package_config() {
	local target="$1"
	local required_path
	local package_path
	required_path=$(omw_config_required_path "$target")
	package_path=$(omw_config_package_path "$target")
	omw_ensure_valid_cwd

	if [[ -f "$package_path" ]]; then
		omw_log "Using existing config package for $target: $package_path" "INFO"
		return 0
	fi

	if ! omw_config_ready_for_package "$target"; then
		if [[ "$target" == "vim" ]]; then
			omw_log "Vim config source and package are missing; skipping optional Vim config package." "WARN"
			return 0
		fi
		omw_log "Config for $target is missing or empty; running configuration flow before packaging: $required_path" "WARN"
		omw_configure "$target" || return 1
		if ! omw_config_ready_for_package "$target"; then
			omw_log "Configuration flow did not prepare expected files: $required_path" "ERROR"
			return 1
		fi
	fi

	mkdir -p "$(dirname "$package_path")"
	if ! COPYFILE_DISABLE=1 tar -czf "$package_path" -C "$CONFIG_PATH" "$target"; then
		omw_log "Failed to create config package: $package_path" "ERROR"
		return 1
	fi
	omw_log "Config package created: $package_path" "SUCCESS"
}

_omw_offline_package_all_configs() {
	local cfg
	for cfg in "${CONFIG_TARGET_LIST[@]}"; do
		_omw_offline_package_config "$cfg" || return 1
	done
}

omw_create_offline_bundle() {
	omw_log "--- Creating OMW Offline Bundle ---" "INFO"
	omw_ensure_valid_cwd
	# 1. Download all required assets
	omw_log "Step 1: Downloading all software and app packages..."
	for app in "${SOFTWARE_LIST[@]}"; do
		local versions_str="${SOFTWARE_VERSIONS[$app]}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			local url
			url=$(omw_get_software_url "$app" "$version")
			if [[ -n "$url" ]] && ! omw_download_package "$url" "$(omw_software_package_path "$app" "$version")"; then
				return 1
			fi
		done
	done
	for app in "${APP_LIST[@]}"; do
		if ! omw_download_package "${APP_URLS[$app]}" "$(omw_app_package_path "${APP_URLS[$app]}")"; then
			return 1
		fi
		local source_url="${APP_SOURCE_URLS[$app]:-}"
		if [[ -n "$source_url" ]] && ! omw_download_package "$source_url" "$(omw_app_package_path "$source_url")"; then
			return 1
		fi
	done

	if ! _omw_offline_prefetch_gcc_prereqs; then
		return 1
	fi

	omw_log "Step 2: Preparing local dependencies (RPMs)..."
	if ! omw_build_local "false" "false" "${SOFTWARE_VERSIONS[local]}"; then # Run omw_build_local for its download side-effect
		return 1
	fi
	if [[ -d "$BUILDS_PATH/local-rpms" ]] && [[ ! -f "$PACKAGES_PATH/rpms.tar.gz" ]]; then
		if ! tar -czf "$PACKAGES_PATH/rpms.tar.gz" -C "$BUILDS_PATH/local-rpms" .; then
			omw_log "Failed to create local RPM package bundle." "ERROR"
			return 1
		fi
	fi

	omw_log "Step 3: Packaging existing configurations..."
	if ! _omw_offline_package_all_configs; then
		return 1
	fi
	omw_ensure_valid_cwd

	# 3.1 Generate checksums for all packages
	omw_log "Step 4: Preparing Node package npm cache..."
	if ! omw_node_pack; then
		return 1
	fi
	omw_ensure_valid_cwd

	if ! _omw_offline_write_checksums; then
		return 1
	fi

	# 3.2 Verify offline completeness before packing
	omw_log "Step 5: Verifying offline completeness..."
	if ! omw_verify_offline; then
		omw_log "Offline verification failed. Please fix missing items before packing." "ERROR"
		return 1
	fi

	# 4. Create the final archive
	local archive_name
	archive_name="omw-offline-bundle-$(date +%Y%m%d).tar.gz"
	omw_log "Step 6: Creating final archive: $archive_name"
	cd "$OMW_HOME"
	local tmp_archive="$HOME/.${archive_name}.tmp"
	local staging_dir="$BUILDS_PATH/.offline-bundle-$$"
	local bundle_root="$staging_dir/oh-my-workspace"
	local archive_items=()
	local item
	for item in omw env.sh packages.sh README.md compose.yaml Makefile packages lib; do
		[[ -e "$item" ]] && archive_items+=("$item")
	done
	omw_safe_rm_rf "$staging_dir"
	mkdir -p "$bundle_root"
	for item in "${archive_items[@]}"; do
		cp -a "$item" "$bundle_root/"
	done
	if [[ -d "$bundle_root/packages/node/npm-cache" ]]; then
		omw_log "Excluding expanded npm cache from offline bundle; keeping packages/node/npm-cache.tar.gz only." "INFO"
		omw_safe_rm_rf "$bundle_root/packages/node/npm-cache"
	fi
	if ! tar -czf "$tmp_archive" -C "$staging_dir" oh-my-workspace; then
		omw_safe_rm_rf "$staging_dir"
		rm -f "$tmp_archive"
		omw_log "Failed to create offline bundle archive." "ERROR"
		return 1
	fi
	if tar -tzf "$tmp_archive" | grep -Eq '^oh-my-workspace/packages/node/npm-cache(/|$)'; then
		omw_safe_rm_rf "$staging_dir"
		rm -f "$tmp_archive"
		omw_log "Offline bundle unexpectedly contains expanded npm cache directory." "ERROR"
		return 1
	fi
	omw_safe_rm_rf "$staging_dir"
	mv -f "$tmp_archive" "$HOME/$archive_name"
	omw_log "Offline bundle created successfully!" "SUCCESS"
	omw_log "To use, transfer '$HOME/$archive_name' to an offline machine, extract it, and run './omw --all'" "INFO"
}
