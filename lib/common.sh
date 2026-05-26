# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_common_*.
omw_log() {
	local msg="$1"
	local level="${2:-INFO}"
	local ts
	ts=$(date +"%T")
	declare -A c=([DEBUG]=34 [INFO]=36 [WARN]=33 [ERROR]=31 [SUCCESS]=32)
	echo -e "\033[1;${c[$level]:-36}m[${ts}] [${level}] - ${msg}\033[0m" >&2
}

omw_init_globals() {
	OMW_HOME=$(cd "$OMW_HOME" && pwd)
	cd "$OMW_HOME"
	# Source environment variables if they exist
	# shellcheck disable=SC1091
	[[ -f "$OMW_HOME/env.sh" ]] && source "$OMW_HOME/env.sh"

	# Define core paths
	CONFIG_PATH="$OMW_HOME/config"
	PACKAGES_PATH="$OMW_HOME/packages"
	BUILDS_PATH="$OMW_HOME/builds"
	SOFTWARE_INSTALL_PATH="$OMW_HOME/tools/software"
	MODULEFILES_PATH="$OMW_HOME/tools/modulefiles"
	APPS_INSTALL_PATH="$OMW_HOME/apps"
	SCRIPTS_BIN_PATH="$OMW_HOME/bin"

	# Ensure core directories exist
	readonly DIRECTORIES=(
		"$CONFIG_PATH" "$PACKAGES_PATH/software" "$PACKAGES_PATH/apps"
		"$PACKAGES_PATH/config" "$BUILDS_PATH" "$SOFTWARE_INSTALL_PATH" "$MODULEFILES_PATH" "$APPS_INSTALL_PATH" "$SCRIPTS_BIN_PATH"
	)
	for dir in "${DIRECTORIES[@]}"; do
		[[ ! -d "$dir" ]] && mkdir -p "$dir"
	done

	# Load software definitions from configuration file
	local conf_file="$OMW_HOME/packages.sh"
	if [[ -f "$conf_file" ]]; then
		omw_log "Loading definitions from $conf_file" "INFO"
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
	return 0
}

_omw_common_validate_config() {
	local errors=0
	local name version versions_str deps dep dep_name dep_version app
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
		if [[ -z "${SOFTWARE_CONFIG_CMDS[$name]+set}" ]]; then
			omw_log "SOFTWARE_CONFIG_CMDS[$name] is not defined." "ERROR"
			((++errors))
		elif [[ -z "${SOFTWARE_CONFIG_CMDS[$name]}" || "${SOFTWARE_CONFIG_CMDS[$name]}" == "$placeholder" ]]; then
			omw_log "SOFTWARE_CONFIG_CMDS[$name] must be a command template or 'special'." "ERROR"
			((++errors))
		fi
		if [[ "${SOFTWARE_URLS[$name]:-}" == "$placeholder" ]]; then
			omw_log "SOFTWARE_URLS[$name] still contains the empty-field placeholder." "ERROR"
			((++errors))
		fi
		for version in $versions_str; do
			if [[ "$version" == "$placeholder" ]]; then
				omw_log "SOFTWARE_VERSIONS[$name] contains the empty-field placeholder." "ERROR"
				((++errors))
			fi
			if [[ -z "${SOFTWARE_DEPS["$name@$version"]+set}" ]]; then
				omw_log "SOFTWARE_DEPS[$name@$version] is not defined." "ERROR"
				((++errors))
				continue
			fi
			deps="${SOFTWARE_DEPS["$name@$version"]}"
			if [[ "$deps" == "$placeholder" ]]; then
				omw_log "SOFTWARE_DEPS[$name@$version] still contains the empty-field placeholder." "ERROR"
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
		[[ -n "${APP_EXECUTABLE_NAME[$app]:-}" ]] || {
			omw_log "APP_EXECUTABLE_NAME[$app] is not defined." "ERROR"
			((++errors))
		}
		[[ "${APP_EXECUTABLE_NAME[$app]:-}" != "$placeholder" ]] || {
			omw_log "APP_EXECUTABLE_NAME[$app] contains the empty-field placeholder." "ERROR"
			((++errors))
		}
	done

	if ((errors > 0)); then
		omw_log "Configuration validation failed with $errors error(s)." "ERROR"
		exit 1
	fi
}

omw_check_sys_deps() {
	omw_log "Checking system dependencies..." "INFO"
	local missing_deps=0
	for cmd in wget tar make git rpm2cpio cpio sed find nproc yumdownloader unzip pushd popd; do
		if ! command -v "$cmd" &>/dev/null; then
			omw_log "Missing command: $cmd" "ERROR"
			missing_deps=1
		fi
	done
	if ((missing_deps)); then exit 1; fi
	omw_log "System dependencies are satisfied." "SUCCESS"
	return 0
}

_omw_common_file_size() {
	local path="$1"
	if stat -c%s "$path" &>/dev/null; then
		stat -c%s "$path"
	else
		stat -f%z "$path"
	fi
}

omw_ensure_valid_cwd() {
	if ! pwd -P >/dev/null 2>&1; then
		omw_log "Current directory is no longer accessible; switching to $OMW_HOME" "WARN"
		cd "$OMW_HOME"
	fi
}

omw_safe_rm_rf() {
	local path="$1"
	omw_ensure_valid_cwd
	if [[ -z "$path" || "$path" == "/" ]]; then
		omw_log "Refusing to remove unsafe path: '${path}'" "ERROR"
		return 1
	fi
	rm -rf -- "$path"
}

omw_clear_directory_contents() {
	local path="$1"
	if [[ -z "$path" || "$path" == "/" ]]; then
		omw_log "Refusing to clear unsafe directory: '${path}'" "ERROR"
		return 1
	fi
	mkdir -p "$path"
	find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
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

omw_safe_link_with_backup() {
	local source="$1"
	local dest="$2"
	local reason="${3:-config}"
	local current_target

	if [[ -L "$dest" ]]; then
		current_target=$(readlink "$dest")
		[[ "$current_target" == "$source" ]] && return 0
		omw_backup_path_for_config "$dest" "$reason"
		rm -f "$dest"
	elif [[ -e "$dest" ]]; then
		omw_backup_path_for_config "$dest" "$reason"
		rm -rf "$dest"
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
	if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$url" "$tmp_dest" 2>"$clone_log"; then
		omw_log "Git clone failed for $url. Last output:" "WARN"
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
		printf '%s/config/%s-%s-HEAD.tar.gz' "$PACKAGES_PATH" "$owner" "$safe_repo"
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

# Helper function to get the URL for a specific software version
omw_get_software_url() {
	local appname="$1"
	local version="$2"
	local url_template="${SOFTWARE_URLS[$appname]}"
	# Replace the {VERSION} placeholder with the actual version number
	echo "${url_template//\{VERSION\}/$version}"
}

omw_download_package() {
	local url="$1"
	local dest="$2"
	if [[ -z "$url" || -z "$dest" ]]; then
		omw_log "omw_download_package requires both URL and destination." "ERROR"
		return 1
	fi
	# Check if package already exists and is reasonably sized
	if [[ -f "$dest" && $(_omw_common_file_size "$dest") -gt 100 ]]; then
		omw_log "Package exists: $(basename "$dest")" "INFO"
		return 0
	fi
	omw_log "Downloading $(basename "$dest") from $url" "INFO"
	mkdir -p "$(dirname "$dest")"
	local tmp_dest
	tmp_dest=$(mktemp "$(dirname "$dest")/.tmp.$(basename "$dest").XXXXXX")
	local log_file
	log_file=$(mktemp)
	for ((i = 1; i <= MAX_RETRIES; i++)); do
		: >"$log_file"
		if wget --tries=1 --timeout="$DOWNLOAD_TIMEOUT" -o "$log_file" -O "$tmp_dest" "$url" && [[ $(_omw_common_file_size "$tmp_dest") -gt 100 ]]; then
			mv -f "$tmp_dest" "$dest"
			rm -f "$log_file"
			omw_log "Download successful." "SUCCESS"
			return 0
		fi
		omw_log "Download attempt $i failed. Retrying..." "WARN"
	done
	omw_log "Failed to download $url. Last attempt omw_log:" "ERROR"
	cat "$log_file" >&2
	rm -f "$log_file" "$tmp_dest"
	return 1
}

omw_extract_package() {
	local pkg="$1"
	local dest="$2"
	local strip="${3:-1}"
	if [[ ! -f "$pkg" ]]; then
		omw_log "Package not found: $pkg" "ERROR"
		return 1
	fi
	omw_log "Extracting $(basename "$pkg") to $(basename "$dest")" "INFO"
	mkdir -p "$(dirname "$dest")"
	local tmp_dest
	tmp_dest=$(mktemp -d "$(dirname "$dest")/.extract.$(basename "$dest").XXXXXX")
	case "$pkg" in
	*.tar.gz | *.tgz) tar -xzf "$pkg" -C "$tmp_dest" --strip-components="$strip" ;;
	*.tar.xz) tar -xJf "$pkg" -C "$tmp_dest" --strip-components="$strip" ;;
	*.tar.bz2) tar -xjf "$pkg" -C "$tmp_dest" --strip-components="$strip" ;;
	*.zip) unzip -q "$pkg" -d "$tmp_dest" ;;
	*)
		omw_log "Unsupported format: $pkg" "ERROR"
		omw_safe_rm_rf "$tmp_dest"
		return 1
		;;
	esac
	if [[ -z "$(ls -A "$tmp_dest")" ]]; then
		omw_log "Extraction failed: destination is empty." "ERROR"
		omw_safe_rm_rf "$tmp_dest"
		return 1
	fi
	omw_safe_rm_rf "$dest"
	mkdir -p "$(dirname "$dest")"
	mv "$tmp_dest" "$dest"
	omw_log "Extraction successful." "SUCCESS"
}

omw_archive_is_readable() {
	local pkg="$1"

	case "$pkg" in
	*.tar.gz | *.tgz) tar -tzf "$pkg" >/dev/null ;;
	*.tar.xz) tar -tJf "$pkg" >/dev/null ;;
	*.tar.bz2) tar -tjf "$pkg" >/dev/null ;;
	*.zip) unzip -tq "$pkg" >/dev/null ;;
	*) return 0 ;;
	esac
}
