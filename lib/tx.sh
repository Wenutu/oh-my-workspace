# shellcheck shell=bash
# Transaction helpers for OMW-managed and approved HOME filesystem changes.

_omw_tx_external_path_allowed() {
	local path="$1"
	local normalized normalized_home
	normalized=$(_omw_fs_normalize_path "$path") || return 1
	normalized_home=$(_omw_fs_normalize_path "$HOME") || return 1
	case "$normalized" in
	"$normalized_home/.bashrc" | "$normalized_home/.zshrc" | "$normalized_home/.vimrc" | "$normalized_home/.tmux.conf" | "$normalized_home/.tmux.conf.local" | "$normalized_home/.oh-my-zsh" | "$normalized_home/.autojump" | "$normalized_home/.local/share/fonts/OMW" | "$normalized_home/.local/share/fonts/OMW/"*) return 0 ;;
	*) return 1 ;;
	esac
}

_omw_tx_path_scope() {
	local path="$1"
	if _omw_fs_is_internal_path "$path"; then
		printf 'internal\n'
	elif _omw_tx_external_path_allowed "$path"; then
		printf 'external\n'
	else
		return 1
	fi
}

_omw_tx_journal_append() {
	local scope="$1" path="$2" backup="${3:-}"
	[[ -n "${OMW_TX_JOURNAL_DIR:-}" ]] || return 0
	printf '%s\t%s\t%s\n' "$scope" "$path" "$backup" >>"$OMW_TX_JOURNAL_DIR/records"
}

_omw_tx_journal_finish() {
	local state="$1"
	[[ -n "${OMW_TX_JOURNAL_DIR:-}" ]] || return 0
	printf '%s\n' "$state" >"$OMW_TX_JOURNAL_DIR/state" || return 1
	omw_safe_rm_rf "$OMW_TX_JOURNAL_DIR" || return 1
	OMW_TX_JOURNAL_DIR=""
}

_omw_tx_cleanup_finished_journal() {
	local journal="$1"
	local scope path backup
	while IFS=$'\t' read -r scope path backup; do
		if [[ "$scope" == "tmp" ]]; then
			[[ ! -e "$path" && ! -L "$path" ]] || omw_safe_rm_rf "$path" || return 1
		elif [[ -n "$backup" ]]; then
			[[ ! -e "$backup" && ! -L "$backup" ]] || omw_safe_rm_rf "$backup" || return 1
		fi
	done <"$journal/records"
	omw_safe_rm_rf "$journal"
}

omw_tx_recover_pending() {
	local journal state scope path backup
	[[ -d "${TRANSACTIONS_PATH:-}" ]] || return 0
	for journal in "$TRANSACTIONS_PATH"/*; do
		[[ -d "$journal" ]] || continue
		state=$(cat "$journal/state" 2>/dev/null || true)
		if [[ "$state" == "committed" || "$state" == "rolled-back" ]]; then
			_omw_tx_cleanup_finished_journal "$journal" || return 1
			continue
		fi
		[[ "$state" == "active" ]] || continue
		omw_log "Recovering interrupted transaction: $(basename "$journal")" "WARN"
		OMW_TX_ACTIVE=true
		OMW_TX_JOURNAL_DIR="$journal"
		OMW_TX_PATHS=()
		OMW_TX_BACKUPS=()
		OMW_TX_SCOPES=()
		OMW_TX_TMP_PATHS=()
		while IFS=$'\t' read -r scope path backup; do
			[[ -n "$scope" && -n "$path" ]] || continue
			if [[ "$scope" == "tmp" ]]; then
				OMW_TX_TMP_PATHS+=("$path")
			else
				OMW_TX_SCOPES+=("$scope")
				OMW_TX_PATHS+=("$path")
				OMW_TX_BACKUPS+=("$backup")
			fi
		done <"$journal/records"
		omw_tx_rollback || return 1
	done
}

omw_tx_begin() {
	if [[ "${OMW_TX_ACTIVE:-false}" == "true" ]]; then
		omw_log "A transaction is already active." "ERROR"
		return 1
	fi
	mkdir -p "$TRANSACTIONS_PATH" || return 1
	OMW_TX_JOURNAL_DIR="$TRANSACTIONS_PATH/$(date +%Y%m%d%H%M%S)-$$"
	mkdir -p "$OMW_TX_JOURNAL_DIR" || return 1
	: >"$OMW_TX_JOURNAL_DIR/records"
	printf 'active\n' >"$OMW_TX_JOURNAL_DIR/state"
	OMW_TX_ACTIVE=true
	OMW_TX_TMP_PATHS=()
	OMW_TX_PATHS=()
	OMW_TX_BACKUPS=()
	OMW_TX_SCOPES=()
}

omw_tx_track_internal_tmp() {
	local path="$1"
	_omw_fs_is_internal_path "$path" || {
		omw_log "Refusing to track non-OMW temporary path: $path" "ERROR"
		return 1
	}
	OMW_TX_TMP_PATHS+=("$path")
	_omw_tx_journal_append tmp "$path"
}

omw_tx_backup_path() {
	local path="$1"
	local scope backup="" existing
	[[ "$path" != *$'\t'* && "$path" != *$'\n'* ]] || {
		omw_log "Refusing transaction path with control separators: $path" "ERROR"
		return 1
	}
	for existing in ${OMW_TX_PATHS[@]+"${OMW_TX_PATHS[@]}"}; do
		[[ "$existing" == "$path" ]] && return 0
	done
	scope=$(_omw_tx_path_scope "$path") || {
		omw_log "Refusing to back up unmanaged transaction path: $path" "ERROR"
		return 1
	}
	if [[ -e "$path" || -L "$path" ]]; then
		if [[ "$scope" == "internal" ]]; then
			backup="${path}.tx-backup-$$"
			_omw_tx_journal_append "$scope" "$path" "$backup" || return 1
			omw_safe_rm_rf "$backup" || return 1
			mv "$path" "$backup" || return 1
		else
			mkdir -p "$OMW_HOME/backups/transactions" || return 1
			backup=$(mktemp -d "$OMW_HOME/backups/transactions/path-XXXXXX") || return 1
			cp -a "$path" "$backup/original" || return 1
			_omw_tx_journal_append "$scope" "$path" "$backup" || return 1
		fi
	else
		_omw_tx_journal_append "$scope" "$path" "" || return 1
	fi
	OMW_TX_PATHS+=("$path")
	OMW_TX_BACKUPS+=("$backup")
	OMW_TX_SCOPES+=("$scope")
}

omw_tx_backup_internal() {
	omw_tx_backup_path "$1"
}

omw_tx_backup_if_active() {
	[[ "${OMW_TX_ACTIVE:-false}" == "true" ]] || return 0
	omw_tx_backup_path "$1"
}

omw_tx_commit() {
	local backup status=0
	[[ "${OMW_TX_ACTIVE:-false}" == "true" ]] || return 0
	if [[ -n "${OMW_TX_JOURNAL_DIR:-}" ]]; then
		printf 'committed\n' >"$OMW_TX_JOURNAL_DIR/state" || return 1
	fi
	for backup in ${OMW_TX_BACKUPS[@]+"${OMW_TX_BACKUPS[@]}"}; do
		[[ -z "$backup" ]] || omw_safe_rm_rf "$backup" || status=1
	done
	for backup in ${OMW_TX_TMP_PATHS[@]+"${OMW_TX_TMP_PATHS[@]}"}; do
		[[ ! -e "$backup" && ! -L "$backup" ]] || omw_safe_rm_rf "$backup" || status=1
	done
	OMW_TX_ACTIVE=false
	if ((status == 0)); then
		_omw_tx_journal_finish committed || status=1
	fi
	return "$status"
}

omw_tx_rollback() {
	local i path backup scope count=0 status=0
	[[ "${OMW_TX_ACTIVE:-false}" == "true" ]] || return 0
	[[ -z "${OMW_TX_PATHS+x}" ]] || count=${#OMW_TX_PATHS[@]}
	for ((i = count - 1; i >= 0; i--)); do
		path="${OMW_TX_PATHS[$i]}"
		backup="${OMW_TX_BACKUPS[$i]}"
		scope="${OMW_TX_SCOPES[$i]}"
		if [[ "$scope" == "internal" ]]; then
			if [[ -n "$backup" && ( -e "$backup" || -L "$backup" ) ]]; then
				[[ ! -e "$path" && ! -L "$path" ]] || omw_safe_rm_rf "$path" || status=1
				mv "$backup" "$path" || status=1
			elif [[ -z "$backup" ]]; then
				[[ ! -e "$path" && ! -L "$path" ]] || omw_safe_rm_rf "$path" || status=1
			fi
		else
			if [[ -n "$backup" && ( -e "$backup/original" || -L "$backup/original" ) ]]; then
				[[ ! -e "$path" && ! -L "$path" ]] || rm -rf -- "$path" || status=1
				mkdir -p "$(dirname "$path")" || status=1
				cp -a "$backup/original" "$path" || status=1
			elif [[ -z "$backup" ]]; then
				[[ ! -e "$path" && ! -L "$path" ]] || rm -rf -- "$path" || status=1
			fi
			[[ -z "$backup" ]] || omw_safe_rm_rf "$backup" || status=1
		fi
	done
	for path in ${OMW_TX_TMP_PATHS[@]+"${OMW_TX_TMP_PATHS[@]}"}; do
		[[ ! -e "$path" && ! -L "$path" ]] || omw_safe_rm_rf "$path" || status=1
	done
	OMW_TX_ACTIVE=false
	((status == 0)) || omw_log "Transaction rollback left one or more paths unrestored." "ERROR"
	if ((status == 0)); then
		_omw_tx_journal_finish rolled-back || status=1
	fi
	return "$status"
}
