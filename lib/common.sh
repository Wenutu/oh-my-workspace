# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_common_*.
omw_log() {
	local msg="$1"
	local level="${2:-INFO}"
	local ts
	ts=$(date +"%T")
	declare -A c=([DEBUG]=34 [INFO]=36 [WARN]=33 [ERROR]=31 [SUCCESS]=32)
	if [[ "${OMW_NO_COLOR:-false}" == "true" || -n "${NO_COLOR:-}" || ! -t 2 ]]; then
		printf '[%s] [%s] - %s\n' "$ts" "$level" "$msg" >&2
	else
		printf '\033[1;%sm[%s] [%s] - %s\033[0m\n' "${c[$level]:-36}" "$ts" "$level" "$msg" >&2
	fi
}

omw_init_globals() {
	OMW_HOME=$(cd "$OMW_HOME" && pwd)
	cd "$OMW_HOME"
	declare -g -a SOFTWARE_LIST SOFTWARE_BUILD_ALL_EXCLUDES APP_LIST NODE_PACKAGE_LIST NODE_CACHE_PACKAGE_LIST CONFIG_BACKUP_PATHS CONFIG_TARGET_LIST
	declare -g -a OMW_TX_TMP_PATHS OMW_TX_INTERNAL_PATHS OMW_TX_INTERNAL_BACKUPS OMW_TX_EXTERNAL_PATHS OMW_TX_EXTERNAL_BACKUPS
	declare -g -A SOFTWARE_VERSIONS SOFTWARE_URLS SOFTWARE_DEPS SOFTWARE_CONFIG_CMDS SOFTWARE_CFLAGS SOFTWARE_LDFLAGS
	declare -g -A APP_VERSIONS APP_URLS APP_EXECUTABLE_NAME APP_SOURCE_URLS APP_BIN_DIRS
	declare -g -A NODE_PACKAGE_NAMES NODE_PACKAGE_VERSIONS NODE_PACKAGE_BINS NODE_PACKAGE_NODE_VERSIONS
	declare -g -A NODE_CACHE_PACKAGE_NAMES NODE_CACHE_PACKAGE_VERSIONS NODE_CACHE_PACKAGE_NODE_VERSIONS

	# Source environment variables if they exist
	# shellcheck disable=SC1091
	[[ -f "$OMW_HOME/env.sh" ]] && source "$OMW_HOME/env.sh"

	# Define core paths
	CONFIG_PATH="$OMW_HOME/config"
	CONFIG_RELEASE_PATH="$CONFIG_PATH/$OMW_VERSION"
	CONFIG_LOCAL_PATH="$CONFIG_PATH/local"
	PACKAGES_PATH="$OMW_HOME/packages"
	BUILDS_PATH="$OMW_HOME/builds"
	SOFTWARE_INSTALL_PATH="$OMW_HOME/tools/software"
	MODULEFILES_PATH="$OMW_HOME/tools/modulefiles"
	APPS_INSTALL_PATH="$OMW_HOME/apps"
	SCRIPTS_BIN_PATH="$OMW_HOME/bin"
	CONFIG_TARGET_LIST=(tmux vim zsh)

	# Ensure core directories exist
	readonly DIRECTORIES=(
		"$CONFIG_PATH" "$CONFIG_LOCAL_PATH" "$PACKAGES_PATH"
		"$BUILDS_PATH" "$SOFTWARE_INSTALL_PATH" "$MODULEFILES_PATH" "$APPS_INSTALL_PATH" "$SCRIPTS_BIN_PATH"
	)
	for dir in "${DIRECTORIES[@]}"; do
		[[ ! -d "$dir" ]] && mkdir -p "$dir"
	done

	# Load software definitions from configuration file
	local conf_file="$OMW_HOME/packages.sh"
	if [[ -f "$conf_file" ]]; then
		omw_log "Loading definitions from $conf_file" "INFO"
		local VERSION='${VERSION}'
		# shellcheck source=/dev/null
		source "$conf_file"
		_omw_common_validate_config
	else
		omw_log "Configuration file not found: $conf_file. Cannot proceed." "ERROR"
		exit 1
	fi

	# Set build-related constants
	local core_count
	if command -v nproc &>/dev/null; then
		core_count=$(nproc)
	elif command -v sysctl &>/dev/null; then
		core_count=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
	else
		core_count=1
	fi
	if ((core_count > 2)); then
		readonly BUILD_JOBS=$((core_count - 2))
	else
		readonly BUILD_JOBS=1
	fi

	readonly MAX_RETRIES=3
	readonly DOWNLOAD_TIMEOUT=300
	readonly GCC_PREREQ_BASE_URL='http://gcc.gnu.org/pub/gcc/infrastructure/'
	CONFIG_BACKUP_PATHS=()
	OMW_TX_ACTIVE=false
	OMW_TX_TMP_PATHS=()
	OMW_TX_INTERNAL_PATHS=()
	OMW_TX_INTERNAL_BACKUPS=()
	OMW_TX_EXTERNAL_PATHS=()
	OMW_TX_EXTERNAL_BACKUPS=()
	return 0
}

_omw_common_validate_software_config() {
	local errors=0
	local name version versions_str key url build_cmd deps dep dep_name dep_version excluded
	local placeholder="${OMW_NONE:--}"

	for name in "${SOFTWARE_LIST[@]}"; do
		if [[ "$name" == "$placeholder" ]]; then
			omw_log "SOFTWARE_LIST contains the empty-field placeholder." "ERROR"
			((++errors))
		fi
		versions_str="${SOFTWARE_VERSIONS[$name]:-}"
		if [[ -z "$versions_str" ]]; then
			omw_log "SOFTWARE_LIST includes '$name' but SOFTWARE_VERSIONS[$name] is not defined." "ERROR"
			((++errors))
			continue
		fi
		for version in $versions_str; do
			key="$name@$version"
			if [[ "$version" == "$placeholder" ]]; then
				omw_log "SOFTWARE_VERSIONS[$name] contains the empty-field placeholder." "ERROR"
				((++errors))
			fi
			if [[ -z "${SOFTWARE_CONFIG_CMDS[$key]+set}" ]]; then
				omw_log "SOFTWARE_CONFIG_CMDS[$key] is not defined." "ERROR"
				((++errors))
			else
				build_cmd="${SOFTWARE_CONFIG_CMDS[$key]}"
				if [[ -z "$build_cmd" && "$name" != "local" ]] && ! declare -F "_omw_build_$name" >/dev/null; then
					omw_log "SOFTWARE_CONFIG_CMDS[$key] is empty but _omw_build_$name is not defined." "ERROR"
					((++errors))
				fi
			fi
			url="${SOFTWARE_URLS[$key]:-}"
			if [[ "$url" == "$placeholder" ]]; then
				omw_log "SOFTWARE_URLS[$key] still contains the empty-field placeholder." "ERROR"
				((++errors))
			elif [[ "$name" != "local" && -z "$url" ]]; then
				omw_log "SOFTWARE_URLS[$key] must be defined." "ERROR"
				((++errors))
			fi
			if [[ -z "${SOFTWARE_DEPS[$key]+set}" ]]; then
				omw_log "SOFTWARE_DEPS[$key] is not defined." "ERROR"
				((++errors))
				continue
			fi
			deps="${SOFTWARE_DEPS[$key]}"
			if [[ "$deps" == "$placeholder" ]]; then
				omw_log "SOFTWARE_DEPS[$key] still contains the empty-field placeholder." "ERROR"
				((++errors))
			fi
			for dep in $deps; do
				dep_name="${dep%@*}"
				dep_version="${dep#*@}"
				if [[ "$dep_name" == "$dep_version" || -z "${SOFTWARE_VERSIONS[$dep_name]:-}" ]]; then
					omw_log "Dependency '$dep' for $name@$version does not reference a defined software package." "ERROR"
					((++errors))
				elif ! omw_contains_word "$dep_version" "${SOFTWARE_VERSIONS[$dep_name]}"; then
					omw_log "Dependency '$dep' for $name@$version references an undefined version." "ERROR"
					((++errors))
				fi
			done
		done
	done

	for excluded in "${SOFTWARE_BUILD_ALL_EXCLUDES[@]}"; do
		if ! omw_contains_word "$excluded" "${SOFTWARE_LIST[*]}"; then
			omw_log "SOFTWARE_BUILD_ALL_EXCLUDES includes '$excluded' but it is not declared in SOFTWARE_LIST." "ERROR"
			((++errors))
		fi
	done

	return "$errors"
}

_omw_common_validate_software_dependency_cycles() {
	local target
	declare -A visit_state=()

	_omw_common_visit_software_dependency() {
		local current="$1"
		local dep dep_name dep_version

		case "${visit_state[$current]:-}" in
		visiting)
			omw_log "Software dependency cycle detected at $current." "ERROR"
			return 1
			;;
		visited) return 0 ;;
		esac
		visit_state["$current"]="visiting"
		for dep in ${SOFTWARE_DEPS[$current]:-}; do
			dep_name="${dep%@*}"
			dep_version="${dep#*@}"
			[[ "$dep_name" != "$dep_version" && -n "${SOFTWARE_DEPS[$dep_name@$dep_version]+set}" ]] || continue
			_omw_common_visit_software_dependency "$dep_name@$dep_version" || return 1
		done
		visit_state["$current"]="visited"
	}

	for target in "${!SOFTWARE_DEPS[@]}"; do
		_omw_common_visit_software_dependency "$target" || return 1
	done
	return 0
}

_omw_common_validate_app_config() {
	local errors=0
	local app
	local placeholder="${OMW_NONE:--}"

	for app in "${APP_LIST[@]}"; do
		if [[ "$app" == "$placeholder" ]]; then
			omw_log "APP_LIST contains the empty-field placeholder." "ERROR"
			((++errors))
		fi
		[[ -n "${APP_VERSIONS[$app]:-}" ]] || {
			omw_log "APP_VERSIONS[$app] is not defined." "ERROR"
			((++errors))
		}
		[[ "${APP_VERSIONS[$app]:-}" != "$placeholder" ]] || {
			omw_log "APP_VERSIONS[$app] contains the empty-field placeholder." "ERROR"
			((++errors))
		}
		[[ -n "${APP_URLS[$app]:-}" ]] || {
			omw_log "APP_URLS[$app] is not defined." "ERROR"
			((++errors))
		}
		[[ "${APP_URLS[$app]:-}" != "$placeholder" ]] || {
			omw_log "APP_URLS[$app] contains the empty-field placeholder." "ERROR"
			((++errors))
		}
		if [[ -z "${APP_EXECUTABLE_NAME[$app]:-}" && -z "${APP_BIN_DIRS[$app]:-}" ]] &&
			! declare -F "_omw_app_install_$app" >/dev/null; then
			omw_log "App '$app' has no executable or bin dirs and _omw_app_install_$app is not defined." "ERROR"
			((++errors))
		fi
	done

	return "$errors"
}

_omw_common_validate_node_config() {
	local errors=0
	local alias package_name version bin_name node_version
	local placeholder="${OMW_NONE:--}"

	validate_node_package_version() {
		local label="$1"
		local pkg_version="$2"
		if [[ -z "$pkg_version" || "$pkg_version" == "$placeholder" || "$pkg_version" == "latest" || "$pkg_version" == *[\^\~\>\<\=\|\*]* || "$pkg_version" == x* || "$pkg_version" == X* || "$pkg_version" == *".x"* || "$pkg_version" == *".X"* || "$pkg_version" == *"x."* || "$pkg_version" == *"X."* ]]; then
			omw_log "$label must be a fixed concrete version." "ERROR"
			((++errors))
		fi
	}

	validate_node_version_ref() {
		local label="$1"
		local ref_version="$2"
		if [[ -z "$ref_version" || "$ref_version" == "$placeholder" ]]; then
			omw_log "$label must be an OMW Node version." "ERROR"
			((++errors))
		elif ! omw_contains_word "$ref_version" "${SOFTWARE_VERSIONS[node]:-}"; then
			omw_log "$label references undefined node version: $ref_version" "ERROR"
			((++errors))
		fi
	}

	for alias in "${NODE_PACKAGE_LIST[@]}"; do
		if [[ "$alias" == "$placeholder" ]]; then
			omw_log "NODE_PACKAGE_LIST contains the empty-field placeholder." "ERROR"
			((++errors))
		fi
		package_name="${NODE_PACKAGE_NAMES[$alias]:-}"
		version="${NODE_PACKAGE_VERSIONS[$alias]:-}"
		bin_name="${NODE_PACKAGE_BINS[$alias]:-}"
		node_version="${NODE_PACKAGE_NODE_VERSIONS[$alias]:-}"
		if [[ -z "$package_name" || "$package_name" == "$placeholder" ]]; then
			omw_log "NODE_PACKAGE_NAMES[$alias] must be a package name." "ERROR"
			((++errors))
		fi
		validate_node_package_version "NODE_PACKAGE_VERSIONS[$alias]" "$version"
		if [[ -n "$bin_name" && "$bin_name" == "$placeholder" ]]; then
			omw_log "NODE_PACKAGE_BINS[$alias] still contains the empty-field placeholder." "ERROR"
			((++errors))
		fi
		validate_node_version_ref "NODE_PACKAGE_NODE_VERSIONS[$alias]" "$node_version"
	done

	for alias in "${NODE_CACHE_PACKAGE_LIST[@]}"; do
		if [[ "$alias" == "$placeholder" ]]; then
			omw_log "NODE_CACHE_PACKAGE_LIST contains the empty-field placeholder." "ERROR"
			((++errors))
		fi
		package_name="${NODE_CACHE_PACKAGE_NAMES[$alias]:-}"
		version="${NODE_CACHE_PACKAGE_VERSIONS[$alias]:-}"
		node_version="${NODE_CACHE_PACKAGE_NODE_VERSIONS[$alias]:-}"
		if [[ -z "$package_name" || "$package_name" == "$placeholder" ]]; then
			omw_log "NODE_CACHE_PACKAGE_NAMES[$alias] must be a package name." "ERROR"
			((++errors))
		fi
		validate_node_package_version "NODE_CACHE_PACKAGE_VERSIONS[$alias]" "$version"
		validate_node_version_ref "NODE_CACHE_PACKAGE_NODE_VERSIONS[$alias]" "$node_version"
	done

	return "$errors"
}

_omw_common_validate_config() {
	local errors=0

	_omw_common_validate_software_config || errors=$((errors + $?))
	_omw_common_validate_software_dependency_cycles || ((++errors))
	_omw_common_validate_app_config || errors=$((errors + $?))
	_omw_common_validate_node_config || errors=$((errors + $?))
	if [[ -z "${OMW_COC_NODE_VERSION:-}" ]]; then
		omw_log "OMW_COC_NODE_VERSION must reference a declared OMW Node version." "ERROR"
		((++errors))
	elif ! omw_contains_word "$OMW_COC_NODE_VERSION" "${SOFTWARE_VERSIONS[node]:-}"; then
		omw_log "OMW_COC_NODE_VERSION references undefined node version: $OMW_COC_NODE_VERSION" "ERROR"
		((++errors))
	fi

	if ((errors > 0)); then
		omw_log "Configuration validation failed with $errors error(s)." "ERROR"
		exit 1
	fi
}

omw_software_prefix() {
	local name="$1"
	local version="$2"
	printf '%s/%s/%s-%s' "$SOFTWARE_INSTALL_PATH" "$name" "$name" "$version"
}

omw_software_modulefile() {
	local name="$1"
	local version="$2"
	printf '%s/%s/%s-%s' "$MODULEFILES_PATH" "$name" "$name" "$version"
}

omw_software_package_path() {
	local name="$1"
	local version="$2"
	local url
	url=$(omw_get_software_url "$name" "$version")
	[[ -z "$url" ]] && return 1
	printf '%s/%s' "$PACKAGES_PATH" "$(basename "$url")"
}

omw_app_install_dir() {
	local app="$1"
	local version="$2"
	printf '%s/%s-%s' "$APPS_INSTALL_PATH" "$app" "$version"
}

omw_app_package_path() {
	local url="$1"
	local version="${2:-}"
	[[ -n "$version" ]] && url=$(omw_render_version_template "$url" "$version")
	printf '%s/%s' "$PACKAGES_PATH" "$(basename "$url")"
}

omw_config_release_path() {
	printf '%s' "$CONFIG_RELEASE_PATH"
}

omw_config_source_target_dir() {
	printf '%s/%s' "$CONFIG_PATH" "$1"
}

omw_config_runtime_target_dir() {
	printf '%s/%s' "$CONFIG_RELEASE_PATH" "$1"
}

omw_config_local_path() {
	printf '%s' "$CONFIG_LOCAL_PATH"
}

omw_config_target_dir() {
	omw_config_runtime_target_dir "$1"
}

omw_software_build_all_enabled() {
	local name="$1"
	! omw_contains_word "$name" "${SOFTWARE_BUILD_ALL_EXCLUDES[*]:-}"
}

_omw_common_profile_commands() {
	case "$1" in
	base) printf '%s\n' tar sed find ;;
	download) printf '%s\n' wget ;;
	build) printf '%s\n' tar sed find wget make module ;;
	local) printf '%s\n' tar sed find wget make module yum yumdownloader rpm2cpio cpio ;;
	app) printf '%s\n' tar sed find wget unzip ;;
	config) printf '%s\n' tar sed find ;;
	config-prepare) printf '%s\n' tar sed find git ;;
	config-prepare-vim) printf '%s\n' tar sed find wget make module git ;;
	node) printf '%s\n' tar sed find module ;;
	offline) printf '%s\n' tar sed find wget make module yum yumdownloader rpm2cpio cpio unzip git ;;
	*)
		omw_log "Unknown dependency profile: $1" "ERROR"
		return 1
		;;
	esac
}

omw_check_sys_deps() {
	local profile="${1:-base}"
	local missing_deps=0 cmd
	omw_log "Checking system dependencies for profile '$profile'..." "INFO"
	while IFS= read -r cmd; do
		if ! command -v "$cmd" &>/dev/null; then
			omw_log "Missing command: $cmd" "ERROR"
			missing_deps=1
		fi
	done < <(_omw_common_profile_commands "$profile")
	if ((missing_deps)); then return 1; fi
	omw_log "System dependencies are satisfied." "SUCCESS"
	return 0
}

_omw_common_backup_path_once() {
	local path="$1"
	local reason="${2:-config}"
	local backup_dir backup_path stamp suffix=0

	stamp=$(date +%Y%m%d%H%M%S)
	backup_dir="$OMW_HOME/backups/$reason/$stamp"
	while [[ -e "$backup_dir/$(basename "$path")" || -L "$backup_dir/$(basename "$path")" ]]; do
		((++suffix))
		backup_dir="$OMW_HOME/backups/$reason/$stamp-$suffix"
	done

	[[ -e "$path" || -L "$path" ]] || return 0
	mkdir -p "$backup_dir"
	backup_path="$backup_dir/$(basename "$path")"
	cp -a "$path" "$backup_path"
	omw_log "Backed up $path to $backup_path" "INFO"
	printf '%s\n' "$backup_path"
}

omw_backup_path_for_config() {
	local path="$1"
	local reason="${2:-config}"
	local backup_path

	backup_path=$(_omw_common_backup_path_once "$path" "$reason")
	if [[ -n "$backup_path" ]]; then
		CONFIG_BACKUP_PATHS+=("$backup_path")
	fi
}

omw_print_config_backup_paths() {
	local path

	((${#CONFIG_BACKUP_PATHS[@]} == 0)) && return 0
	omw_log "Backup files created:" "INFO"
	for path in "${CONFIG_BACKUP_PATHS[@]}"; do
		echo "  - $path" >&2
	done
}

_omw_common_move_external_aside() {
	local path="$1"
	local reason="${2:-config}"
	local backup_dir="$OMW_HOME/backups/$reason/replaced-$(date +%Y%m%d%H%M%S)"

	[[ -e "$path" || -L "$path" ]] || return 0
	mkdir -p "$backup_dir"
	mv "$path" "$backup_dir/$(basename "$path")"
	omw_log "Moved replaced path $path to $backup_dir" "INFO"
}

omw_safe_link_with_backup() {
	local source="$1"
	local dest="$2"
	local reason="${3:-config}"
	local current_target

	if [[ -L "$dest" ]]; then
		current_target=$(readlink "$dest")
		[[ "$current_target" == "$source" ]] && return 0
		rm -f "$dest"
	elif [[ -e "$dest" ]]; then
		omw_backup_path_for_config "$dest" "$reason"
		_omw_common_move_external_aside "$dest" "$reason"
	fi

	ln -s "$source" "$dest"
}

omw_link_if_absent_with_backup() {
	local source="$1"
	local dest="$2"
	local reason="${3:-config}"

	if [[ -L "$dest" ]]; then
		[[ "$(readlink "$dest")" == "$source" ]] && return 0
		omw_backup_path_for_config "$dest" "$reason"
		omw_log "Keeping existing symlink $dest unchanged." "INFO"
		return 0
	elif [[ -e "$dest" ]]; then
		omw_backup_path_for_config "$dest" "$reason"
		omw_log "Keeping existing $dest unchanged." "INFO"
		return 0
	fi

	ln -s "$source" "$dest"
}

omw_copy_if_absent_with_backup() {
	local source="$1"
	local dest="$2"
	local reason="${3:-config}"

	if [[ -e "$dest" || -L "$dest" ]]; then
		omw_backup_path_for_config "$dest" "$reason"
		omw_log "Keeping existing $dest unchanged." "INFO"
		return 0
	fi

	cp "$source" "$dest"
}

omw_append_line_with_backup() {
	local file="$1"
	local marker="$2"
	local content="$3"
	local reason="${4:-config}"

	if [[ -f "$file" ]] && grep -q "$marker" "$file"; then
		return 0
	fi
	[[ -e "$file" || -L "$file" ]] && omw_backup_path_for_config "$file" "$reason"
	printf '%s\n' "$content" >>"$file"
}

omw_extract_rpms_to_prefix() {
	local rpm_dir="$1"
	local prefix="$2"

	mkdir -p "$prefix"
	omw_log "Extracting RPMs to $prefix..." "INFO"
	pushd "$prefix" >/dev/null
	if ! find "$rpm_dir" -maxdepth 1 -name "*.rpm" -print0 | while IFS= read -r -d $'\0' rpm; do
		rpm2cpio "$rpm" | cpio -idmu --quiet
	done; then
		popd >/dev/null
		omw_log "RPM extraction failed." "ERROR"
		return 1
	fi
	popd >/dev/null
}

omw_contains_word() {
	local needle="$1"
	local haystack="$2"
	local item
	for item in $haystack; do
		[[ "$item" == "$needle" ]] && return 0
	done
	return 1
}
omw_clone_repo_once() {
	local url="$1"
	local dest="$2"
	local backup_dest=""
	local clone_log=""
	if [[ -d "$dest/.git" ]]; then
		omw_log "Repository exists: $dest" "INFO"
		return 0
	fi
	if [[ -d "$dest" ]] && find "$dest" -mindepth 1 -print -quit | grep -q .; then
		omw_log "Using existing non-git directory as an offline copy: $dest" "WARN"
		return 0
	fi
	if [[ -e "$dest" ]]; then
		backup_dest="${dest}.backup-$(date +%Y%m%d%H%M%S)"
		omw_log "Destination exists but is not a usable git repo copy: $dest; moving it to $backup_dest." "WARN"
		mv "$dest" "$backup_dest"
	fi
	local tmp_dest="${dest}.tmp-$$"
	omw_safe_rm_rf "$tmp_dest"
	clone_log=$(mktemp)
	local clone_success=false
	for ((i = 1; i <= MAX_RETRIES; i++)); do
		: >"$clone_log"
		if GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$url" "$tmp_dest" 2>"$clone_log"; then
			clone_success=true
			break
		fi
		omw_log "Git clone attempt $i failed. Retrying..." "WARN"
		omw_safe_rm_rf "$tmp_dest"
	done
	if [[ "$clone_success" == "false" ]]; then
		omw_log "Git clone failed for $url after $MAX_RETRIES attempts. Last output:" "WARN"
		cat "$clone_log" >&2
		omw_safe_rm_rf "$tmp_dest"
		rm -f "$clone_log"
		if _omw_common_fetch_github_repo_snapshot "$url" "$dest"; then
			[[ -n "$backup_dest" ]] && omw_log "Previous non-git destination was kept at $backup_dest." "WARN"
			return 0
		fi
		if [[ -n "$backup_dest" && -e "$backup_dest" && ! -e "$dest" ]]; then
			omw_log "Restoring previous non-git destination after fetch failure: $dest" "WARN"
			mv "$backup_dest" "$dest"
		fi
		return 1
	fi
	rm -f "$clone_log"
	mv "$tmp_dest" "$dest"
	[[ -n "$backup_dest" ]] && omw_log "Previous non-git destination was kept at $backup_dest." "WARN"
	return 0
}

_omw_common_github_archive_url() {
	local url="$1"
	local owner repo

	if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
		owner="${BASH_REMATCH[1]}"
		repo="${BASH_REMATCH[2]%.git}"
		printf 'https://github.com/%s/%s/archive/HEAD.tar.gz' "$owner" "$repo"
	fi
}

_omw_common_github_archive_cache_path() {
	local url="$1"
	local owner repo safe_repo

	if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
		owner="${BASH_REMATCH[1]}"
		repo="${BASH_REMATCH[2]%.git}"
		safe_repo="${repo//[^A-Za-z0-9._-]/_}"
		printf '%s/%s-%s-HEAD.tar.gz' "$PACKAGES_PATH" "$owner" "$safe_repo"
	fi
}

_omw_common_fetch_github_repo_snapshot() {
	local url="$1"
	local dest="$2"
	local archive_url archive_path

	archive_url=$(_omw_common_github_archive_url "$url")
	archive_path=$(_omw_common_github_archive_cache_path "$url")
	if [[ -z "$archive_url" || -z "$archive_path" ]]; then
		omw_log "No archive fallback is available for $url." "ERROR"
		return 1
	fi

	omw_log "Falling back to GitHub archive snapshot for $url" "WARN"
	if ! omw_download_package "$archive_url" "$archive_path"; then
		return 1
	fi
	if ! omw_extract_package "$archive_path" "$dest" 1; then
		return 1
	fi
	omw_log "Repository snapshot prepared: $dest" "SUCCESS"
}

omw_ensure_module_command() {
	if ! command -v module &>/dev/null; then
		omw_log "Environment Modules command 'module' is not available. Source your modules init script first." "ERROR"
		return 1
	fi
}
