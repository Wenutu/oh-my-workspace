# shellcheck shell=bash
# Package registry and package metadata helpers backed by packages.sh definitions.

omw_render_version_template() {
	local template="$1"
	local version="$2"
	template="${template//\$\{VERSION\}/$version}"
	template="${template//\{VERSION\}/$version}"
	printf '%s\n' "$template"
}

omw_get_software_url() {
	local appname="$1"
	local version="$2"
	local key="$appname@$version"
	local url_template="${SOFTWARE_URLS[$key]:-${SOFTWARE_URLS[$appname]:-}}"
	omw_render_version_template "$url_template" "$version"
}

omw_get_app_url() {
	local appname="$1"
	local version="${APP_VERSIONS[$appname]:-}"
	local url_template="${APP_URLS[$appname]:-}"
	[[ -n "$url_template" && -n "$version" ]] || return 1
	omw_render_version_template "$url_template" "$version"
}

omw_get_app_source_url() {
	local appname="$1"
	local version="${APP_VERSIONS[$appname]:-}"
	local url_template="${APP_SOURCE_URLS[$appname]:-}"
	[[ -n "$url_template" && -n "$version" ]] || return 1
	omw_render_version_template "$url_template" "$version"
}

omw_gcc_prereq_script_url() {
	local version="$1"
	printf 'https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-%s/contrib/download_prerequisites' "$version"
}

omw_gcc_prereq_packages_from_script() {
	local prereq_script="$1"
	if [[ ! -f "$prereq_script" ]]; then
		omw_log "download_prerequisites script not found: $prereq_script" "ERROR"
		return 1
	fi
	local prereqs=(
		"$(grep -Eo 'gmp-[^[:space:]"'"'"']+tar\.bz2' "$prereq_script" | head -1 || true)"
		"$(grep -Eo 'mpfr-[^[:space:]"'"'"']+tar\.bz2' "$prereq_script" | head -1 || true)"
		"$(grep -Eo 'mpc-[^[:space:]"'"'"']+tar\.gz' "$prereq_script" | head -1 || true)"
		"$(grep -Eo 'isl-[^[:space:]"'"'"']+tar\.bz2' "$prereq_script" | head -1 || true)"
	)
	local pkg
	for pkg in "${prereqs[@]}"; do
		[[ -n "$pkg" ]] && echo "$pkg"
	done
}
