# shellcheck shell=bash
# Public functions in this file use the omw_* prefix.
# Private helpers use _omw_app_*.
_omw_app_install_autojump() {
	local appname="$1"
	local install_dir="$2"
	local exec_path
	exec_path=$(find "$install_dir" -type f -name "install.py" | head -n 1)
	[[ -z "$exec_path" ]] && {
		omw_log "autojump install.py not found in $install_dir." "ERROR"
		return 1
	}
	if [[ ! -f "$exec_path" ]]; then
		omw_log "autojump install.py not found in $install_dir." "ERROR"
		return 1
	fi
	local backup_dir=""
	if [[ -e "$HOME/.autojump" ]]; then
		backup_dir="$HOME/.autojump-backup-$(date +%Y%m%d%H%M%S)"
		mv "$HOME/.autojump" "$backup_dir"
	fi
	# Run the install script
	local dirname
	dirname=$(dirname "$exec_path")
	omw_log "Running autojump installer in $dirname" "INFO"
	pushd "$dirname" >/dev/null
	local installer_shell="${SHELL:-/bin/bash}"
	case "$(basename "$installer_shell")" in
	bash | zsh | fish | tcsh) ;;
	*)
		omw_log "Unsupported or empty SHELL for autojump installer: ${SHELL:-unset}; using /bin/bash." "WARN"
		installer_shell="/bin/bash"
		;;
	esac
	if ! SHELL="$installer_shell" "./install.py" >/dev/null; then
		popd >/dev/null
		omw_log "autojump installation failed." "ERROR"
		omw_safe_rm_rf "$HOME/.autojump"
		[[ -n "$backup_dir" && -e "$backup_dir" ]] && mv "$backup_dir" "$HOME/.autojump"
		return 1
	fi
	popd >/dev/null
	[[ -n "$backup_dir" && -e "$backup_dir" ]] && omw_safe_rm_rf "$backup_dir"
	# add source autojump to shell config
	local zshrc="$HOME/.zshrc_custom"
	# [[ ! -f "$zshrc" ]] && zshrc="$HOME/.zshrc"
	if ! grep -q "autojump.sh" "$zshrc"; then
		printf '\n# Autojump\n[ -f "%s/.autojump/etc/profile.d/autojump.sh" ] && source "%s/.autojump/etc/profile.d/autojump.sh"\n' "$HOME" "$HOME" >>"$zshrc"
		omw_log "Added autojump source line to $zshrc" "INFO"
	fi
	omw_log "App '$appname' installed successfully." "SUCCESS"
	return 0
}

_omw_app_install_default() {
	local appname="$1"
	local install_dir="$2"
	local exec_path
	exec_path=$(find "$install_dir" -type f -name "$appname" | head -n 1)
	if [[ -z "$exec_path" ]]; then
		omw_log "Executable '$appname' not found in $install_dir." "ERROR"
		return 1
	fi
	[[ ! -x "$exec_path" ]] && {
		omw_log "Making '$appname' executable." "WARN"
		chmod +x "$exec_path"
	}
	ln -sf "$exec_path" "$SCRIPTS_BIN_PATH/$appname"
	omw_log "App '$appname' installed successfully." "SUCCESS"
	return 0
}

_omw_app_bin_dir_install_status() {
	local appname="$1"
	local install_dir="$2"
	local bin_dirs="${APP_BIN_DIRS[$appname]:-}"
	local exec_name="${APP_EXECUTABLE_NAME[$appname]:-}"
	local entry link_name total=0 linked=0

	if [[ ! -d "$install_dir" ]]; then
		if [[ -n "$exec_name" && -L "$SCRIPTS_BIN_PATH/$exec_name" ]]; then
			printf 'partial'
		else
			printf 'available'
		fi
		return 0
	fi

	while IFS= read -r -d $'\0' entry; do
		link_name="$SCRIPTS_BIN_PATH/$(basename "$entry")"
		((++total))
		if [[ -L "$link_name" && "$(readlink "$link_name")" == "$entry" ]]; then
			((++linked))
		fi
	done < <(_omw_app_find_bin_dir_entries "$install_dir" "$bin_dirs")

	if ((total > 0 && linked == total)); then
		printf 'installed'
	elif ((total > 0 || linked > 0)); then
		printf 'partial'
	else
		printf 'available'
	fi
}

_omw_app_find_bin_dir_entries() {
	local install_dir="$1"
	local bin_dirs="$2"
	local rel_dir dir found_dir

	for rel_dir in $bin_dirs; do
		dir="$install_dir/$rel_dir"
		if [[ -d "$dir" ]]; then
			find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -print0
			continue
		fi

		while IFS= read -r -d $'\0' found_dir; do
			find "$found_dir" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -print0
		done < <(find "$install_dir" -mindepth 2 -type d -path "*/$rel_dir" -print0)
	done
}

_omw_app_unlink_bin_dir_links() {
	local install_dir="$1"
	local link target

	[[ -d "$SCRIPTS_BIN_PATH" ]] || return 0
	while IFS= read -r -d $'\0' link; do
		target=$(readlink "$link")
		[[ "$target" == "$install_dir"/* ]] && rm -f "$link"
	done < <(find "$SCRIPTS_BIN_PATH" -mindepth 1 -maxdepth 1 -type l -print0)
}

_omw_app_link_bin_dirs() {
	local appname="$1"
	local install_dir="$2"
	local bin_dirs="${APP_BIN_DIRS[$appname]:-}"
	local entry link_name count=0

	while IFS= read -r -d $'\0' entry; do
		((++count))
	done < <(_omw_app_find_bin_dir_entries "$install_dir" "$bin_dirs")

	if ((count == 0)); then
		omw_log "No files found in configured bin dirs for '$appname': $bin_dirs" "ERROR"
		return 1
	fi

	_omw_app_unlink_bin_dir_links "$install_dir"
	count=0
	while IFS= read -r -d $'\0' entry; do
		if [[ -f "$entry" && ! -x "$entry" ]]; then
			omw_log "Making '$(basename "$entry")' executable." "WARN"
			chmod +x "$entry"
		fi
		link_name="$SCRIPTS_BIN_PATH/$(basename "$entry")"
		ln -sf "$entry" "$link_name"
		((++count))
	done < <(_omw_app_find_bin_dir_entries "$install_dir" "$bin_dirs")

	omw_log "Linked $count '$appname' bin entr$(if ((count == 1)); then printf 'y'; else printf 'ies'; fi) into $SCRIPTS_BIN_PATH." "SUCCESS"
	return 0
}

omw_hack_nerd_font_installed() {
	if command -v fc-match &>/dev/null; then
		fc-match "Hack Nerd Font" 2>/dev/null | grep -Eiq 'Hack[[:space:]]*Nerd|HackNerd'
		return $?
	fi

	[[ -d "$HOME/.local/share/fonts/OMW/HackNerdFont" || -d "$HOME/.fonts/OMW/HackNerdFont" ]]
}

_omw_app_install_hack-nerd-font() {
	local appname="$1"
	local install_dir="$2"
	local font_dir="$HOME/.local/share/fonts/OMW/HackNerdFont"
	local font_count

	if omw_hack_nerd_font_installed; then
		omw_log "Hack Nerd Font is already available." "SUCCESS"
		return 0
	fi

	if [[ -f /etc/centos-release || -f /etc/redhat-release ]]; then
		omw_log "CentOS/RHEL family detected; installing Hack Nerd Font for the current user." "INFO"
	else
		omw_log "Installing Hack Nerd Font for the current user." "INFO"
	fi

	font_count=$(find "$install_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) | wc -l | tr -d '[:space:]')
	if [[ "$font_count" == "0" ]]; then
		omw_log "No font files found in $install_dir." "ERROR"
		return 1
	fi

	mkdir -p "$font_dir"
	find "$install_dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -exec cp -f {} "$font_dir/" \;
	if command -v fc-cache &>/dev/null; then
		fc-cache -f "$font_dir"
	else
		omw_log "fc-cache is not available; font files were copied but font cache was not refreshed." "WARN"
	fi

	if command -v fc-match &>/dev/null && ! omw_hack_nerd_font_installed; then
		omw_log "Hack Nerd Font files were installed, but fontconfig did not report the font yet." "ERROR"
		return 1
	fi

	omw_log "Hack Nerd Font installed to $font_dir." "SUCCESS"
	return 0
}

omw_install_app() {
	local appname="$1"
	local force="${2:-false}"
	local version="${APP_VERSIONS[$appname]}"
	local url="${APP_URLS[$appname]}"
	local exec_name="${APP_EXECUTABLE_NAME[$appname]}"
	if [[ -z "$version" || -z "$url" || -z "$exec_name" ]]; then
		omw_log "Unknown app or incomplete app definition: $appname" "ERROR"
		return 1
	fi
	local install_dir="$APPS_INSTALL_PATH/$appname-$version"
	local pkg_path
	pkg_path="$PACKAGES_PATH/apps/$(basename "$url")"
	local bin_dirs="${APP_BIN_DIRS[$appname]:-}"
	local symlink_path="$SCRIPTS_BIN_PATH/$exec_name"
	local backup_dir=""
	local old_symlink_target=""

	omw_log "--- Installing App: $appname $version ---" "INFO"
	if [[ "$exec_name" == "special" && "$force" == "false" && "$(omw_app_install_status "$appname")" == "installed" ]]; then
		omw_log "$appname already installed. Skipping." "INFO"
		return 0
	fi
	if [[ "$exec_name" != "special" && -z "$bin_dirs" && -L "$symlink_path" && "$force" == "false" ]]; then
		omw_log "$appname already installed. Skipping." "INFO"
		return 0
	fi
	if [[ "$exec_name" != "special" && -n "$bin_dirs" && "$force" == "false" && "$(omw_app_install_status "$appname")" == "installed" ]]; then
		omw_log "$appname already installed. Skipping." "INFO"
		return 0
	fi
	if [[ "$force" == "true" ]]; then
		omw_log "Force reinstall for $appname." "WARN"
		if [[ -d "$install_dir" ]]; then
			backup_dir="${install_dir}-backup-$(date +%Y%m%d%H%M%S)"
			mv "$install_dir" "$backup_dir"
		fi
		if [[ "$exec_name" != "special" && -z "$bin_dirs" ]]; then
			[[ -L "$symlink_path" ]] && old_symlink_target=$(readlink "$symlink_path")
			rm -f "$symlink_path"
		fi
	fi
	omw_safe_rm_rf "$install_dir"

	mkdir -p "$install_dir"
	if ! omw_download_package "$url" "$pkg_path" || ! omw_extract_package "$pkg_path" "$install_dir" 0; then
		omw_safe_rm_rf "$install_dir"
		if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
			omw_log "Restoring previous app installation for $appname." "WARN"
			mv "$backup_dir" "$install_dir"
		fi
		[[ -n "$old_symlink_target" ]] && ln -sf "$old_symlink_target" "$symlink_path"
		return 1
	fi

	# Dynamically determine the executable name if set to "special"
	local install_status=0
	if declare -F "_omw_app_install_$appname" >/dev/null; then
		omw_log "Using dedicated install function for $appname." "DEBUG"
		"_omw_app_install_$appname" "$appname" "$install_dir" || install_status=$?
	elif [[ -n "$bin_dirs" ]]; then
		omw_log "Using bin-dir install function for $appname." "DEBUG"
		_omw_app_link_bin_dirs "$appname" "$install_dir" || install_status=$?
	else
		omw_log "Using default install function for $appname." "DEBUG"
		_omw_app_install_default "$exec_name" "$install_dir" || install_status=$?
	fi
	if ((install_status != 0)); then
		omw_safe_rm_rf "$install_dir"
		if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
			omw_log "Restoring previous app installation for $appname." "WARN"
			mv "$backup_dir" "$install_dir"
		fi
		[[ -n "$old_symlink_target" ]] && ln -sf "$old_symlink_target" "$symlink_path"
		return "$install_status"
	fi
	[[ -n "$backup_dir" && -d "$backup_dir" ]] && omw_safe_rm_rf "$backup_dir"
	omw_log "$appname installation complete." "SUCCESS"
}
