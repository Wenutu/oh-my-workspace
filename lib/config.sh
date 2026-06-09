# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_config_*.
_omw_config_ensure_local_file() {
	local file="$1"
	local label="$2"
	local comment="$3"
	local path="$CONFIG_LOCAL_PATH/$file"

	[[ -e "$path" || -L "$path" ]] && return 0
	mkdir -p "$CONFIG_LOCAL_PATH"
	printf '%s Add your custom %s config here\n' "$comment" "$label" >"$path"
	omw_log "Created local config placeholder: $path" "INFO"
}

_omw_config_ensure_local_files() {
	_omw_config_ensure_local_file "tmux.local" "tmux" "#" || return 1
	_omw_config_ensure_local_file "zshrc.local" "zsh" "#" || return 1
	_omw_config_ensure_local_file "vimrc.local" "vim" "\"" || return 1
}

_omw_config_write_vimrc() {
	local vimrc="$HOME/.vimrc"
	local tmp_vimrc
	tmp_vimrc=$(mktemp)

	cat >"$tmp_vimrc" <<-'EOF'
		if v:version >= 900
		    let s:old_dir = expand('~/.vim')
		    let s:new_dir = expand('$OMW_HOME/config/$OMW_VERSION/vim/vim9')
		    let &runtimepath = substitute(&runtimepath, '\V' . escape(s:old_dir, '\'), '\=s:new_dir', 'g')
		    let &packpath = substitute(&packpath, '\V' . escape(s:old_dir, '\'), '\=s:new_dir', 'g')

		    let s:vimrc_default = expand('$OMW_HOME/config/$OMW_VERSION/vim/vimrc.default')
		    if filereadable(s:vimrc_default)
		        execute 'source ' . fnameescape(s:vimrc_default)
		    endif

		    let s:vimrc_local = expand('$OMW_HOME/config/local/vimrc.local')
		    if filereadable(s:vimrc_local)
		        execute 'source ' . fnameescape(s:vimrc_local)
		    endif
		else
		    if filereadable(expand('~/.vim/vimrc'))
		        source ~/.vim/vimrc
		    endif
		endif

		finish
	EOF

	if [[ -f "$vimrc" ]] && cmp -s "$tmp_vimrc" "$vimrc"; then
		rm -f "$tmp_vimrc"
		omw_log "$vimrc is already configured." "INFO"
		return 0
	fi

	[[ -e "$vimrc" || -L "$vimrc" ]] && omw_backup_path_for_config "$vimrc" "vim"
	rm -f "$vimrc"
	mv "$tmp_vimrc" "$vimrc"
	omw_log "Installed OMW vimrc to $vimrc" "SUCCESS"
}

omw_config_package_path() {
	printf '%s/config-%s-%s.tar.gz' "$PACKAGES_PATH" "$1" "$OMW_VERSION"
}

omw_restore_config_package() {
	local target="$1"
	local package_path stage_dir target_dir
	package_path=$(omw_config_package_path "$target")
	stage_dir="$BUILDS_PATH/.tmp-$$-config-$target"
	target_dir=$(omw_config_runtime_target_dir "$target")

	if [[ ! -f "$package_path" ]]; then
		omw_log "Optional $target config package not found; skipping $target config." "WARN"
		return 0
	fi

	omw_log "Restoring $target config from $package_path" "INFO"
	omw_safe_rm_rf "$stage_dir"
	mkdir -p "$stage_dir" "$CONFIG_RELEASE_PATH"
	if ! tar -xzf "$package_path" -C "$stage_dir"; then
		omw_log "Failed to restore $target config package." "ERROR"
		omw_safe_rm_rf "$stage_dir"
		return 1
	fi
	if [[ ! -d "$stage_dir/$target" ]]; then
		omw_log "Config package did not contain expected directory: $target" "ERROR"
		omw_safe_rm_rf "$stage_dir"
		return 1
	fi
	omw_safe_rm_rf "$target_dir"
	mv "$stage_dir/$target" "$target_dir"
	omw_safe_rm_rf "$stage_dir"
	OMW_CONFIG_PACKAGE_RESTORED_TARGET="$target"
}

_omw_config_package_was_restored() {
	[[ "${OMW_CONFIG_PACKAGE_RESTORED_TARGET:-}" == "$1" ]]
}

_omw_config_apply_tmux() {
	local cfg_dir
	cfg_dir=$(omw_config_runtime_target_dir "tmux")
	_omw_config_package_was_restored "tmux" || return 0
	if [[ ! -f "$cfg_dir/.tmux/.tmux.conf" || ! -f "$cfg_dir/tmux.default" ]]; then
		omw_log "Tmux config package is missing .tmux/.tmux.conf or tmux.default; skipping Home links." "WARN"
		return 0
	fi
	omw_safe_link_with_backup "$cfg_dir/.tmux/.tmux.conf" "$HOME/.tmux.conf" "tmux"
	omw_safe_link_with_backup "$cfg_dir/tmux.default" "$HOME/.tmux.conf.local" "tmux"
}

_omw_config_check_coc_extensions() {
	local extensions_dir
	extensions_dir="$(omw_config_runtime_target_dir "vim")/coc/extensions"

	if [[ ! -f "$extensions_dir/package.json" ]]; then
		omw_log "Coc extensions package.json is missing from the Vim config package." "WARN"
		return 0
	fi
	if [[ -d "$extensions_dir/node_modules" ]]; then
		omw_log "Using restored Coc extensions: $extensions_dir/node_modules" "INFO"
		return 0
	fi
	omw_log "Coc extensions are missing from the Vim config package; rerun './omw offline pack' on an online machine." "WARN"
}

_omw_config_apply_vim() {
	_omw_config_package_was_restored "vim" || return 0
	if [[ ! -f "$(omw_config_runtime_target_dir "vim")/vimrc.default" ]]; then
		omw_log "Vim config package is missing vimrc.default; skipping Vim config." "WARN"
		return 0
	fi
	_omw_config_write_vimrc
	_omw_config_check_coc_extensions
}

_omw_config_apply_zsh() {
	local cfg_dir
	local zshrc="$HOME/.zshrc"
	cfg_dir=$(omw_config_runtime_target_dir "zsh")
	_omw_config_package_was_restored "zsh" || return 0
	if [[ ! -f "$cfg_dir/.oh-my-zsh/templates/zshrc.zsh-template" || ! -f "$cfg_dir/zshrc.default" ]]; then
		omw_log "Zsh config package is missing the OMZ template or zshrc.default; skipping Zsh config." "WARN"
		return 0
	fi

	omw_safe_link_with_backup "$cfg_dir/.oh-my-zsh" "$HOME/.oh-my-zsh" "zsh"
	[[ -e "$zshrc" || -L "$zshrc" ]] && omw_backup_path_for_config "$zshrc" "zsh"
	rm -f "$zshrc"
	cp "$cfg_dir/.oh-my-zsh/templates/zshrc.zsh-template" "$zshrc"
	sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$zshrc"
	sed -i 's|plugins=(git)|plugins=(git autojump zsh-autosuggestions zsh-syntax-highlighting)|g' "$zshrc"
	sed -i 's|^#.*zstyle.*':omz:update'.*mode.*disabled|zstyle :omz:update mode disabled|g' "$zshrc"

	# To source environment-modules
	# printf "\n# Source environment-modules if available\n[[ -f /etc/profile.d/modules.sh ]] && source /etc/profile.d/modules.sh\n" >>"$zshrc"

	# OMW Config section
	printf "\n# OMW Config\n" >>"$zshrc"
	# shellcheck disable=SC2016
	printf 'export OMW_HOME="%s"\n' "$OMW_HOME" >>"$zshrc"
	printf '[[ -f "$OMW_HOME/env.sh" ]] && source "$OMW_HOME/env.sh"\n' >>"$zshrc"
	printf '[[ -f "$OMW_HOME/config/$OMW_VERSION/zsh/zshrc.default" ]] && source "$OMW_HOME/config/$OMW_VERSION/zsh/zshrc.default"\n' >>"$zshrc"
	printf '[[ -f "$OMW_HOME/config/local/zshrc.local" ]] && source "$OMW_HOME/config/local/zshrc.local"\n' >>"$zshrc"

	# Autojump section
	# printf "\n# Autojump\n" >>"$zshrc"
	# printf '[[ -f "$HOME/.autojump/etc/profile.d/autojump.sh" ]] && source "$HOME/.autojump/etc/profile.d/autojump.sh"\n' >>"$zshrc"
	omw_log "Rebuilt $zshrc from the OMZ template." "SUCCESS"
}

_omw_config_clone_repo_once() {
	local url="$1"
	local dest="$2"
	local branch="${3:-}"
	local tmp_dest="${dest}.tmp-$$"

	if [[ -d "$dest/.git" ]] || { [[ -d "$dest" ]] && find "$dest" -mindepth 1 -print -quit | grep -q .; }; then
		omw_log "Using existing repository directory: $dest" "INFO"
		return 0
	fi
	omw_safe_rm_rf "$tmp_dest"
	mkdir -p "$(dirname "$dest")"
	omw_log "Cloning $url into $dest" "INFO"
	if [[ -n "$branch" ]]; then
		GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$branch" "$url" "$tmp_dest" || return 1
	else
		GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$url" "$tmp_dest" || return 1
	fi
	omw_safe_rm_rf "$dest"
	mv "$tmp_dest" "$dest"
}

_omw_config_prepare_tmux() {
	local cfg_dir
	cfg_dir=$(omw_config_source_target_dir "tmux")
	if [[ ! -f "$cfg_dir/tmux.default" ]]; then
		omw_log "Tmux config source is missing: $cfg_dir/tmux.default" "ERROR"
		return 1
	fi
	if [[ -d "$cfg_dir/.tmux" ]]; then
		omw_log "Using existing Tmux config: $cfg_dir/.tmux" "INFO"
		return 0
	fi
	mkdir -p "$cfg_dir"
	_omw_config_clone_repo_once "https://github.com/gpakosz/.tmux.git" "$cfg_dir/.tmux"
}

_omw_config_prepare_zsh() {
	local cfg_dir
	cfg_dir=$(omw_config_source_target_dir "zsh")
	if [[ ! -f "$cfg_dir/zshrc.default" ]]; then
		omw_log "Zsh config source is missing: $cfg_dir/zshrc.default" "ERROR"
		return 1
	fi
	if [[ -d "$cfg_dir/.oh-my-zsh" ]]; then
		omw_log "Using existing Zsh config: $cfg_dir/.oh-my-zsh" "INFO"
		return 0
	fi
	mkdir -p "$cfg_dir"
	_omw_config_clone_repo_once "https://github.com/ohmyzsh/ohmyzsh.git" "$cfg_dir/.oh-my-zsh" || return 1
	mkdir -p "$cfg_dir/.oh-my-zsh/custom/themes" "$cfg_dir/.oh-my-zsh/custom/plugins"
	_omw_config_clone_repo_once "https://github.com/romkatv/powerlevel10k.git" "$cfg_dir/.oh-my-zsh/custom/themes/powerlevel10k" || return 1
	_omw_config_clone_repo_once "https://github.com/zsh-users/zsh-autosuggestions.git" "$cfg_dir/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || return 1
	_omw_config_clone_repo_once "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$cfg_dir/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
}

_omw_config_coc_registry_url() {
	printf '%s' "${OMW_COC_REGISTRY_URL:-https://registry.npmjs.org}"
}

_omw_config_record_coc_extension() {
	local extensions_dir="$1"
	local name="$2"
	local version="$3"

	node - "$extensions_dir/package.json" "$name" "$version" <<-'NODE'
		const fs = require('fs')
		const [file, name, version] = process.argv.slice(2)
		const json = JSON.parse(fs.readFileSync(file, 'utf8'))
		json.dependencies = json.dependencies || {}
		json.dependencies[name] = `>=${version}`
		fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n')
	NODE
}

_omw_config_lock_coc_extensions() {
	local extensions_dir="$1"
	local list_file="$2"

	node - "$extensions_dir/package.json" "$list_file" <<-'NODE'
		const fs = require('fs')
		const [file, listFile] = process.argv.slice(2)
		const json = JSON.parse(fs.readFileSync(file, 'utf8'))
		json.locked = fs.readFileSync(listFile, 'utf8')
		  .split(/\r?\n/)
		  .map(line => line.trim())
		  .filter(line => line && !line.startsWith('#'))
		  .map(spec => spec.replace(/@[^@/]+$/, ''))
		fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n')
	NODE
}

_omw_config_install_coc_extension() {
	local extensions_dir="$1"
	local cache_dir="$2"
	local spec="$3"
	local registry_url encoded_name metadata_file tarball_file target_dir
	local name version tarball_url resolved_name resolved_version required_coc dependency

	if [[ "$spec" =~ ^(@[^/]+/[^@]+|[^@]+)@([^@]+)$ ]]; then
		name="${BASH_REMATCH[1]}"
		version="${BASH_REMATCH[2]}"
	else
		name="$spec"
		version="latest"
	fi
	if [[ " ${OMW_COC_INSTALLING:-} " == *" $name "* ]]; then
		omw_log "Skipping circular Coc extension dependency: $name" "WARN"
		return 0
	fi
	target_dir="$extensions_dir/node_modules/$name"
	if [[ -f "$target_dir/package.json" ]]; then
		omw_log "Using installed Coc extension: $name" "INFO"
		return 0
	fi

	OMW_COC_INSTALLING="${OMW_COC_INSTALLING:-} $name"
	registry_url=$(_omw_config_coc_registry_url)
	encoded_name="${name//@/%40}"
	encoded_name="${encoded_name//\//%2f}"
	metadata_file="$cache_dir/${name//\//_}.json"
	tarball_file="$cache_dir/${name//\//_}.tgz"
	omw_log "Fetching Coc extension metadata: $name@$version" "INFO"
	omw_download_package "$registry_url/$encoded_name/$version" "$metadata_file" || return 1
	IFS=$'\t' read -r tarball_url resolved_name resolved_version required_coc < <(
		node - "$metadata_file" <<-'NODE'
			const fs = require('fs')
			const json = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
			if (!json.dist || !json.dist.tarball || !json.name || !json.version || !json.engines || !json.engines.coc) process.exit(1)
			console.log([json.dist.tarball, json.name, json.version, json.engines.coc].join('\t'))
		NODE
	) || {
		omw_log "Failed to parse Coc extension metadata for $spec" "ERROR"
		return 1
	}
	if [[ "$resolved_name" != "$name" || -z "$tarball_url" || -z "$required_coc" ]]; then
		omw_log "Invalid Coc extension metadata for $spec" "ERROR"
		return 1
	fi

	omw_download_package "$tarball_url" "$tarball_file" || return 1
	omw_extract_package "$tarball_file" "$target_dir" 1 || return 1
	if node - "$target_dir/package.json" <<-'NODE'; then
		const json = require(process.argv[2])
		const local = new Set(['coc.nvim', 'esbuild', 'webpack', '@types/node'])
		process.exit(Object.keys(json.dependencies || {}).some(name => !local.has(name)) ? 0 : 1)
	NODE
		omw_log "Installing private dependencies for Coc extension: $resolved_name" "INFO"
		if ! (cd "$target_dir" && npm install --omit=dev --ignore-scripts --legacy-peer-deps --no-global --no-package-lock --no-audit --no-fund --cache "$cache_dir"); then
			omw_log "Failed to install private dependencies for Coc extension: $resolved_name" "ERROR"
			return 1
		fi
	fi
	_omw_config_record_coc_extension "$extensions_dir" "$resolved_name" "$resolved_version" || return 1
	while IFS= read -r dependency; do
		[[ -n "$dependency" ]] || continue
		_omw_config_install_coc_extension "$extensions_dir" "$cache_dir" "$dependency" || return 1
	done < <(
		node - "$target_dir/package.json" <<-'NODE'
			const json = require(process.argv[2])
			for (const dependency of [...new Set(json.extensionDependencies || [])]) console.log(dependency)
		NODE
	)
}

_omw_config_install_all_coc_extensions() {
	local cfg_dir="$1"
	local extensions_dir="$cfg_dir/coc/extensions"
	local stage_dir="${extensions_dir}.tmp-$$"
	local cache_dir="$BUILDS_PATH/.tmp-$$-coc-npm-cache"
	local list_file="$cfg_dir/coc/extensions.list"
	local spec

	if [[ ! -f "$list_file" ]]; then
		omw_log "Coc extensions list is missing: $list_file" "ERROR"
		return 1
	fi
	omw_safe_rm_rf "$stage_dir"
	omw_safe_rm_rf "$cache_dir"
	mkdir -p "$stage_dir/node_modules" "$cache_dir"
	printf '{"dependencies":{}}\n' >"$stage_dir/package.json"
	OMW_COC_INSTALLING=""
	while IFS= read -r spec; do
		[[ -z "$spec" || "$spec" == \#* ]] && continue
		if [[ ! "$spec" =~ ^(@[^/]+/[^@]+|[^@]+)@[^@]+$ ]]; then
			omw_log "Coc extensions list entry must include an exact version: $spec" "ERROR"
			omw_safe_rm_rf "$stage_dir"
			omw_safe_rm_rf "$cache_dir"
			return 1
		fi
		_omw_config_install_coc_extension "$stage_dir" "$cache_dir" "$spec" || {
			omw_safe_rm_rf "$stage_dir"
			omw_safe_rm_rf "$cache_dir"
			return 1
		}
	done <"$list_file"
	_omw_config_lock_coc_extensions "$stage_dir" "$list_file" || {
		omw_safe_rm_rf "$stage_dir"
		omw_safe_rm_rf "$cache_dir"
		return 1
	}
	omw_safe_rm_rf "$extensions_dir"
	mv "$stage_dir" "$extensions_dir"
	omw_safe_rm_rf "$cache_dir"
}

_omw_config_prepare_vim() {
	local cfg_dir
	local plugin_dir
	local extensions_dir
	local node_modules_dir
	local node_version="${OMW_COC_NODE_VERSION:-}"
	local name url branch

	cfg_dir=$(omw_config_source_target_dir "vim")
	plugin_dir="$cfg_dir/vim9/pack/omw/start"
	extensions_dir="$cfg_dir/coc/extensions"
	node_modules_dir="$extensions_dir/node_modules"

	if [[ ! -f "$cfg_dir/plugins.list" || ! -f "$cfg_dir/vimrc.default" ]]; then
		omw_log "Vim plugins.list or vimrc.default is missing." "ERROR"
		return 1
	fi
	if [[ -d "$plugin_dir" && -d "$node_modules_dir" ]]; then
		omw_log "Using existing Vim plugins and Coc extensions." "INFO"
		return 0
	fi
	mkdir -p "$plugin_dir"
	while IFS='|' read -r name url branch; do
		[[ -z "$name" || "$name" == \#* ]] && continue
		_omw_config_clone_repo_once "$url" "$plugin_dir/$name" "$branch" || return 1
	done <"$cfg_dir/plugins.list"

	if [[ -d "$node_modules_dir" ]]; then
		omw_log "Using existing Coc extensions: $node_modules_dir" "INFO"
		return 0
	fi
	omw_node_ensure_version "$node_version" || return 1
	omw_node_load_version "$node_version" || return 1
	omw_log "Installing Coc extensions from the fixed extension list." "INFO"
	_omw_config_install_all_coc_extensions "$cfg_dir"
}

_omw_config_backup_generated_assets() {
	local target="$1"
	case "$target" in
	tmux) omw_tx_backup_internal "$(omw_config_source_target_dir "tmux")/.tmux" ;;
	zsh) omw_tx_backup_internal "$(omw_config_source_target_dir "zsh")/.oh-my-zsh" ;;
	vim)
		omw_tx_backup_internal "$(omw_config_source_target_dir "vim")/vim9/pack" || return 1
		omw_tx_backup_internal "$(omw_config_source_target_dir "vim")/coc/extensions"
		;;
	*)
		omw_log "Unknown config target: $target" "ERROR"
		return 1
		;;
	esac
}

omw_prepare_config_for_package() {
	local target="$1"
	local force="${2:-false}"
	local prepare_func="_omw_config_prepare_$target"
	if ! declare -F "$prepare_func" >/dev/null; then
		omw_log "Unknown config target: $target" "ERROR"
		return 1
	fi
	if [[ "$force" != "true" ]]; then
		"$prepare_func"
		return
	fi

	omw_log "Refreshing generated $target config assets." "INFO"
	omw_tx_begin || return 1
	local OMW_CONFIG_FORCE_REFRESH=true
	if ! _omw_config_backup_generated_assets "$target" || ! "$prepare_func"; then
		omw_tx_rollback
		return 1
	fi
	omw_tx_commit
}

omw_configure() {
	local target="$1"
	local apply_func="_omw_config_apply_$target"
	CONFIG_BACKUP_PATHS=()
	OMW_CONFIG_PACKAGE_RESTORED_TARGET=""

	if ! omw_contains_word "$target" "${CONFIG_TARGET_LIST[*]}" || ! declare -F "$apply_func" >/dev/null; then
		omw_log "Unknown config target: $target" "ERROR"
		return 1
	fi
	omw_log "Configuring $target..."
	_omw_config_ensure_local_files || return 1
	omw_restore_config_package "$target" || return 1
	"$apply_func" || return 1
	omw_log "$target configuration complete." "SUCCESS"
	omw_print_config_backup_paths
}

omw_init_shell_env() {
	local bashrc="$HOME/.bashrc"

	omw_log "Initializing OMW shell environment..." "INFO"
	# shellcheck disable=SC2016
	omw_append_line_with_backup "$bashrc" "$OMW_HOME/env.sh" "$(printf '\n# OMW Config\n[[ -f "%s/env.sh" ]] && source "%s/env.sh"' "$OMW_HOME" "$OMW_HOME")" "bash"
	omw_log "OMW environment source line is configured in $bashrc" "SUCCESS"
	omw_log "Please restart your terminal or run 'source $bashrc' to apply the changes." "SUCCESS"
}

omw_config_clean_generated_assets() {
	local dry_run="${1:-false}"
	local path
	for path in \
		"$(omw_config_source_target_dir "tmux")/.tmux" \
		"$(omw_config_source_target_dir "vim")/coc/extensions" \
		"$(omw_config_source_target_dir "vim")/vim9/pack" \
		"$(omw_config_source_target_dir "zsh")/.oh-my-zsh" \
		"$(omw_config_runtime_target_dir "tmux")/.tmux" \
		"$(omw_config_runtime_target_dir "vim")/coc/extensions" \
		"$(omw_config_runtime_target_dir "vim")/vim9/pack" \
		"$(omw_config_runtime_target_dir "zsh")/.oh-my-zsh"; do
		if [[ "$dry_run" == "true" ]]; then
			printf 'Would remove: %s\n' "$path"
		else
			omw_safe_rm_rf "$path"
		fi
	done
}
