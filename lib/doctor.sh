# shellcheck shell=bash
# Local health checks for the OMW runtime.

_omw_doctor_result() {
	local status="$1"
	local message="$2"
	printf '%-6s %s\n' "$status" "$message"
}

_omw_doctor_check_command() {
	local cmd="$1"
	if command -v "$cmd" >/dev/null 2>&1; then
		_omw_doctor_result "OK" "$cmd"
		return 0
	fi
	_omw_doctor_result "ERROR" "missing command: $cmd"
	return 1
}

_omw_doctor_check_profile() {
	local profile="$1"
	local errors=0 cmd output
	local -a commands=()

	printf '\nSystem dependency profile: %s\n' "$profile"
	output=$(_omw_common_profile_commands "$profile") || {
		_omw_doctor_result "ERROR" "unknown dependency profile: $profile"
		return 1
	}
	mapfile -t commands <<<"$output"
	for cmd in "${commands[@]}"; do
		_omw_doctor_check_command "$cmd" || ((++errors))
	done
	return "$errors"
}

_omw_doctor_check_directories() {
	local errors=0 dir

	printf '\nOMW directories\n'
	for dir in "$CONFIG_PATH" "$PACKAGES_PATH" "$BUILDS_PATH" "$SOFTWARE_INSTALL_PATH" "$MODULEFILES_PATH" "$APPS_INSTALL_PATH" "$SCRIPTS_BIN_PATH"; do
		if [[ -d "$dir" ]]; then
			_omw_doctor_result "OK" "$dir"
		else
			_omw_doctor_result "ERROR" "missing directory: $dir"
			((++errors))
		fi
	done
	return "$errors"
}

_omw_doctor_check_module() {
	printf '\nEnvironment modules\n'
	if command -v module >/dev/null 2>&1; then
		_omw_doctor_result "OK" "module command is available"
		return 0
	fi
	_omw_doctor_result "WARN" "module command is not available in this shell"
	return 0
}

_omw_doctor_check_registry() {
	printf '\nPackage registry\n'
	_omw_doctor_result "OK" "software definitions: ${#SOFTWARE_LIST[@]}"
	_omw_doctor_result "OK" "app definitions: ${#APP_LIST[@]}"
	_omw_doctor_result "OK" "Node package definitions: ${#NODE_PACKAGE_LIST[@]}"
	_omw_doctor_result "OK" "Node cache-only definitions: ${#NODE_CACHE_PACKAGE_LIST[@]}"
	return 0
}

_omw_doctor_check_offline_assets() {
	local missing=0 path name version versions_str url app_url

	printf '\nOffline asset cache\n'
	for name in "${SOFTWARE_LIST[@]}"; do
		versions_str="${SOFTWARE_VERSIONS[$name]:-}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			url=$(omw_get_software_url "$name" "$version")
			[[ -z "$url" ]] && continue
			path=$(omw_software_package_path "$name" "$version") || continue
			[[ -f "$path" ]] || ((++missing))
		done
	done
	for name in "${APP_LIST[@]}"; do
		app_url=$(omw_get_app_url "$name" 2>/dev/null || true)
		[[ -z "$app_url" ]] && continue
		path=$(omw_app_package_path "$app_url")
		[[ -f "$path" ]] || ((++missing))
	done
	if ((missing == 0)); then
		_omw_doctor_result "OK" "declared package archives are cached"
	else
		_omw_doctor_result "WARN" "missing cached package archives: $missing"
	fi
	return 0
}

omw_doctor() {
	local profile="${1:-base}"
	local errors=0

	printf 'OMW doctor\n'
	printf 'Home: %s\n' "$OMW_HOME"
	printf 'Version: %s\n' "$OMW_VERSION"
	printf 'Bash: %s\n' "$BASH_VERSION"

	_omw_doctor_check_directories || errors=$((errors + $?))
	_omw_doctor_check_profile "$profile" || errors=$((errors + $?))
	_omw_doctor_check_module || errors=$((errors + $?))
	_omw_doctor_check_registry || errors=$((errors + $?))
	_omw_doctor_check_offline_assets || errors=$((errors + $?))

	printf '\n'
	if ((errors > 0)); then
		omw_log "Doctor found $errors error(s)." "ERROR"
		return 1
	fi
	omw_log "Doctor completed with no critical errors." "SUCCESS"
}
