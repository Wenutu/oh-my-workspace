# shellcheck shell=bash
# Transaction helpers for OMW-managed filesystem changes.

omw_tx_begin() {
	if [[ "${OMW_TX_ACTIVE:-false}" == "true" ]]; then
		omw_log "A transaction is already active." "ERROR"
		return 1
	fi
	OMW_TX_ACTIVE=true
	OMW_TX_TMP_PATHS=()
	OMW_TX_INTERNAL_PATHS=()
	OMW_TX_INTERNAL_BACKUPS=()
	OMW_TX_EXTERNAL_PATHS=()
	OMW_TX_EXTERNAL_BACKUPS=()
}

omw_tx_track_internal_tmp() {
	local path="$1"
	_omw_fs_is_internal_path "$path" || {
		omw_log "Refusing to track non-OMW temporary path: $path" "ERROR"
		return 1
	}
	OMW_TX_TMP_PATHS+=("$path")
}

omw_tx_backup_internal() {
	local path="$1"
	local backup=""
	_omw_fs_is_internal_path "$path" || {
		omw_log "Refusing to back up non-OMW internal path: $path" "ERROR"
		return 1
	}
	if [[ -e "$path" || -L "$path" ]]; then
		backup="${path}.tx-backup-$$"
		omw_safe_rm_rf "$backup"
		mv "$path" "$backup"
	fi
	OMW_TX_INTERNAL_PATHS+=("$path")
	OMW_TX_INTERNAL_BACKUPS+=("$backup")
}

omw_tx_backup_external() {
	local path="$1"
	local reason="${2:-config}"
	local backup=""
	if [[ -e "$path" || -L "$path" ]]; then
		backup=$(_omw_common_backup_path_once "$path" "$reason") || return 1
	fi
	OMW_TX_EXTERNAL_PATHS+=("$path")
	OMW_TX_EXTERNAL_BACKUPS+=("$backup")
}

omw_tx_commit() {
	local backup
	[[ "${OMW_TX_ACTIVE:-false}" == "true" ]] || return 0
	for backup in ${OMW_TX_INTERNAL_BACKUPS[@]+"${OMW_TX_INTERNAL_BACKUPS[@]}"}; do
		[[ -n "$backup" ]] && omw_safe_rm_rf "$backup"
	done
	for backup in ${OMW_TX_TMP_PATHS[@]+"${OMW_TX_TMP_PATHS[@]}"}; do
		[[ -e "$backup" || -L "$backup" ]] && omw_safe_rm_rf "$backup"
	done
	OMW_TX_ACTIVE=false
}

omw_tx_rollback() {
	local i path backup internal_count=0 external_count=0
	[[ "${OMW_TX_ACTIVE:-false}" == "true" ]] || return 0
	[[ -z "${OMW_TX_INTERNAL_PATHS+x}" ]] || internal_count=${#OMW_TX_INTERNAL_PATHS[@]}
	for ((i = internal_count - 1; i >= 0; i--)); do
		path="${OMW_TX_INTERNAL_PATHS[$i]}"
		backup="${OMW_TX_INTERNAL_BACKUPS[$i]}"
		[[ -e "$path" || -L "$path" ]] && omw_safe_rm_rf "$path"
		[[ -n "$backup" && ( -e "$backup" || -L "$backup" ) ]] && mv "$backup" "$path"
	done
	[[ -z "${OMW_TX_EXTERNAL_PATHS+x}" ]] || external_count=${#OMW_TX_EXTERNAL_PATHS[@]}
	for ((i = external_count - 1; i >= 0; i--)); do
		path="${OMW_TX_EXTERNAL_PATHS[$i]}"
		backup="${OMW_TX_EXTERNAL_BACKUPS[$i]}"
		if [[ -n "$backup" && ( -e "$backup" || -L "$backup" ) ]]; then
			[[ -e "$path" || -L "$path" ]] && mv "$path" "${backup}.failed-$$"
			cp -a "$backup" "$path"
		elif [[ -e "$path" || -L "$path" ]]; then
			mkdir -p "$OMW_HOME/backups"
			mv "$path" "$OMW_HOME/backups/rollback-created-$(date +%Y%m%d%H%M%S)-$(basename "$path")"
		fi
	done
	for path in ${OMW_TX_TMP_PATHS[@]+"${OMW_TX_TMP_PATHS[@]}"}; do
		[[ -e "$path" || -L "$path" ]] && omw_safe_rm_rf "$path"
	done
	OMW_TX_ACTIVE=false
}
