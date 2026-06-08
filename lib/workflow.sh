# shellcheck shell=bash
# Command workflow orchestration. CLI parsing stays in lib/cli.sh.

omw_workflow_run_build_all() {
	local sw version versions_str count=0 skipped=0
	for sw in "${SOFTWARE_LIST[@]}"; do
		if ! omw_software_build_all_enabled "$sw"; then
			((++skipped))
			omw_log "Skipping manual-only build target: $sw" "INFO"
			continue
		fi
		versions_str="${SOFTWARE_VERSIONS[$sw]}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			((++count))
			omw_log "Build target $count: $sw@$version" "INFO"
			omw_ensure_module_command || return 1
			module purge || return 1
			omw_build_software "$sw@$version" "$OMW_FORCE" "$OMW_REFRESH" || return 1
		done
	done
	((count > 0)) || {
		omw_log "No source build targets are defined in packages.sh." "ERROR"
		return 1
	}
	((skipped == 0)) || omw_log "Skipped $skipped manual-only source build target(s). Build them explicitly when needed." "INFO"
}

omw_workflow_run_all() {
	local app
	omw_log "Phase 1/4: build source software (${#SOFTWARE_LIST[@]} package definitions)" "INFO"
	omw_workflow_run_build_all || return 1
	omw_log "Phase 2/4: apply configs" "INFO"
	for app in "${CONFIG_TARGET_LIST[@]}"; do
		omw_configure "$app" "$OMW_FORCE" || return 1
	done
	omw_log "Phase 3/4: install prebuilt apps (${#APP_LIST[@]} app definitions)" "INFO"
	for app in "${APP_LIST[@]}"; do
		omw_install_app "$app" "$OMW_FORCE" || return 1
	done
	omw_log "Phase 4/4: install Node global packages (${#NODE_PACKAGE_LIST[@]} package definitions)" "INFO"
	omw_node_install_all
}

omw_workflow_run_build() {
	local target="$1" appname version versions_str v
	if [[ "$target" == "all" ]]; then
		omw_workflow_run_build_all
		return
	fi
	read -r appname version < <(omw_parse_target "$target")
	if [[ -z "$version" ]]; then
		omw_log "No version specified for '$appname'. Building all defined versions." "INFO"
		versions_str="${SOFTWARE_VERSIONS[$appname]:-}"
		[[ -n "$versions_str" ]] || {
			omw_log "No versions defined for '$appname' in packages.sh." "ERROR"
			return 1
		}
		for v in $versions_str; do
			omw_build_software "$appname@$v" "$OMW_FORCE" "$OMW_REFRESH" || return 1
		done
	else
		omw_build_software "$target" "$OMW_FORCE" "$OMW_REFRESH"
	fi
}

omw_workflow_run_build_prepare_all() {
	local sw version versions_str count=0 skipped=0
	declare -g -A OMW_BUILD_PREPARE_SEEN=()

	for sw in "${SOFTWARE_LIST[@]}"; do
		if ! omw_software_build_all_enabled "$sw"; then
			((++skipped))
			omw_log "Skipping manual-only build prepare target: $sw" "INFO"
			continue
		fi
		versions_str="${SOFTWARE_VERSIONS[$sw]}"
		[[ -z "$versions_str" ]] && continue
		for version in $versions_str; do
			((++count))
			omw_log "Build prepare target $count: $sw@$version" "INFO"
			omw_prepare_build_software "$sw@$version" || return 1
		done
	done
	((count > 0)) || {
		omw_log "No source build prepare targets are defined in packages.sh." "ERROR"
		return 1
	}
	((skipped == 0)) || omw_log "Skipped $skipped manual-only source build prepare target(s). Prepare them explicitly when needed." "INFO"
}

omw_workflow_run_build_prepare() {
	local target="$1" appname version versions_str v
	if [[ "$target" == "all" ]]; then
		omw_workflow_run_build_prepare_all
		return
	fi

	declare -g -A OMW_BUILD_PREPARE_SEEN=()
	read -r appname version < <(omw_parse_target "$target")
	if [[ -z "$version" ]]; then
		omw_log "No version specified for '$appname'. Preparing all defined versions." "INFO"
		versions_str="${SOFTWARE_VERSIONS[$appname]:-}"
		[[ -n "$versions_str" ]] || {
			omw_log "No versions defined for '$appname' in packages.sh." "ERROR"
			return 1
		}
		for v in $versions_str; do
			omw_prepare_build_software "$appname@$v" || return 1
		done
	else
		omw_prepare_build_software "$target"
	fi
}

omw_workflow_run_config() {
	local target="$1" cfg
	if [[ "$target" == "all" ]]; then
		for cfg in "${CONFIG_TARGET_LIST[@]}"; do
			omw_configure "$cfg" "$OMW_FORCE" || return 1
		done
	elif omw_contains_word "$target" "${CONFIG_TARGET_LIST[*]}"; then
		omw_configure "$target" "$OMW_FORCE"
	else
		omw_log "Invalid config target. Use: ${CONFIG_TARGET_LIST[*]}, all." "ERROR"
		return 1
	fi
}

omw_workflow_run_config_prepare() {
	local target="$1"
	if [[ "$target" == "all" ]]; then
		omw_prepare_all_config_packages "$OMW_FORCE"
	elif omw_contains_word "$target" "${CONFIG_TARGET_LIST[*]}"; then
		omw_prepare_config_package "$target" "$OMW_FORCE"
	else
		omw_log "Invalid config prepare target. Use: ${CONFIG_TARGET_LIST[*]}, all." "ERROR"
		return 1
	fi
}

omw_workflow_run_app_install_all() {
	local app

	for app in "${APP_LIST[@]}"; do
		omw_install_app "$app" "$OMW_FORCE" || return 1
	done
}

_omw_workflow_clean_path() {
	local path="$1"
	if [[ "$OMW_DRY_RUN" == "true" ]]; then
		printf 'Would remove: %s\n' "$path"
	else
		omw_safe_rm_rf "$path"
	fi
}

_omw_workflow_clean_packages() {
	_omw_workflow_clean_path "$PACKAGES_PATH"
	omw_config_clean_generated_assets "$OMW_DRY_RUN"
}

omw_workflow_run_clean() {
	local target="$1"
	omw_log "$([[ "$OMW_DRY_RUN" == "true" ]] && printf 'Previewing clean' || printf 'Cleaning') $target..."
	case "$target" in
	builds) omw_clean_source_builds "$OMW_DRY_RUN" ;;
	packages) _omw_workflow_clean_packages ;;
	config) omw_config_clean_generated_assets "$OMW_DRY_RUN" ;;
	installs) omw_clean_software_installs "$OMW_DRY_RUN" ;;
	apps) omw_clean_app_installs "$OMW_DRY_RUN" ;;
	node) omw_node_clean_generated_assets "$OMW_DRY_RUN" ;;
	all)
		omw_clean_source_builds "$OMW_DRY_RUN"
		omw_config_clean_generated_assets "$OMW_DRY_RUN"
		omw_clean_software_installs "$OMW_DRY_RUN"
		omw_clean_app_installs "$OMW_DRY_RUN"
		;;
	*)
		omw_log "Invalid clean target. Use: builds, packages, config, installs, apps, node, all." "ERROR"
		return 1
		;;
	esac
	omw_log "$([[ "$OMW_DRY_RUN" == "true" ]] && printf 'Clean preview complete.' || printf 'Clean complete.')" "SUCCESS"
}
