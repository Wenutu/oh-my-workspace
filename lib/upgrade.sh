# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_upgrade_*.

_omw_upgrade_managed_items() {
	printf '%s\t%s\n' VERSION replace-exact
	printf '%s\t%s\n' omw replace-exact
	printf '%s\t%s\n' env.sh replace-exact
	printf '%s\t%s\n' packages.sh replace-exact
	printf '%s\t%s\n' README.md replace-exact
	printf '%s\t%s\n' README.zh-CN.md replace-exact
	printf '%s\t%s\n' docs replace-exact
	printf '%s\t%s\n' compose.yaml replace-exact
	printf '%s\t%s\n' lib versioned-lib
	printf '%s\t%s\n' config preserve-local
}

_omw_upgrade_print_action() {
	local action="$1"
	local path="$2"
	printf '%s: %s\n' "$action" "$path"
}

_omw_upgrade_short_md5() {
	local digest="$1"
	[[ "$digest" == "missing" ]] && printf 'missing' || printf '%s' "${digest:0:12}"
}

_omw_upgrade_color_enabled() {
	[[ -t 1 && -z "${NO_COLOR:-}" && "${OMW_NO_COLOR:-false}" != "true" ]]
}

_omw_upgrade_status_color() {
	local status="$1"

	case "$status" in
	keep | keep-local | preserve-local) printf '32' ;;
	add) printf '36' ;;
	replace) printf '33' ;;
	delete) printf '31' ;;
	skip | skip-missing) printf '90' ;;
	*) printf '0' ;;
	esac
}

_omw_upgrade_print_package_status() {
	local rel="$1"
	local status="$2"

	_omw_upgrade_print_path_status "$status" "$rel"
}

_omw_upgrade_print_path_status() {
	local status="$1"
	local rel="$2"
	local note="${3:-}"
	local color

	if _omw_upgrade_color_enabled; then
		color=$(_omw_upgrade_status_color "$status")
		printf '\033[%sm%-72s %-14s %s\033[0m\n' "$color" "$rel" "$status" "$note"
	else
		printf '%-72s %-14s %s\n' "$rel" "$status" "$note"
	fi
}

_omw_upgrade_meta_value() {
	local key="$1"
	local line

	[[ -f "${OMW_UPGRADE_META_FILE:-}" ]] || return 1
	line=$(grep -E "^${key}=" "$OMW_UPGRADE_META_FILE" | head -n 1 || true)
	[[ -n "$line" ]] || return 1
	printf '%s\n' "${line#*=}"
}

_omw_upgrade_manifest_record() {
	local rel="$1"

	[[ -f "${OMW_UPGRADE_MANIFEST_FILE:-}" ]] || return 1
	awk -F '\t' -v rel="$rel" '$1 ~ /^[FDL]$/ && $4 == rel { print; found=1; exit } END { exit found ? 0 : 1 }' "$OMW_UPGRADE_MANIFEST_FILE"
}

_omw_upgrade_manifest_hash() {
	local rel="$1"
	local record

	record=$(_omw_upgrade_manifest_record "$rel") || return 1
	[[ "${record%%$'\t'*}" == "F" ]] || return 1
	printf '%s\n' "$(printf '%s\n' "$record" | awk -F '\t' '{print $2}')"
}

_omw_upgrade_manifest_available() {
	[[ -f "${OMW_UPGRADE_MANIFEST_FILE:-}" ]]
}

_omw_upgrade_manifest_has_path() {
	local rel="$1"
	_omw_upgrade_manifest_record "$rel" >/dev/null 2>&1
}

_omw_upgrade_require_bundle_metadata() {
	local format manifest_path algorithm

	[[ -f "${OMW_UPGRADE_META_FILE:-}" ]] || {
		omw_log "Upgrade bundle is missing .omw-bundle-meta; regenerate it with './omw offline pack'." "ERROR"
		return 1
	}
	format=$(_omw_upgrade_meta_value bundle_format) || format=""
	[[ "$format" == "2" ]] || {
		omw_log "Unsupported upgrade bundle format: ${format:-missing}. Regenerate it with './omw offline pack'." "ERROR"
		return 1
	}
	manifest_path=$(_omw_upgrade_meta_value manifest_path) || manifest_path=""
	algorithm=$(_omw_upgrade_meta_value manifest_algorithm) || algorithm=""
	[[ "$manifest_path" == ".omw-bundle-manifest" && "$algorithm" == "md5" && -f "${OMW_UPGRADE_MANIFEST_FILE:-}" ]] || {
		omw_log "Upgrade bundle metadata does not point to a valid md5 manifest." "ERROR"
		return 1
	}
}

_omw_upgrade_source_rel() {
	local source="$1"
	local root="${OMW_UPGRADE_BUNDLE_ROOT:-}"
	[[ -n "$root" && "$source" == "$root/"* ]] || return 1
	printf '%s\n' "${source#"$root/"}"
}

_omw_upgrade_target_md5() {
	local path="$1"
	if [[ -f "$path" ]]; then
		omw_file_md5 "$path"
	else
		printf 'missing\n'
	fi
}

_omw_upgrade_bundle_version() {
	local version=""

	version=$(_omw_upgrade_meta_value omw_version 2>/dev/null || true)
	if [[ -z "$version" && -n "${OMW_UPGRADE_BUNDLE_ROOT:-}" && -f "$OMW_UPGRADE_BUNDLE_ROOT/VERSION" ]]; then
		version=$(tr -d '[:space:]' <"$OMW_UPGRADE_BUNDLE_ROOT/VERSION")
	fi
	printf '%s\n' "$version"
}

_omw_upgrade_config_package_rel() {
	local target="$1"
	local version="$2"
	printf 'packages/config-%s-%s.tar.gz' "$target" "$version"
}

_omw_upgrade_config_packages_needs_update() {
	local source_config="$1"
	local dest_config="$2"
	local version target rel source_pkg found=0

	[[ -e "$source_config" || -L "$source_config" ]] || return 1
	version=$(_omw_upgrade_bundle_version)
	[[ -n "$version" ]] || return 0
	for target in "${CONFIG_TARGET_LIST[@]}"; do
		rel=$(_omw_upgrade_config_package_rel "$target" "$version")
		source_pkg="$OMW_UPGRADE_BUNDLE_ROOT/$rel"
		[[ -f "$source_pkg" ]] || continue
		found=1
	done
	((found == 1)) && return 0
	if ((found == 0)); then
		[[ ! -e "$dest_config" && ! -L "$dest_config" ]]
		return
	fi
	return 1
}

_omw_upgrade_config_package_stats() {
	local version target rel dest_pkg total=0 changed=0 missing=0

	version=$(_omw_upgrade_bundle_version)
	if [[ -z "$version" ]]; then
		printf 'bundle version missing; config will update\n'
		return 0
	fi
	for target in "${CONFIG_TARGET_LIST[@]}"; do
		rel=$(_omw_upgrade_config_package_rel "$target" "$version")
		_omw_upgrade_manifest_has_path "$rel" || continue
		((++total))
		dest_pkg="$PACKAGES_PATH/$(basename "$rel")"
		if [[ ! -e "$dest_pkg" && ! -L "$dest_pkg" ]]; then
			((++missing))
			((++changed))
			continue
		fi
		_omw_upgrade_manifest_entry_matches "$rel" "$dest_pkg" || ((++changed))
	done
	printf 'config-packages=%s changed=%s missing=%s policy=preserve-local\n' "$total" "$changed" "$missing"
}

_omw_upgrade_config_local_files() {
	local dest_config="$1"

	[[ -d "$dest_config/local" ]] || return 0
	(
		cd "$dest_config/local" || exit 1
		find . \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r rel; do
			printf 'config/local/%s\n' "${rel#./}"
		done
	)
}

_omw_upgrade_target_path_for_rel() {
	local rel_root="$1"
	local dest_root="$2"
	local manifest_rel="$3"

	if [[ "$manifest_rel" == "$rel_root" ]]; then
		printf '%s\n' "$dest_root"
	else
		printf '%s/%s\n' "$dest_root" "${manifest_rel#"$rel_root/"}"
	fi
}

_omw_upgrade_manifest_entry_matches() {
	local rel="$1"
	local target="$2"
	local record type expected value mode target_mode

	record=$(_omw_upgrade_manifest_record "$rel") || return 1
	IFS=$'\t' read -r type expected mode _ <<<"$record"
	case "$type" in
	F)
		[[ -f "$target" ]] || return 1
		value=$(omw_file_md5 "$target") || return 1
		target_mode=$(_omw_fs_file_mode "$target") || return 1
		[[ "$value" == "$expected" && "$target_mode" == "$mode" ]]
		;;
	D)
		[[ -d "$target" && ! -L "$target" ]] || return 1
		target_mode=$(_omw_fs_file_mode "$target") || return 1
		[[ "$target_mode" == "$mode" ]]
		;;
	L)
		[[ -L "$target" ]] || return 1
		value=$(readlink "$target") || return 1
		[[ "$value" == "$mode" ]]
		;;
	*) return 1 ;;
	esac
}

_omw_upgrade_tree_needs_update() {
	local rel="$1"
	local dest="$2"
	local policy="${3:-merge-overlay}"
	local manifest_rel target_path target_rel found=0

	_omw_upgrade_manifest_available || return 0
	while IFS= read -r manifest_rel; do
		found=1
		target_path=$(_omw_upgrade_target_path_for_rel "$rel" "$dest" "$manifest_rel") || return 1
		_omw_upgrade_manifest_entry_matches "$manifest_rel" "$target_path" || return 0
	done < <(_omw_upgrade_manifest_paths_under "$rel")
	if ((found == 0)); then
		[[ ! -e "$dest" && ! -L "$dest" ]]
		return
	fi
	if [[ "$policy" == "replace-exact" && -d "$dest" && ! -L "$dest" ]]; then
		while IFS= read -r target_path; do
			target_rel="${target_path#"$dest"/}"
			_omw_upgrade_manifest_has_path "$rel/$target_rel" || return 0
		done < <(find "$dest" -mindepth 1 -print | LC_ALL=C sort)
	fi
	return 1
}

_omw_upgrade_manifest_paths_under() {
	local rel="$1"
	local prefix="$rel/"

	[[ -f "${OMW_UPGRADE_MANIFEST_FILE:-}" ]] || return 1
	awk -F '\t' -v rel="$rel" -v prefix="$prefix" '$1 ~ /^[FDL]$/ {
		path=$4
		if (path == rel || index(path, prefix) == 1) print path
	}' "$OMW_UPGRADE_MANIFEST_FILE"
}

_omw_upgrade_manifest_file_paths_under() {
	local rel="$1"
	local prefix="$rel/"

	[[ -f "${OMW_UPGRADE_MANIFEST_FILE:-}" ]] || return 1
	awk -F '\t' -v rel="$rel" -v prefix="$prefix" '$1 ~ /^[FL]$/ {
		path=$4
		if (path == rel || index(path, prefix) == 1) print path
	}' "$OMW_UPGRADE_MANIFEST_FILE"
}

_omw_upgrade_tree_stats() {
	local rel="$1"
	local dest="$2"
	local policy="${3:-merge-overlay}"
	local manifest_rel target_path target_rel total=0 changed=0 missing=0 extra=0

	_omw_upgrade_manifest_available || {
		printf 'manifest missing; update will replace path\n'
		return 0
	}
	while IFS= read -r manifest_rel; do
		((++total))
		target_path=$(_omw_upgrade_target_path_for_rel "$rel" "$dest" "$manifest_rel") || return 1
		if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
			((++missing))
			((++changed))
			continue
		fi
		_omw_upgrade_manifest_entry_matches "$manifest_rel" "$target_path" || ((++changed))
	done < <(_omw_upgrade_manifest_paths_under "$rel")
	if [[ "$policy" == "replace-exact" && -d "$dest" && ! -L "$dest" ]]; then
		while IFS= read -r target_path; do
			target_rel="${target_path#"$dest"/}"
			_omw_upgrade_manifest_has_path "$rel/$target_rel" || ((++extra))
		done < <(find "$dest" -mindepth 1 -print | LC_ALL=C sort)
	fi
	printf 'entries=%s changed=%s missing=%s extra=%s policy=%s\n' "$total" "$changed" "$missing" "$extra" "$policy"
}

_omw_upgrade_item_needs_update() {
	local source="$1"
	local dest="$2"
	local rel="$3"
	local policy="${4:-merge-overlay}"

	[[ -e "$source" || -L "$source" ]] || return 1
	if [[ "$policy" == "preserve-local" && "$rel" == "config" ]]; then
		_omw_upgrade_config_packages_needs_update "$source" "$dest"
		return
	fi
	[[ -e "$dest" || -L "$dest" ]] || return 0
	if omw_paths_same "$source" "$dest"; then
		return 1
	fi
	if [[ -f "$source" ]]; then
		! _omw_upgrade_manifest_entry_matches "$rel" "$dest"
	elif [[ -d "$source" && ! -L "$source" ]]; then
		_omw_upgrade_tree_needs_update "$rel" "$dest" "$policy"
	else
		_omw_upgrade_manifest_entry_matches "$rel" "$dest" >/dev/null 2>&1
		[[ $? -ne 0 ]]
	fi
}

_omw_upgrade_print_detail() {
	local source="$1"
	local dest="$2"
	local decision="$3"
	local rel="${4:-}"
	local policy="${5:-merge-overlay}"
	local source_digest target_digest stats

	printf '  source: %s\n' "$source"
	printf '  target: %s\n' "$dest"
	if [[ "$policy" == "preserve-local" && "$rel" == "config" ]]; then
		stats=$(_omw_upgrade_config_package_stats) || return 1
		printf '  manifest: %s\n' "${OMW_UPGRADE_MANIFEST_FILE:-missing}"
		printf '  manifest summary: %s\n' "$stats"
	elif [[ -n "$rel" && -d "$source" && ! -L "$source" ]]; then
		stats=$(_omw_upgrade_tree_stats "$rel" "$dest" "$policy") || return 1
		printf '  manifest: %s\n' "${OMW_UPGRADE_MANIFEST_FILE:-missing}"
		printf '  manifest summary: %s\n' "$stats"
	elif [[ -n "$rel" && -f "$source" ]]; then
		source_digest=$(_omw_upgrade_manifest_hash "$rel" 2>/dev/null || omw_file_md5 "$source") || return 1
		target_digest=$(_omw_upgrade_target_md5 "$dest") || return 1
		printf '  source md5: %s\n' "$(_omw_upgrade_short_md5 "$source_digest")"
		printf '  target md5: %s\n' "$(_omw_upgrade_short_md5 "$target_digest")"
	fi
	printf '  decision: %s\n' "$decision"
}

_omw_upgrade_source_has_npm_cache() {
	local source_packages="$1"
	local cache

	for cache in "$source_packages"/npm-cache-*.tar.gz; do
		[[ -e "$cache" || -L "$cache" ]] && return 0
	done
	return 1
}

_omw_upgrade_source_has_config_packages() {
	local source_packages="$1"
	local package

	for package in "$source_packages"/config-*.tar.gz; do
		[[ -e "$package" || -L "$package" ]] && return 0
	done
	return 1
}

_omw_upgrade_force_replace_package_rel() {
	local rel="$1"

	_omw_upgrade_rel_is_config_package "$rel" || _omw_upgrade_rel_is_npm_cache "$rel"
}

_omw_upgrade_rel_is_npm_cache() {
	local rel="$1"

	[[ "$rel" == packages/npm-cache-*.tar.gz ]]
}

_omw_upgrade_rel_is_config_package() {
	local rel="$1"

	[[ "$rel" == packages/config-*.tar.gz ]]
}

_omw_upgrade_config_package_restore_dir() {
	local rel="$1"
	local base name version target

	base=$(basename "$rel")
	name="${base%.tar.gz}"
	version="${name##*-}"
	target="${name#config-}"
	target="${target%-"$version"}"
	[[ -n "$target" && -n "$version" && "$target" != "$name" ]] || return 1
	printf 'config/%s/%s' "$version" "$target"
}

_omw_upgrade_npm_cache_restore_dir() {
	printf 'builds/node/npm-cache'
}

_omw_upgrade_local_packages_files() {
	local dest_packages="$1"

	[[ -d "$dest_packages" ]] || return 0
	(
		cd "$dest_packages" || exit 1
		find . \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r rel; do
			printf 'packages/%s\n' "${rel#./}"
		done
	)
}

_omw_upgrade_package_status() {
	local manifest_rel="$1"
	local dest_packages="$2"
	local mode="$3"
	local target_path

	target_path=$(_omw_upgrade_target_path_for_rel "packages" "$dest_packages" "$manifest_rel") || return 1
	if _omw_upgrade_rel_is_npm_cache "$manifest_rel" || _omw_upgrade_rel_is_config_package "$manifest_rel"; then
		if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
			printf 'add\n'
		else
			printf 'replace\n'
		fi
	elif [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
		printf 'add\n'
	elif _omw_upgrade_manifest_entry_matches "$manifest_rel" "$target_path"; then
		printf 'keep\n'
	else
		printf 'replace\n'
	fi
}

_omw_upgrade_preview_local_only_packages() {
	local dest_packages="$1"
	local mode="$2"
	local local_rel status

	while IFS= read -r local_rel; do
		[[ -n "$local_rel" ]] || continue
		_omw_upgrade_manifest_has_path "$local_rel" && continue
		if [[ "$mode" == "replace" ]]; then
			status="delete"
		else
			status="keep-local"
		fi
		_omw_upgrade_print_package_status "$local_rel" "$status"
	done < <(_omw_upgrade_local_packages_files "$dest_packages")
}

_omw_upgrade_preview_package_items() {
	local source_packages="$1"
	local dest_packages="$2"
	local mode="$3"
	local manifest_rel status note shown=0

	while IFS= read -r manifest_rel; do
		[[ -n "$manifest_rel" ]] || continue
		status=$(_omw_upgrade_package_status "$manifest_rel" "$dest_packages" "$mode") || return 1
		note=$(_omw_upgrade_package_restore_note "$manifest_rel")
		_omw_upgrade_print_path_status "$status" "$manifest_rel" "$note"
		shown=1
	done < <(_omw_upgrade_manifest_file_paths_under "packages")
	_omw_upgrade_preview_local_only_packages "$dest_packages" "$mode"
	if ((shown == 0)) && [[ ! -d "$dest_packages" ]]; then
		_omw_upgrade_print_path_status "skip" "packages"
	fi
}

_omw_upgrade_package_restore_note() {
	local manifest_rel="$1"
	local restore_dir

	if _omw_upgrade_rel_is_config_package "$manifest_rel"; then
		restore_dir=$(_omw_upgrade_config_package_restore_dir "$manifest_rel" 2>/dev/null || true)
		[[ -n "$restore_dir" ]] && printf '%s' "$restore_dir"
	elif _omw_upgrade_rel_is_npm_cache "$manifest_rel"; then
		_omw_upgrade_npm_cache_restore_dir
	fi
}

_omw_upgrade_path_status() {
	local manifest_rel="$1"
	local rel="$2"
	local dest="$3"
	local target_path

	target_path=$(_omw_upgrade_target_path_for_rel "$rel" "$dest" "$manifest_rel") || return 1
	if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
		printf 'add\n'
	elif _omw_upgrade_manifest_entry_matches "$manifest_rel" "$target_path"; then
		printf 'keep\n'
	else
		printf 'replace\n'
	fi
}

_omw_upgrade_preview_manifest_items() {
	local rel="$1"
	local dest="$2"
	local manifest_rel status shown=0

	while IFS= read -r manifest_rel; do
		[[ -n "$manifest_rel" ]] || continue
		status=$(_omw_upgrade_path_status "$manifest_rel" "$rel" "$dest") || return 1
		_omw_upgrade_print_path_status "$status" "$manifest_rel"
		shown=1
	done < <(_omw_upgrade_manifest_file_paths_under "$rel")
	((shown == 1)) || _omw_upgrade_print_path_status "skip" "$rel"
}

_omw_upgrade_preview_config_items() {
	local dest_config="$2"
	local local_rel shown=0

	while IFS= read -r local_rel; do
		[[ -n "$local_rel" ]] || continue
		_omw_upgrade_print_path_status "preserve-local" "$local_rel"
		shown=1
	done < <(_omw_upgrade_config_local_files "$dest_config")
	return 0
}

_omw_upgrade_preview_local_only_manifest_files() {
	local rel="$1"
	local dest="$2"
	local mode="$3"
	local target_path target_rel status

	[[ "$mode" == "replace-exact" && -d "$dest" && ! -L "$dest" ]] || return 0
	while IFS= read -r target_path; do
		target_rel="${target_path#"$dest"/}"
		_omw_upgrade_manifest_has_path "$rel/$target_rel" && continue
		status="delete"
		_omw_upgrade_print_path_status "$status" "$rel/$target_rel"
	done < <(find "$dest" \( -type f -o -type l \) -print | LC_ALL=C sort)
}

_omw_upgrade_remove_current_npm_cache() {
	local dest_packages="$1"
	local rel current

	for rel in npm-cache-*.tar.gz; do
		current="$dest_packages/$rel"
		[[ -e "$current" || -L "$current" ]] || continue
		omw_safe_rm_rf "$current" || return 1
	done
}

_omw_upgrade_backup_current_npm_cache() {
	local source_packages="$1"
	local dest_packages="$2"
	local rel current backup_path

	_omw_upgrade_source_has_npm_cache "$source_packages" || return 0
	for rel in npm-cache-*.tar.gz; do
		current="$dest_packages/$rel"
		[[ -e "$current" || -L "$current" ]] || continue
		backup_path=$(_omw_common_backup_path_once "$current" "npm-cache") || return 1
		[[ -n "$backup_path" ]] && omw_log "Preserved previous npm cache before adopting bundle cache: $backup_path" "INFO"
	done
}

_omw_upgrade_prepare_config_stage() {
	local source_config="$1"
	local dest_config="$2"
	local stage_config="$3"

	omw_safe_rm_rf "$stage_config"
	mkdir -p "$stage_config"
	cp -a "$source_config" "$stage_config/config" || return 1
	if [[ -d "$dest_config/local" ]]; then
		omw_safe_rm_rf "$stage_config/config/local"
		cp -a "$dest_config/local" "$stage_config/config/local" || return 1
	else
		mkdir -p "$stage_config/config/local"
	fi
}

_omw_upgrade_bundle_root_from_dir() {
	local input="$1"

	if [[ -f "$input/omw" && -d "$input/lib" && -f "$input/packages.sh" && -f "$input/env.sh" && -f "$input/compose.yaml" ]]; then
		printf '%s\n' "$input"
		return 0
	fi
	if [[ -f "$input/oh-my-workspace/omw" && -d "$input/oh-my-workspace/lib" && -f "$input/oh-my-workspace/packages.sh" && -f "$input/oh-my-workspace/env.sh" && -f "$input/oh-my-workspace/compose.yaml" ]]; then
		printf '%s\n' "$input/oh-my-workspace"
		return 0
	fi
	return 1
}

_omw_upgrade_extract_bundle() {
	local input="$1"
	local stage_dir="$2"
	local root

	omw_safe_rm_rf "$stage_dir"
	mkdir -p "$stage_dir"
	if ! tar -xzf "$input" -C "$stage_dir"; then
		omw_log "Failed to extract upgrade bundle: $input" "ERROR"
		omw_safe_rm_rf "$stage_dir"
		return 1
	fi
	root=$(_omw_upgrade_bundle_root_from_dir "$stage_dir") || {
		omw_log "Upgrade bundle does not contain a valid OMW root." "ERROR"
		omw_safe_rm_rf "$stage_dir"
		return 1
	}
	printf '%s\n' "$root"
}

_omw_upgrade_resolve_bundle_root() {
	local input="$1"
	local stage_dir="$2"

	if [[ -d "$input" ]]; then
		_omw_upgrade_bundle_root_from_dir "$input" || {
			omw_log "Upgrade directory does not look like an OMW bundle: $input" "ERROR"
			return 1
		}
	elif [[ -f "$input" ]]; then
		if ! omw_archive_is_readable "$input"; then
			omw_log "Upgrade bundle is not a readable archive: $input" "ERROR"
			return 1
		fi
		_omw_upgrade_extract_bundle "$input" "$stage_dir"
	else
		omw_log "Upgrade source not found: $input" "ERROR"
		return 1
	fi
}

_omw_upgrade_plan_line() {
	local action="$1"
	local label="$2"
	local source="$3"
	local dest="$4"
	local policy="${5:-merge-overlay}"

	printf '%s\t%s\t%s\t%s\t%s\n' "$action" "$label" "$source" "$dest" "$policy"
}

_omw_upgrade_build_plan() {
	local bundle_root="$1"
	local replace_packages="$2"
	local item policy source

	_omw_upgrade_require_bundle_metadata || return 1

	while IFS=$'\t' read -r item policy; do
		source="$bundle_root/$item"
		if [[ -e "$source" || -L "$source" ]]; then
			if [[ "$item" == "config" ]]; then
				_omw_upgrade_plan_line "preserve-config" "$item" "$source" "$CONFIG_PATH" "$policy"
			else
				_omw_upgrade_plan_line "update" "$item" "$source" "$OMW_HOME/$item" "$policy"
			fi
		else
			_omw_upgrade_plan_line "skip-missing" "$item" "$source" "$OMW_HOME/$item" "$policy"
		fi
	done < <(_omw_upgrade_managed_items)

	if [[ "$replace_packages" == "true" ]]; then
		if [[ ! -d "$bundle_root/packages" ]]; then
			omw_log "Upgrade bundle does not contain packages/ for --replace-packages." "ERROR"
			return 1
		fi
		_omw_upgrade_plan_line "replace-packages" "packages" "$bundle_root/packages" "$PACKAGES_PATH" "replace-exact"
	elif [[ -d "$bundle_root/packages" ]]; then
		_omw_upgrade_plan_line "merge-packages" "packages" "$bundle_root/packages" "$PACKAGES_PATH" "merge-overlay"
	else
		_omw_upgrade_plan_line "skip-missing" "packages" "$bundle_root/packages" "$PACKAGES_PATH" "merge-overlay"
	fi
}

_omw_upgrade_preview_plan() {
	local plan="$1"
	local action label source dest policy
	local rel

	printf '%-72s %-14s %s\n' "PATH" "STATUS" "NOTE"
	printf '%-72s %-14s %s\n' "----" "------" "----"
	while IFS=$'\t' read -r action label source dest policy; do
		[[ -n "$action" ]] || continue
		case "$action" in
		update)
			rel=$(_omw_upgrade_source_rel "$source") || rel="$label"
			if [[ -f "$source" || -L "$source" ]]; then
				if [[ ! -e "$dest" && ! -L "$dest" ]]; then
					_omw_upgrade_print_path_status "add" "$rel"
				elif _omw_upgrade_manifest_entry_matches "$rel" "$dest"; then
					_omw_upgrade_print_path_status "keep" "$rel"
				else
					_omw_upgrade_print_path_status "replace" "$rel"
				fi
			else
				_omw_upgrade_preview_manifest_items "$rel" "$dest" || return 1
				_omw_upgrade_preview_local_only_manifest_files "$rel" "$dest" "$policy" || return 1
			fi
			;;
		preserve-config)
			rel=$(_omw_upgrade_source_rel "$source") || rel="$label"
			_omw_upgrade_preview_config_items "$source" "$dest" || return 1
			;;
		merge-packages)
			_omw_upgrade_preview_package_items "$source" "$dest" "merge" || return 1
			;;
		replace-packages)
			_omw_upgrade_preview_package_items "$source" "$dest" "replace" || return 1
			;;
		skip-missing)
			_omw_upgrade_print_path_status "skip-missing" "$label"
			;;
		*)
			omw_log "Unknown upgrade plan action: $action" "ERROR"
			return 1
			;;
		esac
	done <<<"$plan"
}

_omw_upgrade_execute_update() {
	local label="$1"
	local source="$2"
	local dest="$3"
	local policy="${4:-replace-exact}"
	local rel

	rel=$(_omw_upgrade_source_rel "$source") || rel="$label"
	if ! _omw_upgrade_item_needs_update "$source" "$dest" "$rel" "$policy"; then
		_omw_upgrade_print_action "Unchanged" "$label"
		return 0
	fi
	if [[ "$policy" == "versioned-lib" && "$rel" == "lib" ]]; then
		_omw_upgrade_execute_versioned_lib "$label" "$source" "$dest"
		return
	fi
	omw_tx_backup_internal "$dest" || return 1
	if [[ -d "$source" && ! -L "$source" ]]; then
		cp -a "$source" "$dest"
	else
		mkdir -p "$(dirname "$dest")"
		cp -a "$source" "$dest"
	fi
	_omw_upgrade_print_action "Updated" "$label"
}

_omw_upgrade_execute_versioned_lib() {
	local label="$1"
	local source_lib="$2"
	local dest_lib="$3"
	local version source_version_dir dest_version_dir

	version=$(_omw_upgrade_bundle_version)
	[[ -n "$version" ]] || {
		omw_log "Upgrade bundle version is missing; cannot update versioned lib." "ERROR"
		return 1
	}
	source_version_dir="$source_lib/$version"
	dest_version_dir="$dest_lib/$version"
	[[ -d "$source_version_dir" && ! -L "$source_version_dir" ]] || {
		omw_log "Upgrade bundle is missing lib/$version." "ERROR"
		return 1
	}
	mkdir -p "$dest_lib"
	omw_tx_backup_internal "$dest_version_dir" || return 1
	cp -a "$source_version_dir" "$dest_version_dir" || return 1
	_omw_upgrade_print_action "Updated" "$label/$version"
}

_omw_upgrade_execute_config() {
	local label="$1"
	local source_config="$2"
	local dest_config="$3"
	local policy="${4:-preserve-local}"
	local stage_config="$BUILDS_PATH/.upgrade-config-$$"
	local rel

	rel=$(_omw_upgrade_source_rel "$source_config") || rel="$label"
	if ! _omw_upgrade_item_needs_update "$source_config" "$dest_config" "$rel" "$policy"; then
		_omw_upgrade_print_action "Unchanged" "$label"
		return 0
	fi

	_omw_upgrade_prepare_config_stage "$source_config" "$dest_config" "$stage_config" || return 1
	omw_tx_track_internal_tmp "$stage_config" || return 1
	omw_tx_backup_internal "$dest_config" || return 1
	mv "$stage_config/config" "$dest_config" || return 1
	_omw_upgrade_print_action "Updated" "$label"
	_omw_upgrade_preview_config_items "$source_config" "$dest_config" || return 1
}

_omw_upgrade_execute_merge_packages() {
	local label="$1"
	local source_packages="$2"
	local dest_packages="$3"
	local policy="${4:-merge-overlay}"
	local stage_packages="$BUILDS_PATH/.upgrade-packages-$$"
	local rel manifest_rel source_path staged_path changed=0
	local -a replaced_special_packages=()

	if [[ ! -d "$source_packages" ]]; then
		_omw_upgrade_print_action "Skipped missing" "$label"
		return 0
	fi

	rel=$(_omw_upgrade_source_rel "$source_packages") || rel="$label"
	if ! _omw_upgrade_item_needs_update "$source_packages" "$dest_packages" "$rel" "$policy" &&
		! _omw_upgrade_source_has_npm_cache "$source_packages" &&
		! _omw_upgrade_source_has_config_packages "$source_packages"; then
		_omw_upgrade_print_action "Unchanged" "$label"
		return 0
	fi

	omw_safe_rm_rf "$stage_packages"
	mkdir -p "$stage_packages"
	if [[ -d "$dest_packages" ]]; then
		omw_copy_path_contents "$dest_packages" "$stage_packages" || return 1
	fi
	if _omw_upgrade_source_has_npm_cache "$source_packages"; then
		_omw_upgrade_remove_current_npm_cache "$stage_packages" || return 1
	fi
	_omw_upgrade_backup_current_npm_cache "$source_packages" "$dest_packages" || return 1
	while IFS= read -r manifest_rel; do
		source_path="$OMW_UPGRADE_BUNDLE_ROOT/$manifest_rel"
		staged_path=$(_omw_upgrade_target_path_for_rel "$rel" "$stage_packages" "$manifest_rel") || return 1
		[[ -e "$source_path" || -L "$source_path" ]] || continue
		if _omw_upgrade_force_replace_package_rel "$manifest_rel" || ! _omw_upgrade_manifest_entry_matches "$manifest_rel" "$staged_path"; then
			mkdir -p "$(dirname "$staged_path")"
			[[ -e "$staged_path" || -L "$staged_path" ]] && rm -rf -- "$staged_path"
			cp -a "$source_path" "$staged_path" || return 1
			((++changed))
			if _omw_upgrade_force_replace_package_rel "$manifest_rel"; then
				replaced_special_packages+=("$manifest_rel")
			fi
		fi
	done < <(_omw_upgrade_manifest_paths_under "$rel")
	omw_tx_track_internal_tmp "$stage_packages" || return 1
	omw_tx_backup_internal "$dest_packages" || return 1
	mv "$stage_packages" "$dest_packages" || return 1
	_omw_upgrade_print_action "Merged" "$label"
	for manifest_rel in "${replaced_special_packages[@]}"; do
		_omw_upgrade_print_path_status "replace" "$manifest_rel" "$(_omw_upgrade_package_restore_note "$manifest_rel")"
	done
	omw_log "Merged $changed changed package file(s) from bundle manifest." "INFO"
}

_omw_upgrade_execute_replace_packages() {
	local label="$1"
	local source_packages="$2"
	local dest_packages="$3"
	local policy="${4:-replace-exact}"
	local rel

	if [[ ! -d "$source_packages" ]]; then
		omw_log "Upgrade bundle does not contain packages/ for --replace-packages." "ERROR"
		return 1
	fi
	rel=$(_omw_upgrade_source_rel "$source_packages") || rel="$label"
	if ! _omw_upgrade_item_needs_update "$source_packages" "$dest_packages" "$rel" "$policy"; then
		_omw_upgrade_print_action "Unchanged" "$label"
		return 0
	fi
	_omw_upgrade_backup_current_npm_cache "$source_packages" "$dest_packages" || return 1
	omw_tx_backup_internal "$dest_packages" || return 1
	cp -a "$source_packages" "$dest_packages" || return 1
	_omw_upgrade_print_action "Replaced" "$label"
	_omw_upgrade_preview_package_items "$source_packages" "$dest_packages" "replace" || return 1
}

_omw_upgrade_execute_plan() {
	local plan="$1"
	local action label source dest policy

	while IFS=$'\t' read -r action label source dest policy; do
		[[ -n "$action" ]] || continue
		case "$action" in
		update) _omw_upgrade_execute_update "$label" "$source" "$dest" "$policy" || return 1 ;;
		preserve-config) _omw_upgrade_execute_config "$label" "$source" "$dest" "$policy" || return 1 ;;
		merge-packages) _omw_upgrade_execute_merge_packages "$label" "$source" "$dest" "$policy" || return 1 ;;
		replace-packages) _omw_upgrade_execute_replace_packages "$label" "$source" "$dest" "$policy" || return 1 ;;
		skip-missing) _omw_upgrade_print_action "Skipped missing" "$label" ;;
		*)
			omw_log "Unknown upgrade plan action: $action" "ERROR"
			return 1
			;;
		esac
	done <<<"$plan"
}

omw_upgrade_from_bundle() {
	local input="$1"
	local dry_run="${2:-false}"
	local replace_packages="${3:-false}"
	local stage_dir="$BUILDS_PATH/.upgrade-bundle-$$"
	local bundle_root plan status=0

	omw_log "--- Upgrading OMW from bundle ---" "INFO"
	bundle_root=$(_omw_upgrade_resolve_bundle_root "$input" "$stage_dir") || return 1
	OMW_UPGRADE_BUNDLE_ROOT="$bundle_root"
	OMW_UPGRADE_META_FILE="$bundle_root/.omw-bundle-meta"
	OMW_UPGRADE_MANIFEST_FILE="$bundle_root/.omw-bundle-manifest"
	plan=$(_omw_upgrade_build_plan "$bundle_root" "$replace_packages") || {
		[[ -d "$stage_dir" ]] && omw_safe_rm_rf "$stage_dir"
		return 1
	}

	if [[ "$dry_run" == "true" ]]; then
		_omw_upgrade_preview_plan "$plan" || status=$?
		[[ -d "$stage_dir" ]] && omw_safe_rm_rf "$stage_dir"
		if ((status == 0)); then
			omw_log "Upgrade preview complete." "SUCCESS"
		fi
		return "$status"
	fi

	omw_tx_begin || {
		[[ -d "$stage_dir" ]] && omw_safe_rm_rf "$stage_dir"
		return 1
	}
	if [[ -d "$stage_dir" ]]; then
		omw_tx_track_internal_tmp "$stage_dir" || status=$?
	fi
	if ((status == 0)); then
		_omw_upgrade_execute_plan "$plan" || status=$?
	fi

	if ((status == 0)); then
		omw_tx_commit
		omw_log "Upgrade complete." "SUCCESS"
	else
		omw_tx_rollback
		omw_log "Upgrade failed; restored previous OMW state." "ERROR"
	fi
	return "$status"
}
