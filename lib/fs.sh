# shellcheck shell=bash
# Filesystem, archive, and download helpers.

_omw_fs_file_size() {
	local path="$1"
	if stat -c%s "$path" &>/dev/null; then
		stat -c%s "$path"
	else
		stat -f%z "$path"
	fi
}

omw_sha256_stdin() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | {
			local hash _
			read -r hash _
			printf '%s\n' "$hash"
		}
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 | {
			local hash _
			read -r hash _
			printf '%s\n' "$hash"
		}
	else
		omw_log "sha256sum or shasum is required for digest comparison." "ERROR"
		return 1
	fi
}

omw_file_sha256() {
	local path="$1"
	local hash _
	if command -v sha256sum >/dev/null 2>&1; then
		read -r hash _ < <(sha256sum "$path")
		printf '%s\n' "$hash"
	elif command -v shasum >/dev/null 2>&1; then
		read -r hash _ < <(shasum -a 256 "$path")
		printf '%s\n' "$hash"
	else
		omw_log "sha256sum or shasum is required for digest comparison." "ERROR"
		return 1
	fi
}

omw_file_md5() {
	local path="$1"
	local hash _
	if command -v md5sum >/dev/null 2>&1; then
		read -r hash _ < <(md5sum "$path")
		printf '%s\n' "$hash"
	elif command -v md5 >/dev/null 2>&1; then
		read -r hash _ < <(md5 -r "$path")
		printf '%s\n' "$hash"
	else
		omw_log "md5sum or md5 is required for bundle manifest comparison." "ERROR"
		return 1
	fi
}

_omw_fs_file_mode() {
	local path="$1"
	if stat -c '%a' "$path" &>/dev/null; then
		stat -c '%a' "$path"
	else
		stat -f '%Lp' "$path"
	fi
}

_omw_bundle_manifest_include_path() {
	local rel="$1"
	local manifest_name="$2"
	local version="${OMW_VERSION:-}"

	case "$rel" in
	"$manifest_name" | .omw-bundle-meta) return 1 ;;
	config | config/*) return 1 ;;
	esac
	if [[ "$rel" == lib || "$rel" == lib/* ]]; then
		[[ -n "$version" ]] || return 0
		[[ "$rel" == "lib" || "$rel" == "lib/$version" || "$rel" == "lib/$version/"* ]]
		return
	fi
	return 0
}

omw_write_bundle_manifest() {
	local root="$1"
	local manifest="$2"
	local rel hash mode target

	[[ -d "$root" ]] || {
		omw_log "Manifest root not found: $root" "ERROR"
		return 1
	}
	mkdir -p "$(dirname "$manifest")"
	(
		cd "$root" || exit 1
		printf 'format\t2\n'
		printf 'algorithm\tmd5\n'
		find . -mindepth 1 \
			! -path "./$(basename "$manifest")" \
			! -path './.omw-bundle-meta' \
			-print | LC_ALL=C sort | while IFS= read -r rel; do
			rel="${rel#./}"
			_omw_bundle_manifest_include_path "$rel" "$(basename "$manifest")" || continue
			if [[ -L "$rel" ]]; then
				target=$(readlink "$rel") || exit 1
				printf 'L\t-\t%s\t%s\n' "$target" "$rel"
			elif [[ -f "$rel" ]]; then
				hash=$(omw_file_md5 "$rel") || exit 1
				mode=$(_omw_fs_file_mode "$rel") || exit 1
				printf 'F\t%s\t%s\t%s\n' "$hash" "$mode" "$rel"
			elif [[ -d "$rel" ]]; then
				mode=$(_omw_fs_file_mode "$rel") || exit 1
				printf 'D\t-\t%s\t%s\n' "$mode" "$rel"
			fi
		done
	) >"$manifest"
}

omw_write_bundle_metadata() {
	local root="$1"
	local meta="$2"
	local source_commit="${OMW_SOURCE_COMMIT:-}"
	local source_commit_short="${OMW_SOURCE_COMMIT_SHORT:-}"
	local source_ref="${OMW_SOURCE_REF:-}"
	local source_ref_name="${OMW_SOURCE_REF_NAME:-}"
	local source_ref_type="${OMW_SOURCE_REF_TYPE:-}"
	local build_kind="${OMW_BUILD_KIND:-}"
	local release_tag="${OMW_RELEASE_TAG:-}"
	local release_name="${OMW_RELEASE_NAME:-}"
	local git_root="${OMW_HOME:-$root}"

	[[ -d "$root" ]] || {
		omw_log "Bundle metadata root not found: $root" "ERROR"
		return 1
	}
	if [[ -z "$source_commit" ]] && command -v git >/dev/null 2>&1; then
		source_commit=$(git -C "$git_root" rev-parse HEAD 2>/dev/null || true)
	fi
	if [[ -z "$source_commit_short" && -n "$source_commit" ]]; then
		source_commit_short="${source_commit:0:12}"
	fi
	if [[ -z "$source_ref" ]] && command -v git >/dev/null 2>&1; then
		source_ref=$(git -C "$git_root" symbolic-ref -q HEAD 2>/dev/null || true)
		if [[ -z "$source_ref" ]]; then
			source_ref_name=$(git -C "$git_root" describe --tags --exact-match --match 'v*' 2>/dev/null || true)
			[[ -n "$source_ref_name" ]] && source_ref="refs/tags/$source_ref_name"
		fi
	fi
	if [[ -z "$source_ref_name" && -n "$source_ref" ]]; then
		source_ref_name="${source_ref#refs/heads/}"
		source_ref_name="${source_ref_name#refs/tags/}"
	fi
	if [[ -z "$source_ref_type" ]]; then
		case "$source_ref" in
		refs/tags/*) source_ref_type="tag" ;;
		refs/heads/*) source_ref_type="branch" ;;
		*) source_ref_type="unknown" ;;
		esac
	fi
	if [[ -z "$build_kind" ]]; then
		[[ "$source_ref_type" == "tag" ]] && build_kind="release" || build_kind="commit"
	fi
	if [[ "$build_kind" == "release" && -z "$release_tag" ]]; then
		release_tag="$source_ref_name"
	fi
	if [[ "$build_kind" == "release" && -z "$release_name" ]]; then
		release_name="$release_tag"
	fi
	mkdir -p "$(dirname "$meta")"
	{
		printf 'bundle_format=2\n'
		printf 'manifest_format=2\n'
		printf 'manifest_path=.omw-bundle-manifest\n'
		printf 'manifest_algorithm=md5\n'
		printf 'created_at=%s\n' "$(date +%Y%m%d%H%M%S)"
		printf 'omw_version=%s\n' "${OMW_VERSION:-}"
		printf 'managed_policy=replace-exact\n'
		printf 'config_policy=replace-preserve-local\n'
		printf 'packages_policy=merge-overlay\n'
		printf 'npm_cache_policy=replace\n'
		printf 'build_kind=%s\n' "$build_kind"
		printf 'source_commit=%s\n' "$source_commit"
		printf 'source_commit_short=%s\n' "$source_commit_short"
		printf 'source_ref=%s\n' "$source_ref"
		printf 'source_ref_name=%s\n' "$source_ref_name"
		printf 'source_ref_type=%s\n' "$source_ref_type"
		printf 'release_tag=%s\n' "$release_tag"
		printf 'release_name=%s\n' "$release_name"
	} >"$meta"
}

omw_path_sha256() {
	local path="$1"
	local rel target hash

	if [[ -L "$path" ]]; then
		target=$(readlink "$path") || return 1
		printf 'L\t%s\n' "$target" | omw_sha256_stdin
	elif [[ -f "$path" ]]; then
		omw_file_sha256 "$path"
	elif [[ -d "$path" ]]; then
		(
			cd "$path" || exit 1
			find . -mindepth 1 -print | LC_ALL=C sort | while IFS= read -r rel; do
				if [[ -L "$rel" ]]; then
					target=$(readlink "$rel") || exit 1
					printf 'L\t%s\t%s\n' "$rel" "$target"
				elif [[ -f "$rel" ]]; then
					hash=$(omw_file_sha256 "$rel") || exit 1
					printf 'F\t%s\t%s\n' "$rel" "$hash"
				elif [[ -d "$rel" ]]; then
					printf 'D\t%s\n' "$rel"
				else
					printf 'O\t%s\n' "$rel"
				fi
			done | omw_sha256_stdin
		)
	else
		omw_log "Path not found for sha256 digest: $path" "ERROR"
		return 1
	fi
}

omw_ensure_valid_cwd() {
	if ! pwd -P >/dev/null 2>&1; then
		omw_log "Current directory is no longer accessible; switching to $OMW_HOME" "WARN"
		cd "$OMW_HOME"
	fi
}

_omw_fs_normalize_path() {
	local path="$1"
	local probe="$path"
	local suffix=""
	local base resolved

	[[ "$path" == /* && "$path" != *"/../"* && "$path" != */.. && "$path" != *"/./"* && "$path" != */. ]] || return 1
	while [[ ! -e "$probe" && ! -L "$probe" ]]; do
		base=$(basename "$probe")
		[[ -n "$base" && "$base" != "/" && "$base" != "." && "$base" != ".." ]] || return 1
		suffix="/$base$suffix"
		probe=$(dirname "$probe")
	done
	if [[ ! -d "$probe" ]]; then
		base=$(basename "$probe")
		suffix="/$base$suffix"
		probe=$(dirname "$probe")
	fi
	resolved=$(cd "$probe" 2>/dev/null && pwd -P) || return 1
	if [[ "$resolved" == "/" ]]; then
		printf '/%s\n' "${suffix#/}"
	else
		printf '%s%s\n' "$resolved" "$suffix"
	fi
}

_omw_fs_is_internal_path() {
	local path="$1"
	local normalized_home normalized_path
	normalized_home=$(_omw_fs_normalize_path "$OMW_HOME") || return 1
	normalized_path=$(_omw_fs_normalize_path "$path") || return 1
	[[ "$normalized_path" == "$normalized_home/"* ]]
}

omw_paths_same() {
	local left="$1"
	local right="$2"
	local normalized_left normalized_right
	normalized_left=$(_omw_fs_normalize_existing_path "$left") || return 1
	normalized_right=$(_omw_fs_normalize_existing_path "$right") || return 1
	[[ "$normalized_left" == "$normalized_right" ]]
}

_omw_fs_normalize_existing_path() {
	local path="$1"
	local dir base resolved

	[[ -e "$path" || -L "$path" ]] || return 1
	if [[ -d "$path" && ! -L "$path" ]]; then
		(cd "$path" 2>/dev/null && pwd -P)
		return
	fi
	dir=$(dirname "$path")
	base=$(basename "$path")
	resolved=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
	if [[ "$resolved" == "/" ]]; then
		printf '/%s\n' "$base"
	else
		printf '%s/%s\n' "$resolved" "$base"
	fi
}

omw_safe_rm_rf() {
	local path="$1"
	omw_ensure_valid_cwd
	if [[ -z "$path" ]] || ! _omw_fs_is_internal_path "$path"; then
		omw_log "Refusing to remove unsafe path: '${path}'" "ERROR"
		return 1
	fi
	rm -rf -- "$path"
}

omw_clear_directory_contents() {
	local path="$1"
	if [[ -z "$path" ]] || ! _omw_fs_is_internal_path "$path"; then
		omw_log "Refusing to clear unsafe directory: '${path}'" "ERROR"
		return 1
	fi
	mkdir -p "$path"
	find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

omw_copy_path_contents() {
	local source_dir="$1"
	local dest_dir="$2"

	if [[ ! -d "$source_dir" ]]; then
		omw_log "Source directory not found: $source_dir" "ERROR"
		return 1
	fi
	mkdir -p "$dest_dir"
	cp -a "$source_dir/." "$dest_dir/"
}

omw_download_package() {
	local url="$1"
	local dest="$2"
	if [[ -z "$url" || -z "$dest" ]]; then
		omw_log "omw_download_package requires both URL and destination." "ERROR"
		return 1
	fi
	if [[ -f "$dest" && $(_omw_fs_file_size "$dest") -gt 100 ]]; then
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
		if wget --tries=1 --timeout="$DOWNLOAD_TIMEOUT" -o "$log_file" -O "$tmp_dest" "$url" && [[ $(_omw_fs_file_size "$tmp_dest") -gt 100 ]]; then
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
