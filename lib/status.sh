# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_status_*.
_omw_status_strip_version_prefix() {
	local version="$1"
	version="${version#release-}"
	version="${version#v}"
	version="${version%-stable}"
	printf '%s' "$version"
}

_omw_status_version_major() {
	local version="$1"
	version=$(_omw_status_strip_version_prefix "$version")
	printf '%s' "${version%%.*}"
}

_omw_status_version_series() {
	local version="$1"
	version=$(_omw_status_strip_version_prefix "$version")
	if [[ "$version" =~ ^([0-9]+\.[0-9]+) ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
	else
		_omw_status_version_major "$version"
	fi
}

_omw_status_filter_versions_by_major() {
	local current="$1"
	local current_major candidate
	current_major=$(_omw_status_version_major "$current")
	while IFS= read -r candidate; do
		[[ -n "$candidate" ]] || continue
		[[ "$(_omw_status_version_major "$candidate")" == "$current_major" ]] && printf '%s\n' "$candidate"
	done
}

_omw_status_filter_versions_by_series() {
	local current="$1"
	local current_series candidate
	current_series=$(_omw_status_version_series "$current")
	while IFS= read -r candidate; do
		[[ -n "$candidate" ]] || continue
		[[ "$(_omw_status_version_series "$candidate")" == "$current_series" ]] && printf '%s\n' "$candidate"
	done
}

_omw_status_filter_openssl_compat_versions() {
	local current="$1"
	local candidate
	while IFS= read -r candidate; do
		[[ -n "$candidate" ]] || continue
		if [[ "$current" == 1.1.1* ]]; then
			[[ "$candidate" == 1.1.1* ]] && printf '%s\n' "$candidate"
		else
			[[ "$(_omw_status_version_major "$candidate")" == "$(_omw_status_version_major "$current")" ]] && printf '%s\n' "$candidate"
		fi
	done
}

_omw_status_version_gt() {
	local candidate="$1"
	local current="$2"
	[[ -n "$candidate" && -n "$current" && "$candidate" != "$current" ]] || return 1
	[[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n 1)" == "$candidate" ]]
}

_omw_status_fetch_url() {
	local url="$1"
	wget -q -T 20 -O - "$url"
}

_omw_status_latest_from_github() {
	local url="$1"
	local owner repo api latest response

	[[ "$url" =~ github\.com/([^/]+)/([^/]+)/ ]] || return 2
	owner="${BASH_REMATCH[1]}"
	repo="${BASH_REMATCH[2]%.git}"
	api="https://api.github.com/repos/$owner/$repo/releases/latest"
	response=$(_omw_status_fetch_url "$api" 2>/dev/null || true)
	latest=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$response" | head -n 1)
	if [[ -z "$latest" ]]; then
		api="https://api.github.com/repos/$owner/$repo/tags"
		response=$(_omw_status_fetch_url "$api") || return 3
		latest=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$response" | head -n 1)
	fi
	[[ -n "$latest" ]] || return 3
	_omw_status_strip_version_prefix "$latest"
}

_omw_status_latest_from_directory_listing() {
	local url="$1"
	local pattern="$2"
	local response latest
	response=$(_omw_status_fetch_url "$url") || return 3
	latest=$(sed -n "s|.*$pattern.*|\\1|p" <<<"$response" | sort -V | tail -n 1)
	[[ -n "$latest" ]] || return 3
	printf '%s' "$latest"
}

_omw_status_latest_from_directory_listing_same_major() {
	local url="$1"
	local pattern="$2"
	local current="$3"
	local response latest
	response=$(_omw_status_fetch_url "$url") || return 3
	latest=$(sed -n "s|.*$pattern.*|\\1|p" <<<"$response" |
		_omw_status_filter_versions_by_major "$current" |
		sort -V |
		tail -n 1)
	[[ -n "$latest" ]] || return 3
	printf '%s' "$latest"
}

_omw_status_latest_from_directory_listing_same_series() {
	local url="$1"
	local pattern="$2"
	local current="$3"
	local response latest
	response=$(_omw_status_fetch_url "$url") || return 3
	latest=$(sed -n "s|.*$pattern.*|\\1|p" <<<"$response" |
		_omw_status_filter_versions_by_series "$current" |
		sort -V |
		tail -n 1)
	[[ -n "$latest" ]] || return 3
	printf '%s' "$latest"
}

_omw_status_latest_openssl_version() {
	local current="$1"
	local response latest
	if [[ "$current" == 1.1.1* ]]; then
		latest=$(git ls-remote --tags https://github.com/openssl/openssl.git "refs/tags/OpenSSL_1_1_1*" 2>/dev/null |
			sed -n 's|.*/OpenSSL_1_1_1\([a-z]\+\)\(\^{}\)\?$|1.1.1\1|p' |
			sort -V |
			tail -n 1)
		[[ -n "$latest" ]] || return 3
		printf '%s' "$latest"
		return 0
	fi
	response=$(_omw_status_fetch_url "https://www.openssl.org/source/") || return 3
	latest=$(sed -n 's|.*openssl-\([0-9][0-9A-Za-z.]*\)\.tar.*|\1|p' <<<"$response" |
		_omw_status_filter_openssl_compat_versions "$current" |
		sort -V |
		tail -n 1)
	[[ -n "$latest" ]] || return 3
	printf '%s' "$latest"
}

_omw_status_latest_software_version() {
	local name="$1"
	local current="$2"
	local url
	url=$(omw_get_software_url "$name" "$current")

	case "$url" in
	*github.com*)
		_omw_status_latest_from_github "$url"
		;;
	*python.org/ftp/python/*)
		_omw_status_latest_from_directory_listing_same_series "https://www.python.org/ftp/python/" 'href="\([0-9][0-9.]*\)/"' "$current"
		;;
	*ftp.gnu.org/gnu/ncurses/*)
		_omw_status_latest_from_directory_listing "https://ftp.gnu.org/gnu/ncurses/" 'ncurses-\([0-9][0-9.]*\)\.tar'
		;;
	*ftp.gnu.org/gnu/gcc/gcc-*)
		_omw_status_latest_from_directory_listing_same_major "https://ftp.gnu.org/gnu/gcc/" 'gcc-\([0-9][0-9.]*\)/' "$current"
		;;
	*openssl.org/source/*)
		_omw_status_latest_openssl_version "$current"
		;;
	*lua.org/ftp/*)
		_omw_status_latest_from_directory_listing "https://www.lua.org/ftp/" 'lua-\([0-9][0-9.]*\)\.tar'
		;;
	*unofficial-builds.nodejs.org/download/release/*)
		_omw_status_latest_from_directory_listing_same_major "https://unofficial-builds.nodejs.org/download/release/" 'href="v\([0-9][0-9.]*\)/"' "$current"
		;;
	*sourceforge.net/projects/zsh/files/zsh/*)
		_omw_status_latest_from_directory_listing_same_major "https://sourceforge.net/projects/zsh/files/zsh/" '/zsh/\([0-9][0-9.]*\)/' "$current"
		;;
	*)
		return 2
		;;
	esac
}

_omw_status_latest_app_version() {
	local name="$1"
	local url
	url=$(omw_get_app_url "$name" 2>/dev/null || true)

	case "$url" in
	*github.com*)
		_omw_status_latest_from_github "$url"
		;;
	*)
		return 2
		;;
	esac
}

_omw_status_latest_npm_version() {
	local package_name="$1"
	local registry encoded response latest
	registry="${OMW_NPM_REGISTRY_URL:-${OMW_COC_REGISTRY_URL:-https://registry.npmjs.org}}"
	encoded="${package_name//@/%40}"
	encoded="${encoded//\//%2f}"
	response=$(_omw_status_fetch_url "${registry%/}/$encoded/latest") || return 3
	latest=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$response" | head -n 1)
	[[ -n "$latest" ]] || return 3
	printf '%s' "$latest"
}

_omw_status_update_header() {
	local header
	printf -v header '%-20s %-20s %-20s %-12s %s' "Name" "Current" "Latest" "Status" "Detail"
	_omw_status_ui_color "1;37" "$header"
	printf '\n'
}

_omw_status_update_color_code() {
	case "$1" in
	current) printf '32' ;;
	available) printf '1;36' ;;
	unsupported) printf '1;33' ;;
	error | missing) printf '1;31' ;;
	*) printf '0' ;;
	esac
}

_omw_status_update_row() {
	local name="$1"
	local current="$2"
	local latest="$3"
	local status="$4"
	local detail="${5:-}"
	local row color

	printf -v row '%-20s %-20s %-20s %-12s %s' "$name" "$current" "$latest" "$status" "$detail"
	color=$(_omw_status_update_color_code "$status")
	_omw_status_ui_color "$color" "$row"
	printf '\n'
	((++OMW_UPDATE_CHECKED))
	case "$status" in
	current) ((++OMW_UPDATE_CURRENT)) ;;
	available) ((++OMW_UPDATE_AVAILABLE)) ;;
	unsupported) ((++OMW_UPDATE_UNSUPPORTED)) ;;
	error) ((++OMW_UPDATE_ERRORS)) ;;
	missing) ((++OMW_UPDATE_MISSING)) ;;
	esac
}

_omw_status_check_version() {
	local name="$1"
	local current="$2"
	local detail="$3"
	local resolver="$4"
	shift 4
	local latest rc

	if latest=$("$resolver" "$@"); then
		if _omw_status_version_gt "$latest" "$current"; then
			_omw_status_update_row "$name" "$current" "$latest" available "$detail"
		else
			_omw_status_update_row "$name" "$current" "$latest" current "$detail"
		fi
	else
		rc=$?
		if ((rc == 2)); then
			_omw_status_update_row "$name" "$current" "-" unsupported "$detail; no checker"
		else
			_omw_status_update_row "$name" "$current" "-" error "$detail; request or parse failed"
		fi
	fi
}

_omw_status_check_vim_plugins() {
	local list_file plugin_root name url branch local_dir local_head remote_ref remote_head
	list_file="$(omw_config_source_target_dir "vim")/plugins.list"
	plugin_root="$(omw_config_source_target_dir "vim")/vim9/pack/omw/start"

	_omw_status_ui_section "Vim plugin updates"
	_omw_status_update_header
	if [[ ! -f "$list_file" ]]; then
		_omw_status_update_row "plugins.list" "-" "-" missing "Vim plugin declarations"
		return 0
	fi
	while IFS='|' read -r name url branch || [[ -n "$name$url$branch" ]]; do
		[[ -z "$name" || "$name" == \#* ]] && continue
		local_dir="$plugin_root/$name"
		if [[ ! -d "$local_dir/.git" ]]; then
			_omw_status_update_row "$name" "-" "-" missing "${branch:-HEAD}"
			continue
		fi
		local_head=$(cd "$local_dir" && git rev-parse HEAD 2>/dev/null) || {
			_omw_status_update_row "$name" "-" "-" error "invalid local repository"
			continue
		}
		remote_ref="${branch:+refs/heads/$branch}"
		remote_ref="${remote_ref:-HEAD}"
		remote_head=$(git ls-remote "$url" "$remote_ref" 2>/dev/null | awk 'NR == 1 { print $1 }') || true
		if [[ -z "$remote_head" ]]; then
			_omw_status_update_row "$name" "${local_head:0:10}" "-" error "remote $remote_ref unavailable"
		elif [[ "$local_head" == "$remote_head" ]]; then
			_omw_status_update_row "$name" "${local_head:0:10}" "${remote_head:0:10}" current "$remote_ref"
		else
			_omw_status_update_row "$name" "${local_head:0:10}" "${remote_head:0:10}" available "$remote_ref"
		fi
	done <"$list_file"
}

_omw_status_check_coc_extensions() {
	local list_file spec name version
	list_file="$(omw_config_source_target_dir "vim")/coc/extensions.list"

	_omw_status_ui_section "Vim Coc extension updates"
	_omw_status_update_header
	if [[ ! -f "$list_file" ]]; then
		_omw_status_update_row "extensions.list" "-" "-" missing "Coc extension declarations"
		return 0
	fi
	while IFS= read -r spec || [[ -n "$spec" ]]; do
		[[ -z "$spec" || "$spec" == \#* ]] && continue
		if [[ "$spec" =~ ^(@[^/]+/[^@]+|[^@]+)@([^@]+)$ ]]; then
			name="${BASH_REMATCH[1]}"
			version="${BASH_REMATCH[2]}"
			_omw_status_check_version "$name" "$version" "npm latest" _omw_status_latest_npm_version "$name"
		else
			_omw_status_update_row "$spec" "-" "-" error "invalid fixed version"
		fi
	done <"$list_file"
}

omw_check_updates() {
	local name version versions_str
	local -A listed_software=()

	if ! command -v wget &>/dev/null; then
		omw_log "wget is required for 'update check'." "ERROR"
		return 1
	fi
	if ! command -v git &>/dev/null; then
		omw_log "git is required for Vim plugin update checks." "ERROR"
		return 1
	fi
	_omw_status_ui_init_color
	OMW_UPDATE_CHECKED=0
	OMW_UPDATE_CURRENT=0
	OMW_UPDATE_AVAILABLE=0
	OMW_UPDATE_UNSUPPORTED=0
	OMW_UPDATE_ERRORS=0
	OMW_UPDATE_MISSING=0

	_omw_status_ui_section "Software updates"
	_omw_status_update_header
	for name in "${SOFTWARE_LIST[@]}"; do
		listed_software["$name"]=1
		versions_str="${SOFTWARE_VERSIONS[$name]:-}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			_omw_status_check_version "$name" "$version" "source release" _omw_status_latest_software_version "$name" "$version"
		done
	done
	for name in "${!SOFTWARE_VERSIONS[@]}"; do
		[[ -n "${listed_software[$name]:-}" ]] && continue
		for version in ${SOFTWARE_VERSIONS[$name]}; do
			_omw_status_check_version "$name" "$version" "extra source release" _omw_status_latest_software_version "$name" "$version"
		done
	done

	_omw_status_ui_section "App updates"
	_omw_status_update_header
	for name in "${APP_LIST[@]}"; do
		version="${APP_VERSIONS[$name]:-}"
		[[ -z "$version" ]] && continue
		_omw_status_check_version "$name" "$version" "upstream release" _omw_status_latest_app_version "$name"
	done

	_omw_status_ui_section "Node package updates"
	_omw_status_update_header
	for name in "${NODE_PACKAGE_LIST[@]}"; do
		version="${NODE_PACKAGE_VERSIONS[$name]:-}"
		_omw_status_check_version "$name" "$version" "${NODE_PACKAGE_NAMES[$name]} via npm" _omw_status_latest_npm_version "${NODE_PACKAGE_NAMES[$name]}"
	done
	for name in "${NODE_CACHE_PACKAGE_LIST[@]}"; do
		version="${NODE_CACHE_PACKAGE_VERSIONS[$name]:-}"
		_omw_status_check_version "$name" "$version" "${NODE_CACHE_PACKAGE_NAMES[$name]} cache-only" _omw_status_latest_npm_version "${NODE_CACHE_PACKAGE_NAMES[$name]}"
	done

	_omw_status_check_coc_extensions
	_omw_status_check_vim_plugins

	printf '\nChecked: %d, current: %d, updates: %d, unsupported: %d, errors: %d, missing: %d\n' \
		"$OMW_UPDATE_CHECKED" "$OMW_UPDATE_CURRENT" "$OMW_UPDATE_AVAILABLE" "$OMW_UPDATE_UNSUPPORTED" "$OMW_UPDATE_ERRORS" "$OMW_UPDATE_MISSING"
	if ((OMW_UPDATE_ERRORS > 0)); then
		omw_log "Update check completed with upstream or parsing errors; review error rows before changing pinned versions." "WARN"
	elif ((OMW_UPDATE_AVAILABLE > 0)); then
		omw_log "New versions are available. Update packages.sh intentionally, then build/install the target." "WARN"
	else
		omw_log "No newer versions detected for supported sources." "SUCCESS"
	fi
}

_omw_status_ui_supports_color() {
	if [[ -n "${OMW_STATUS_COLOR_ENABLED:-}" ]]; then
		[[ "$OMW_STATUS_COLOR_ENABLED" == "true" ]]
		return
	fi
	[[ -t 1 && -z "${NO_COLOR:-}" && "${OMW_NO_COLOR:-false}" != "true" ]]
}

_omw_status_ui_init_color() {
	if [[ -t 1 && -z "${NO_COLOR:-}" && "${OMW_NO_COLOR:-false}" != "true" ]]; then
		OMW_STATUS_COLOR_ENABLED=true
	else
		OMW_STATUS_COLOR_ENABLED=false
	fi
}

_omw_status_ui_color() {
	local code="$1"
	local text="$2"
	if _omw_status_ui_supports_color; then
		printf '\033[%sm%s\033[0m' "$code" "$text"
	else
		printf '%s' "$text"
	fi
}

_omw_status_ui_status() {
	local status="$1"
	case "$status" in
	installed) _omw_status_ui_color "1;32" "installed" ;;
	legacy) _omw_status_ui_color "1;36" "legacy" ;;
	cached) _omw_status_ui_color "1;32" "cached" ;;
	partial) _omw_status_ui_color "1;33" "partial" ;;
	missing) _omw_status_ui_color "1;31" "missing" ;;
	available) _omw_status_ui_color "1;36" "available" ;;
	current) _omw_status_ui_color "1;32" "current" ;;
	unsupported) _omw_status_ui_color "1;33" "unsupported" ;;
	error) _omw_status_ui_color "1;31" "error" ;;
	*) printf '%s' "$status" ;;
	esac
}

_omw_status_ui_section() {
	local title="$1"
	printf '\n%s\n' "$(_omw_status_ui_color "1;36" "$title")"
	printf '%*s\n' "${#title}" "" | tr ' ' '-'
}

_omw_status_software_install_status() {
	local name="$1"
	local version="$2"
	local prefix modulefile actual
	prefix=$(omw_software_prefix "$name" "$version")
	modulefile=$(omw_software_modulefile "$name" "$version")
	if [[ -d "$prefix" && -f "$modulefile" ]]; then
		actual=installed
	elif [[ -d "$prefix" || -f "$modulefile" ]]; then
		actual=partial
	else
		actual=available
	fi
	omw_receipt_state software "$name" "$version" "$actual"
}

_omw_status_config_install_status() {
	local target="$1"
	local actual
	case "$target" in
	tmux)
		[[ -L "$HOME/.tmux.conf" && -L "$HOME/.tmux.conf.local" ]] && actual=installed || actual=available
		;;
	vim)
		[[ -f "$CONFIG_RELEASE_PATH/vim/vimrc.default" && -f "$HOME/.vimrc" ]] && actual=installed || actual=available
		;;
	zsh)
		[[ -L "$HOME/.oh-my-zsh" && -f "$HOME/.zshrc" ]] && actual=installed || actual=available
		;;
	*)
		actual=available
		;;
	esac
	omw_receipt_state config "$target" "$OMW_VERSION" "$actual"
}

omw_print_status() {
	local show_all="${1:-true}"
	local name version versions_str status pkg cmd
	local -A listed_software=()

	printf '%s\n' "$(_omw_status_ui_color "1;37" "OMW package view")"
	printf 'Home: %s\n' "$OMW_HOME"

	_omw_status_ui_section "Source builds"
	printf '%-14s %-14s %-12s %-10s %s\n' "Name" "Version" "State" "Package" "Command"
	for name in "${SOFTWARE_LIST[@]}"; do
		listed_software["$name"]=1
		versions_str="${SOFTWARE_VERSIONS[$name]:-}"
		if [[ -z "$versions_str" ]]; then
			printf '%-14s %-14s %-12s %-10s %s\n' "$name" "-" "$(_omw_status_ui_status missing)" "-" "missing version definition"
			continue
		fi
		for version in $versions_str; do
			status=$(_omw_status_software_install_status "$name" "$version")
			[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "legacy" && "$status" != "partial" ]] && continue
			pkg="-"
			if omw_software_package_path "$name" "$version" >/dev/null; then
				pkg=$(omw_software_package_path "$name" "$version")
				[[ -f "$pkg" ]] && pkg="cached" || pkg="needed"
			fi
			cmd="./omw build $name@$version"
			printf '%-14s %-14s %-12s %-10s %s\n' "$name" "$version" "$(_omw_status_ui_status "$status")" "$pkg" "$cmd"
		done
	done
	for name in "${!SOFTWARE_VERSIONS[@]}"; do
		[[ -n "${listed_software[$name]:-}" ]] && continue
		versions_str="${SOFTWARE_VERSIONS[$name]:-}"
		for version in $versions_str; do
			status=$(_omw_status_software_install_status "$name" "$version")
			[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "legacy" && "$status" != "partial" ]] && continue
			pkg="-"
			if omw_software_package_path "$name" "$version" >/dev/null; then
				pkg=$(omw_software_package_path "$name" "$version")
				[[ -f "$pkg" ]] && pkg="cached" || pkg="needed"
			fi
			cmd="./omw build $name@$version (extra)"
			printf '%-14s %-14s %-12s %-10s %s\n' "$name" "$version" "$(_omw_status_ui_status "$status")" "$pkg" "$cmd"
		done
	done

	_omw_status_ui_section "Prebuilt apps"
	printf '%-14s %-14s %-12s %-10s %s\n' "Name" "Version" "State" "Package" "Command"
	for name in "${APP_LIST[@]}"; do
		version="${APP_VERSIONS[$name]:-}"
		url=$(omw_get_app_url "$name" 2>/dev/null || true)
		cmd="${APP_EXECUTABLE_NAME[$name]:-}"
		if ! omw_app_definition_ready "$name"; then
			printf '%-14s %-14s %-12s %-10s %s\n' "$name" "-" "$(_omw_status_ui_status missing)" "-" "incomplete definition"
			continue
		fi
		status=$(omw_app_install_status "$name")
		[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "legacy" && "$status" != "partial" ]] && continue
		pkg=$(omw_app_package_path "$url")
		[[ -f "$pkg" ]] && pkg="cached" || pkg="needed"
		cmd="./omw app install $name"
		printf '%-14s %-14s %-12s %-10s %s\n' "$name" "$version" "$(_omw_status_ui_status "$status")" "$pkg" "$cmd"
	done

	_omw_status_ui_section "Node packages"
	printf '%-14s %-24s %-14s %-12s %-10s %s\n' "Alias" "Package" "Node" "State" "Cache" "Command"
	for name in "${NODE_PACKAGE_LIST[@]}"; do
		version="${NODE_PACKAGE_VERSIONS[$name]:-}"
		url="${NODE_PACKAGE_NAMES[$name]:-}"
		cmd="${NODE_PACKAGE_NODE_VERSIONS[$name]:-}"
		if [[ -z "$version" || -z "$url" || -z "$cmd" ]]; then
			printf '%-14s %-24s %-14s %-12s %-10s %s\n' "$name" "-" "-" "$(_omw_status_ui_status missing)" "-" "incomplete definition"
			continue
		fi
		status=$(omw_node_package_status "$name")
		[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "legacy" && "$status" != "partial" ]] && continue
		if omw_node_cache_available; then
			pkg="cached"
		else
			pkg="needed"
		fi
		printf '%-14s %-24s %-14s %-12s %-10s %s\n' "$name" "$url@$version" "$cmd" "$(_omw_status_ui_status "$status")" "$pkg" "./omw node install $name"
	done
	for name in "${NODE_CACHE_PACKAGE_LIST[@]}"; do
		version="${NODE_CACHE_PACKAGE_VERSIONS[$name]:-}"
		url="${NODE_CACHE_PACKAGE_NAMES[$name]:-}"
		cmd="${NODE_CACHE_PACKAGE_NODE_VERSIONS[$name]:-}"
		if [[ -z "$version" || -z "$url" || -z "$cmd" ]]; then
			printf '%-14s %-24s %-14s %-12s %-10s %s\n' "$name" "-" "-" "$(_omw_status_ui_status missing)" "-" "incomplete cache-only definition"
			continue
		fi
		status=$(omw_node_cache_package_status "$name")
		[[ "$show_all" == "false" && "$status" != "cached" ]] && continue
		if omw_node_cache_available; then
			pkg="cached"
		else
			pkg="needed"
		fi
		printf '%-14s %-24s %-14s %-12s %-10s %s\n' "$name" "$url@$version" "$cmd" "$(_omw_status_ui_status "$status")" "$pkg" "./omw node restore-cache"
	done

	_omw_status_ui_section "Shell configs"
	printf '%-14s %-14s %-12s %s\n' "Name" "Target" "State" "Command"
	for name in "${CONFIG_TARGET_LIST[@]}"; do
		status=$(_omw_status_config_install_status "$name")
		[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "legacy" && "$status" != "partial" ]] && continue
		printf '%-14s %-14s %-12s %s\n' "$name" "$name" "$(_omw_status_ui_status "$status")" "./omw config $name"
	done

	printf '\nInstall commands: %s, %s, %s\n' \
		"$(_omw_status_ui_color "36" "./omw build <name[@version]>")" \
		"$(_omw_status_ui_color "36" "./omw app install <app>")" \
		"$(_omw_status_ui_color "36" "./omw node install <alias>")"
	printf 'Full setup: %s\n' "$(_omw_status_ui_color "36" "./omw all")"
}
