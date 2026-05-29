# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_config_*.
_omw_config_write_vimrc() {
	local vimrc="$HOME/.vimrc"
	local tmp_vimrc
	tmp_vimrc=$(mktemp)

	cat >"$tmp_vimrc" <<-'EOF'
		if v:version >= 900
		    let s:old_dir = expand('~/.vim')
		    let s:new_dir = expand('$OMW_HOME/config/vim/vim9')
		    let &runtimepath = substitute(&runtimepath, '\V' . escape(s:old_dir, '\'), '\=s:new_dir', 'g')
		    let &packpath = substitute(&packpath, '\V' . escape(s:old_dir, '\'), '\=s:new_dir', 'g')

		    let s:vimrc = s:new_dir . '/vimrc'
		    if filereadable(s:vimrc)
		        execute 'source ' . fnameescape(s:vimrc)
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
	mv "$tmp_vimrc" "$vimrc"
	omw_log "Installed OMW vimrc to $vimrc" "SUCCESS"
}

_omw_config_dir_has_entries() {
	local dir="$1"
	local first_entry

	[[ -d "$dir" ]] || return 1
	first_entry=$(find "$dir" -mindepth 1 -print -quit)
	[[ -n "$first_entry" ]]
}

_omw_config_skip_existing_dir_without_force() {
	local target="$1"
	local dir="$2"
	local force="$3"

	if [[ "$force" == "true" ]]; then
		return 1
	fi
	if _omw_config_dir_has_entries "$dir"; then
		omw_log "$target config directory already contains files: $dir" "WARN"
		omw_log "Skipping $target config. Delete the existing config directory or rerun with --force to overwrite it." "WARN"
		return 0
	fi
	return 1
}

_omw_config_package_path() {
	local target="$1"
	printf '%s/config/%s.tar.gz' "$PACKAGES_PATH" "$target"
}

_omw_config_required_path() {
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

omw_config_package_path() {
	_omw_config_package_path "$1"
}

omw_config_required_path() {
	_omw_config_required_path "$1"
}

omw_config_ready_for_package() {
	local target="$1"
	local required_path first_entry
	required_path=$(_omw_config_required_path "$target")

	[[ -d "$required_path" ]] || return 1
	first_entry=$(find "$required_path" -mindepth 1 -print -quit)
	[[ -n "$first_entry" ]]
}

omw_restore_config_package() {
	local target="$1"
	local required_path="$2"
	local force="${3:-false}"
	local package_path target_dir backup_dir first_entry has_conflict=false
	package_path=$(_omw_config_package_path "$target")
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

###############################################################################
# Post-Install & Packaging
###############################################################################
omw_configure() {
	local target="$1"
	local force="${2:-false}"
	CONFIG_BACKUP_PATHS=()

	case "$target" in
	"tmux")
		omw_log "Configuring tmux..."
		local cfg_dir="$CONFIG_PATH/tmux"
		if _omw_config_skip_existing_dir_without_force "$target" "$cfg_dir" "$force"; then
			return 0
		fi
		omw_restore_config_package "$target" "$cfg_dir/.tmux" "$force" || return 1
		mkdir -p "$cfg_dir"
		omw_clone_repo_once "https://github.com/gpakosz/.tmux.git" "$cfg_dir/.tmux" || return 1
		omw_safe_link_with_backup "$cfg_dir/.tmux/.tmux.conf" "$HOME/.tmux.conf" "tmux"
		omw_copy_if_absent_with_backup "$cfg_dir/.tmux/.tmux.conf.local" "$HOME/.tmux.conf.local" "tmux"
		;;
	"vim")
		omw_log "Configuring Vim..."
		local cfg_dir="$CONFIG_PATH/vim/vim9"
		if _omw_config_skip_existing_dir_without_force "$target" "$CONFIG_PATH/vim" "$force"; then
			return 0
		fi
		omw_restore_config_package "$target" "$cfg_dir" "$force" || return 1
		if ! omw_config_ready_for_package "$target"; then
			omw_log "Vim config package not found and local Vim config is missing; please configure Vim manually." "WARN"
			return 0
		fi
		_omw_config_write_vimrc || return 1
		;;
	"zsh")
		omw_log "Configuring Zsh..."
		local cfg_dir="$CONFIG_PATH/zsh"
		if _omw_config_skip_existing_dir_without_force "$target" "$cfg_dir" "$force"; then
			return 0
		fi
		omw_restore_config_package "$target" "$cfg_dir/.oh-my-zsh" "$force" || return 1
		mkdir -p "$cfg_dir"
		omw_clone_repo_once "https://github.com/ohmyzsh/ohmyzsh.git" "$cfg_dir/.oh-my-zsh" || return 1
		mkdir -p "$cfg_dir/.oh-my-zsh/custom/themes" "$cfg_dir/.oh-my-zsh/custom/plugins"
		omw_clone_repo_once "https://github.com/romkatv/powerlevel10k.git" "$cfg_dir/.oh-my-zsh/custom/themes/powerlevel10k" || return 1
		omw_clone_repo_once "https://github.com/zsh-users/zsh-autosuggestions.git" "$cfg_dir/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || return 1
		omw_clone_repo_once "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$cfg_dir/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || return 1
		omw_link_if_absent_with_backup "$cfg_dir/.oh-my-zsh" "$HOME/.oh-my-zsh" "zsh"
		# Only create a .zshrc if one does not exist
		if [[ ! -f "$HOME/.zshrc" ]]; then
			cp "$cfg_dir/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
			sed -i 's|ZSH_THEME="robbyrussell"|ZSH_THEME="powerlevel10k/powerlevel10k"|g' "$HOME/.zshrc"
			sed -i 's|plugins=(git)|plugins=(git autojump zsh-autosuggestions zsh-syntax-highlighting)|g' "$HOME/.zshrc"
		fi
		# Ensure OMW environment is sourced in .zshrc
		# shellcheck disable=SC2016
		omw_append_line_with_backup "$HOME/.zshrc" "OMW_HOME" "$(printf '\n# OMW Config\nexport OMW_HOME="%s"\n[[ -f "$OMW_HOME/env.sh" ]] && source "$OMW_HOME/env.sh"' "$OMW_HOME")" "zsh"
		# Add a hook for user customizations if it doesn't exist
		# shellcheck disable=SC2016
		omw_append_line_with_backup "$HOME/.zshrc" ".zshrc_custom" '
# User customizations file
[[ -f "$HOME/.zshrc_custom" ]] && source "$HOME/.zshrc_custom"' "zsh"
		# Create the custom file if it's missing
		if [[ ! -f "$HOME/.zshrc_custom" ]]; then
			cat >"$HOME/.zshrc_custom" <<-EOF
				# Add your custom Zsh configurations here
				# For example, set your preferred editor:
				# export EDITOR='nvim'
				export EDITOR='gvim'
			EOF
		fi
		;;
	*)
		omw_log "Unknown config target: $target" "ERROR"
		return 1
		;;
	esac
	omw_log "$target configuration complete." "SUCCESS"
	omw_print_config_backup_paths
}

omw_init_shell_env() {
	local bashrc="$HOME/.bashrc"

	omw_log "Initializing OMW shell environment..." "INFO"
	# shellcheck disable=SC2016
	omw_append_line_with_backup "$bashrc" "$OMW_HOME/env.sh" "$(printf '\n# OMW Config\n[[ -f "%s/env.sh" ]] && source "%s/env.sh"' "$OMW_HOME" "$OMW_HOME")" "bash"
	omw_log "OMW environment source line is configured in $bashrc" "SUCCESS"
}
