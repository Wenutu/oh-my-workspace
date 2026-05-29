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

_omw_status_filter_versions_by_major() {
	local current="$1"
	local current_major candidate
	current_major=$(_omw_status_version_major "$current")
	while IFS= read -r candidate; do
		[[ -n "$candidate" ]] || continue
		[[ "$(_omw_status_version_major "$candidate")" == "$current_major" ]] && printf '%s\n' "$candidate"
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
	local owner repo api latest

	if [[ "$url" =~ github\.com/([^/]+)/([^/]+)/ ]]; then
		owner="${BASH_REMATCH[1]}"
		repo="${BASH_REMATCH[2]}"
		api="https://api.github.com/repos/$owner/$repo/releases/latest"
		latest=$(_omw_status_fetch_url "$api" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)
		if [[ -z "$latest" ]]; then
			api="https://api.github.com/repos/$owner/$repo/tags"
			latest=$(_omw_status_fetch_url "$api" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)
		fi
		_omw_status_strip_version_prefix "$latest"
	fi
}

_omw_status_latest_from_directory_listing() {
	local url="$1"
	local pattern="$2"
	(_omw_status_fetch_url "$url" || true) |
		sed -n "s|.*$pattern.*|\\1|p" |
		sort -V |
		tail -n 1
}

_omw_status_latest_from_directory_listing_same_major() {
	local url="$1"
	local pattern="$2"
	local current="$3"
	(_omw_status_fetch_url "$url" || true) |
		sed -n "s|.*$pattern.*|\\1|p" |
		_omw_status_filter_versions_by_major "$current" |
		sort -V |
		tail -n 1
}

_omw_status_latest_openssl_version() {
	local current="$1"
	(_omw_status_fetch_url "https://www.openssl.org/source/" || true) |
		sed -n 's|.*openssl-\([0-9][0-9A-Za-z.]*\)\.tar.*|\1|p' |
		_omw_status_filter_openssl_compat_versions "$current" |
		sort -V |
		tail -n 1
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
		_omw_status_latest_from_directory_listing_same_major "https://www.python.org/ftp/python/" 'href="\([0-9][0-9.]*\)/"' "$current"
		;;
	*ftp.gnu.org/gnu/ncurses/*)
		_omw_status_latest_from_directory_listing "https://ftp.gnu.org/gnu/ncurses/" 'ncurses-\([0-9][0-9.]*\)\.tar'
		;;
	*openssl.org/source/*)
		_omw_status_latest_openssl_version "$current"
		;;
	*lua.org/ftp/*)
		_omw_status_latest_from_directory_listing "https://www.lua.org/ftp/" 'lua-\([0-9][0-9.]*\)\.tar'
		;;
	*sourceforge.net/projects/zsh/files/zsh/*)
		_omw_status_latest_from_directory_listing_same_major "https://sourceforge.net/projects/zsh/files/zsh/" '/zsh/\([0-9][0-9.]*\)/' "$current"
		;;
	*)
		printf ''
		;;
	esac
}

_omw_status_latest_app_version() {
	local name="$1"
	local url="${APP_URLS[$name]:-}"

	case "$url" in
	*github.com*)
		_omw_status_latest_from_github "$url"
		;;
	*)
		printf ''
		;;
	esac
}

omw_check_updates() {
	local name version versions_str latest checked=0 updates=0 unsupported=0
	local -A listed_software=()

	if ! command -v wget &>/dev/null; then
		omw_log "wget is required for --check-updates." "ERROR"
		return 1
	fi

	_omw_status_ui_section "Software updates"
	printf '%-14s %-14s %-14s %s\n' "Name" "Current" "Latest" "Status"
	for name in "${SOFTWARE_LIST[@]}"; do
		listed_software["$name"]=1
		versions_str="${SOFTWARE_VERSIONS[$name]:-}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			latest=$(_omw_status_latest_software_version "$name" "$version")
			if [[ -z "$latest" ]]; then
				printf '%-14s %-14s %-14s %s\n' "$name" "$version" "-" "unsupported source"
				((++unsupported))
			elif _omw_status_version_gt "$latest" "$version"; then
				printf '%-14s %-14s %-14s %s\n' "$name" "$version" "$latest" "$(_omw_status_ui_status available)"
				((++updates))
			else
				printf '%-14s %-14s %-14s %s\n' "$name" "$version" "$latest" "current"
			fi
			((++checked))
		done
	done
	for name in "${!SOFTWARE_VERSIONS[@]}"; do
		[[ -n "${listed_software[$name]:-}" ]] && continue
		for version in ${SOFTWARE_VERSIONS[$name]}; do
			latest=$(_omw_status_latest_software_version "$name" "$version")
			if [[ -z "$latest" ]]; then
				printf '%-14s %-14s %-14s %s\n' "$name" "$version" "-" "unsupported source"
				((++unsupported))
			elif _omw_status_version_gt "$latest" "$version"; then
				printf '%-14s %-14s %-14s %s\n' "$name" "$version" "$latest" "$(_omw_status_ui_status available)"
				((++updates))
			else
				printf '%-14s %-14s %-14s %s\n' "$name" "$version" "$latest" "current"
			fi
			((++checked))
		done
	done

	_omw_status_ui_section "App updates"
	printf '%-14s %-14s %-14s %s\n' "Name" "Current" "Latest" "Status"
	for name in "${APP_LIST[@]}"; do
		version="${APP_VERSIONS[$name]:-}"
		[[ -z "$version" ]] && continue
		latest=$(_omw_status_latest_app_version "$name")
		if [[ -z "$latest" ]]; then
			printf '%-14s %-14s %-14s %s\n' "$name" "$version" "-" "unsupported source"
			((++unsupported))
		elif _omw_status_version_gt "$latest" "$version"; then
			printf '%-14s %-14s %-14s %s\n' "$name" "$version" "$latest" "$(_omw_status_ui_status available)"
			((++updates))
		else
			printf '%-14s %-14s %-14s %s\n' "$name" "$version" "$latest" "current"
		fi
		((++checked))
	done

	printf '\nChecked: %d, updates: %d, unsupported: %d\n' "$checked" "$updates" "$unsupported"
	if ((updates > 0)); then
		omw_log "New versions are available. Update packages.sh intentionally, then build/install the target." "WARN"
	else
		omw_log "No newer versions detected for supported sources." "SUCCESS"
	fi
}

_omw_status_ui_supports_color() {
	[[ -t 1 && -z "${NO_COLOR:-}" ]]
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
	cached) _omw_status_ui_color "1;32" "cached" ;;
	partial) _omw_status_ui_color "1;33" "partial" ;;
	missing) _omw_status_ui_color "1;31" "missing" ;;
	available) _omw_status_ui_color "1;36" "available" ;;
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
	local prefix modulefile
	prefix=$(omw_software_prefix "$name" "$version")
	modulefile=$(omw_software_modulefile "$name" "$version")
	if [[ -d "$prefix" && -f "$modulefile" ]]; then
		printf 'installed'
	elif [[ -d "$prefix" || -f "$modulefile" ]]; then
		printf 'partial'
	else
		printf 'available'
	fi
}

_omw_status_config_install_status() {
	local target="$1"
	case "$target" in
	tmux)
		[[ -d "$CONFIG_PATH/tmux/.tmux" || -L "$HOME/.tmux.conf" ]] && printf 'installed' || printf 'available'
		;;
	vim)
		[[ -d "$CONFIG_PATH/vim/vim9" && -f "$HOME/.vimrc" ]] && printf 'installed' || printf 'available'
		;;
	zsh)
		[[ -d "$CONFIG_PATH/zsh/.oh-my-zsh" || -L "$HOME/.oh-my-zsh" ]] && printf 'installed' || printf 'available'
		;;
	*)
		printf 'available'
		;;
	esac
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
			[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "partial" ]] && continue
			pkg="-"
			if omw_software_package_path "$name" "$version" >/dev/null; then
				pkg=$(omw_software_package_path "$name" "$version")
				[[ -f "$pkg" ]] && pkg="cached" || pkg="needed"
			fi
			cmd="./omw --build $name@$version"
			printf '%-14s %-14s %-12s %-10s %s\n' "$name" "$version" "$(_omw_status_ui_status "$status")" "$pkg" "$cmd"
		done
	done
	for name in "${!SOFTWARE_VERSIONS[@]}"; do
		[[ -n "${listed_software[$name]:-}" ]] && continue
		versions_str="${SOFTWARE_VERSIONS[$name]:-}"
		for version in $versions_str; do
			status=$(_omw_status_software_install_status "$name" "$version")
			[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "partial" ]] && continue
			pkg="-"
			if omw_software_package_path "$name" "$version" >/dev/null; then
				pkg=$(omw_software_package_path "$name" "$version")
				[[ -f "$pkg" ]] && pkg="cached" || pkg="needed"
			fi
			cmd="./omw --build $name@$version (extra)"
			printf '%-14s %-14s %-12s %-10s %s\n' "$name" "$version" "$(_omw_status_ui_status "$status")" "$pkg" "$cmd"
		done
	done

	_omw_status_ui_section "Prebuilt apps"
	printf '%-14s %-14s %-12s %-10s %s\n' "Name" "Version" "State" "Package" "Command"
	for name in "${APP_LIST[@]}"; do
		version="${APP_VERSIONS[$name]:-}"
		url="${APP_URLS[$name]:-}"
		cmd="${APP_EXECUTABLE_NAME[$name]:-}"
		if [[ -z "$version" || -z "$url" || -z "$cmd" ]]; then
			printf '%-14s %-14s %-12s %-10s %s\n' "$name" "-" "$(_omw_status_ui_status missing)" "-" "incomplete definition"
			continue
		fi
		status=$(omw_app_install_status "$name")
		[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "partial" ]] && continue
		pkg=$(omw_app_package_path "$url")
		[[ -f "$pkg" ]] && pkg="cached" || pkg="needed"
		cmd="./omw --install $name"
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
		[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "partial" ]] && continue
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
		[[ "$show_all" == "false" && "$status" != "installed" && "$status" != "partial" ]] && continue
		printf '%-14s %-14s %-12s %s\n' "$name" "$name" "$(_omw_status_ui_status "$status")" "./omw --config $name"
	done

	printf '\nInstall commands: %s, %s, %s\n' \
		"$(_omw_status_ui_color "36" "./omw --build <name[@version]>")" \
		"$(_omw_status_ui_color "36" "./omw --install <app>")" \
		"$(_omw_status_ui_color "36" "./omw node install <alias>")"
	printf 'Full setup: %s\n' "$(_omw_status_ui_color "36" "./omw --all")"
}
