# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_offline_*.
_omw_offline_get_gcc_prereq_pkgs() {
	local extracted_gcc_path="$1"
	local prereq_script="$extracted_gcc_path/contrib/download_prerequisites"

	if [[ ! -f "$prereq_script" ]]; then
		omw_log "download_prerequisites script not found in $extracted_gcc_path" "ERROR"
		return 1
	fi
	# Use an array to store results, which handles potential future changes better
	local prereqs=(
		"$(grep -oP 'gmp-.*tar\.bz2' "$prereq_script" | head -1 || true)"
		"$(grep -oP 'mpfr-.*tar\.bz2' "$prereq_script" | head -1 || true)"
		"$(grep -oP 'mpc-.*tar\.gz' "$prereq_script" | head -1 || true)"
		"$(grep -oP 'isl-.*tar\.bz2' "$prereq_script" | head -1 || true)"
	)
	# Print non-empty package names
	for pkg in "${prereqs[@]}"; do
		[[ -n "$pkg" ]] && echo "$pkg"
	done
}

# Prefetch GCC prerequisites for all defined versions
_omw_offline_prefetch_gcc_prereqs() {
	local versions_str="${SOFTWARE_VERSIONS[gcc]}"
	[[ -z "$versions_str" ]] && return 0 # Skip if GCC is not defined

	omw_log "Prefetching GCC prerequisites for all defined versions..." "INFO"

	for version in $versions_str; do
		local url
		url=$(omw_get_software_url "gcc" "$version")
		local gcc_pkg
		gcc_pkg="$PACKAGES_PATH/software/$(basename "$url")"
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
		mapfile -t prereq_pkgs < <(_omw_offline_get_gcc_prereq_pkgs "$tmp_dir")

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
			p="$PACKAGES_PATH/software/$(basename "$url")"
			verify_package "$p"
		done
	done

	for app in "${APP_LIST[@]}"; do
		local url="${APP_URLS[$app]}"
		[[ -z "$url" ]] && continue
		local p
		p="$PACKAGES_PATH/apps/$(basename "$url")"
		verify_package "$p"

		local source_url="${APP_SOURCE_URLS[$app]:-}"
		[[ -z "$source_url" ]] && continue
		local source_p
		source_p="$PACKAGES_PATH/apps/$(basename "$source_url")"
		verify_package "$source_p"
	done

	# 2) GCC prerequisites (if GCC is defined in config) for all versions
	local gcc_versions_str="${SOFTWARE_VERSIONS[gcc]}"
	if [[ -n "$gcc_versions_str" ]]; then
		for version in $gcc_versions_str; do
			local gcc_url
			gcc_url=$(omw_get_software_url "gcc" "$version")
			local gcc_pkg
			gcc_pkg="$PACKAGES_PATH/software/$(basename "$gcc_url")"

			if [[ -f "$gcc_pkg" ]]; then
				local tmp_dir="$BUILDS_PATH/.verify-gcc-prereqs-$version"
				omw_safe_rm_rf "$tmp_dir"
				if omw_extract_package "$gcc_pkg" "$tmp_dir" 1; then
					local prereq_pkgs
					mapfile -t prereq_pkgs < <(_omw_offline_get_gcc_prereq_pkgs "$tmp_dir")
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
	for cfg in tmux zsh; do
		verify_package "$PACKAGES_PATH/config/$cfg.tar.gz"
	done
	if [[ ! -f "$PACKAGES_PATH/config/vim.tar.gz" ]]; then
		omw_log "Optional Vim config package not found; Vim config will be skipped offline." "WARN"
	else
		verify_package "$PACKAGES_PATH/config/vim.tar.gz"
	fi

	if _omw_node_has_any_packages; then
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

_omw_offline_config_package_path() {
	local target="$1"
	printf '%s/config/%s.tar.gz' "$PACKAGES_PATH" "$target"
}

_omw_offline_config_required_path() {
	local target="$1"

	case "$target" in
	tmux)
		printf '%s/tmux/.tmux' "$CONFIG_PATH"
		;;
	vim)
		printf '%s/vim/vim9' "$CONFIG_PATH"
		;;
	zsh)
		printf '%s/zsh/.oh-my-zsh' "$CONFIG_PATH"
		;;
	*)
		printf '%s/%s' "$CONFIG_PATH" "$target"
		;;
	esac
}

omw_config_ready_for_package() {
	local target="$1"
	local required_path first_entry
	required_path=$(_omw_offline_config_required_path "$target")

	[[ -d "$required_path" ]] || return 1
	first_entry=$(find "$required_path" -mindepth 1 -print -quit)
	[[ -n "$first_entry" ]]
}

_omw_offline_package_config() {
	local target="$1"
	local required_path
	local package_path
	required_path=$(_omw_offline_config_required_path "$target")
	package_path=$(_omw_offline_config_package_path "$target")
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
	for cfg in tmux vim zsh; do
		_omw_offline_package_config "$cfg" || return 1
	done
}

omw_restore_config_package() {
	local target="$1"
	local required_path="$2"
	local force="${3:-false}"
	local package_path target_dir backup_dir first_entry has_conflict=false
	package_path=$(_omw_offline_config_package_path "$target")
	target_dir="$CONFIG_PATH/$target"

	if [[ ! -f "$package_path" ]]; then
		return 0
	fi

	omw_log "Restoring $target config from $package_path" "INFO"
	mkdir -p "$CONFIG_PATH"
	if [[ -e "$target_dir" || -L "$target_dir" ]]; then
		if [[ -L "$target_dir" || ! -d "$target_dir" ]]; then
			has_conflict=true
		else
			first_entry=$(find "$target_dir" -mindepth 1 -print -quit)
			[[ -n "$first_entry" ]] && has_conflict=true
		fi
		if [[ "$has_conflict" == "true" && "$force" != "true" ]]; then
			omw_log "$target config directory already exists: $target_dir" "WARN"
			omw_log "Skipping package restore. Delete the existing config directory or rerun with --force to overwrite it." "WARN"
			return 0
		fi
		if [[ "$has_conflict" == "true" ]]; then
			backup_dir=$(_omw_common_backup_path_once "$target_dir" "$target")
			omw_safe_rm_rf "$target_dir"
			[[ -n "$backup_dir" ]] && omw_log "Existing $target config was replaced by package; backup: $backup_dir" "INFO"
		fi
	fi
	if ! tar -xzf "$package_path" -C "$CONFIG_PATH"; then
		omw_log "Failed to restore $target config package." "ERROR"
		if [[ -n "$backup_dir" && -e "$backup_dir" ]]; then
			omw_safe_rm_rf "$target_dir"
			cp -a "$backup_dir" "$target_dir"
			omw_log "Restored previous $target config from $backup_dir" "WARN"
		fi
		return 1
	fi
	if [[ ! -d "$required_path" ]]; then
		omw_log "Config package did not restore expected directory: $required_path" "ERROR"
		if [[ -n "$backup_dir" && -e "$backup_dir" ]]; then
			omw_safe_rm_rf "$target_dir"
			cp -a "$backup_dir" "$target_dir"
			omw_log "Restored previous $target config from $backup_dir" "WARN"
		fi
		return 1
	fi
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
			if [[ -n "$url" ]] && ! omw_download_package "$url" "$PACKAGES_PATH/software/$(basename "$url")"; then
				return 1
			fi
		done
	done
	for app in "${APP_LIST[@]}"; do
		if ! omw_download_package "${APP_URLS[$app]}" "$PACKAGES_PATH/apps/$(basename "${APP_URLS[$app]}")"; then
			return 1
		fi
		local source_url="${APP_SOURCE_URLS[$app]:-}"
		if [[ -n "$source_url" ]] && ! omw_download_package "$source_url" "$PACKAGES_PATH/apps/$(basename "$source_url")"; then
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
