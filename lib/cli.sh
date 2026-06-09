# shellcheck shell=bash

_omw_cli_help_supports_color() {
	[[ -t 1 && -z "${NO_COLOR:-}" && "${OMW_NO_COLOR:-false}" != "true" ]]
}

_omw_cli_help_color() {
	local code="$1"
	local text="$2"
	if _omw_cli_help_supports_color; then
		printf '\033[%sm%s\033[0m' "$code" "$text"
	else
		printf '%s' "$text"
	fi
}

_omw_cli_help_section() {
	printf '\n'
	_omw_cli_help_color "1;36" "$1"
	printf '\n'
}

_omw_cli_help_command() {
	local command="$1"
	local description="$2"
	local width=38
	printf '  '
	_omw_cli_help_color "1;32" "$command"
	printf '%*s%s\n' "$((width - ${#command}))" "" "$description"
}

_omw_cli_help_banner() {
	_omw_cli_help_color "1;36" '  ___  __  __ _       _'
	printf '\n'
	_omw_cli_help_color "1;36" ' / _ \|  \/  \ \  /\/ /'
	printf '\n'
	_omw_cli_help_color "1;36" ' \___/|_|\/|_|\ \/  \/'
	printf '\n'
	printf '\n'
}

_omw_cli_print_main_help() {
	_omw_cli_help_banner
	_omw_cli_help_color "1;37" "  Oh My Workspace"
	printf '\n'
	printf '  Build tools, install apps, apply configs, and pack offline workspaces.\n'

	_omw_cli_help_section "Usage"
	printf '  ./omw <command> [options]\n'

	_omw_cli_help_section "Setup"
	_omw_cli_help_command "init" "Add OMW env sourcing to ~/.bashrc"
	_omw_cli_help_command "all [--force] [--refresh]" "Run the complete workspace setup"

	_omw_cli_help_section "Packages"
	_omw_cli_help_command "build <target|all>" "Build source software"
	_omw_cli_help_command "build prepare <target|all>" "Download build packages"
	_omw_cli_help_command "app <action>" "Install prebuilt apps"
	_omw_cli_help_command "node <action>" "Manage npm cache and global packages"

	_omw_cli_help_section "Configuration"
	_omw_cli_help_command "config <target|all>" "Apply shell and editor configs"
	_omw_cli_help_command "config prepare <target|all>" "Prepare config assets and archives"

	_omw_cli_help_section "Offline Workflow"
	_omw_cli_help_command "offline pack [--force]" "Create an offline deployment bundle"
	_omw_cli_help_command "offline verify" "Verify offline assets"
	_omw_cli_help_command "upgrade <bundle|dir>" "Upgrade OMW from an offline bundle"

	_omw_cli_help_section "Maintenance"
	_omw_cli_help_command "status [installed]" "Show installable or installed items"
	_omw_cli_help_command "doctor [profile]" "Check local OMW runtime health"
	_omw_cli_help_command "update check" "Check upstream package and Vim plugin updates"
	_omw_cli_help_command "clean <target> [--dry-run]" "Remove generated artifacts"
	_omw_cli_help_command "help [command [action]]" "Show contextual help"

	_omw_cli_help_section "Quick Start"
	_omw_cli_help_command "omw status" "Inspect available workspace packages"
	_omw_cli_help_command "omw all" "Install the complete workspace"
	_omw_cli_help_command "omw help <command>" "Explore a command in detail"

	_omw_cli_help_section "Global Options"
	_omw_cli_help_command "-h, --help" "Show contextual help"
	_omw_cli_help_command "--version" "Show OMW version"
	_omw_cli_help_command "--no-color" "Disable colored output"
}

_omw_cli_print_help() {
	local topic="${1:-}"
	local action="${2:-}"

	case "$topic:$action" in
	:*) _omw_cli_print_main_help ;;
	init:*) cat <<-EOF ;;
		Usage: ./omw init

		Add OMW env sourcing to ~/.bashrc. This does not install packages.
		EOF
	all:*) cat <<-EOF ;;
		Usage: ./omw all [--force] [--refresh]

		Run the complete workspace setup:
		  build source tools -> apply configs -> install apps -> install Node packages

		Options:
		  --force    Rebuild, reinstall, or replace local config files
		  --refresh  Regenerate modulefiles without rebuilding source tools
		EOF
	build:prepare) cat <<-EOF ;;
		Usage: ./omw build prepare <software[@version]|all>

		Download source archives and build dependency packages for a target and
		its declared dependency chain. local targets prepare the RPM bundle.

		Example:
		  ./omw build prepare vim
		  ./omw build prepare vim@9.1.1766
		EOF
	build:*) cat <<-EOF ;;
		Usage:
		  ./omw build <software[@version]|all> [--force] [--refresh]
		  ./omw build prepare <software[@version]|all>

		Build source software. Without @version, all declared versions are built.
		Use build prepare to download build packages without compiling.

		Options:
		  --force    Rebuild an installed target
		  --refresh  Regenerate modulefiles without rebuilding

		Example:
		  ./omw build vim --force
		EOF
	app:install) cat <<-EOF ;;
		Usage: ./omw app install <app> [--force]

		Install one prebuilt app.

		Example:
		  ./omw app install exa
		EOF
	app:*) cat <<-EOF ;;
		Usage:
		  ./omw app install <app> [--force]
		  ./omw app install-all [--force]

		Install one or all declared prebuilt apps.
		EOF
	node:*) cat <<-EOF ;;
		Usage:
		  ./omw node pack
		  ./omw node verify
		  ./omw node restore-cache
		  ./omw node install <alias>
		  ./omw node install-all

		Manage the offline npm cache and declared global packages.
		EOF
	config:prepare) cat <<-EOF ;;
		Usage: ./omw config prepare <tmux|vim|zsh|all> [--force]

		Prepare config assets and archives. --force refreshes generated assets.
		EOF
	config:*) cat <<-EOF ;;
		Usage:
		  ./omw config <tmux|vim|zsh|all> [--force]
		  ./omw config prepare <tmux|vim|zsh|all> [--force]

		Apply offline configs or prepare config archives on an online machine.
		EOF
	offline:*) cat <<-EOF ;;
		Usage:
		  ./omw offline pack [--force]
		  ./omw offline verify

		Create a portable bundle or verify its offline assets.
		--force refreshes generated config assets before packing.
		EOF
	upgrade:*) cat <<-EOF ;;
		Usage: ./omw upgrade <bundle.tar.gz|extracted-dir> [--dry-run] [--replace-packages]

		Upgrade this OMW checkout from an offline bundle archive or extracted bundle
		directory. By default, package assets are merged into packages/ and stale
		local package assets are preserved. Use --replace-packages to replace
		packages/ with the bundle's packages/ directory.

		Options:
		  --dry-run           Preview updated paths without changing files
		  --replace-packages  Replace packages/ instead of merging package assets
		EOF
	clean:*) cat <<-EOF ;;
		Usage: ./omw clean <builds|packages|config|installs|apps|node|all> [--dry-run]

		Remove generated artifacts. Use --dry-run to preview removed paths.
		The all target preserves deployment packages so './omw all' can restore the workspace.
		Use the packages target when downloaded and packed caches should also be removed.
		EOF
	status:*) cat <<-EOF ;;
		Usage: ./omw status [installed]

		Show installable items, or limit the view to installed items.
		EOF
	doctor:*) cat <<-EOF ;;
		Usage: ./omw doctor [base|build|local|app|config|config-prepare|config-prepare-vim|node|offline]

		Check local OMW runtime health without modifying files. The optional profile
		controls which system dependency set is checked; base is the default.
		EOF
	update:*) cat <<-EOF ;;
		Usage: ./omw update check

		Check source software, apps, Node packages, Coc extensions, and Vim
		Git plugins for upstream updates. Vim plugins compare local and remote
		commits; package definitions remain pinned until changed intentionally.
		EOF
	*)
		omw_log "Unknown help topic: $topic${action:+ $action}" "ERROR"
		return 1
		;;
	esac
}

_omw_cli_error() {
	omw_log "$1" "ERROR"
	return 1
}

_omw_cli_parse_leaf() {
	local allowed="$1"
	shift
	OMW_POSITIONAL=()
	while (($#)); do
		case "$1" in
		--force)
			[[ " $allowed " == *" force "* ]] || { _omw_cli_error "Option --force is not valid for '$OMW_COMMAND'."; return 1; }
			OMW_FORCE=true
			;;
		--refresh)
			[[ " $allowed " == *" refresh "* ]] || { _omw_cli_error "Option --refresh is not valid for '$OMW_COMMAND'."; return 1; }
			OMW_REFRESH=true
			;;
		--dry-run)
			[[ " $allowed " == *" dry-run "* ]] || { _omw_cli_error "Option --dry-run is not valid for '$OMW_COMMAND'."; return 1; }
			OMW_DRY_RUN=true
			;;
		--replace-packages)
			[[ " $allowed " == *" replace-packages "* ]] || { _omw_cli_error "Option --replace-packages is not valid for '$OMW_COMMAND'."; return 1; }
			OMW_REPLACE_PACKAGES=true
			;;
		--*) _omw_cli_error "Unknown option for '$OMW_COMMAND': $1"; return 1 ;;
		*) OMW_POSITIONAL+=("$1") ;;
		esac
		shift
	done
}

_omw_cli_require_positionals() {
	local usage="$1"
	local min="$2"
	local max="$3"
	local count="${#OMW_POSITIONAL[@]}"
	if ((count < min || count > max)); then
		_omw_cli_error "Invalid arguments. Use: $usage"
		return 1
	fi
}

_omw_cli_parse() {
	local -a args=()
	local arg first second
	OMW_COMMAND=""
	OMW_TARGET=""
	OMW_FORCE=false
	OMW_REFRESH=false
	OMW_DRY_RUN=false
	OMW_REPLACE_PACKAGES=false
	OMW_HELP=false
	OMW_NO_COLOR="${OMW_NO_COLOR:-false}"

	for arg in "$@"; do
		case "$arg" in
		-h | --help) OMW_HELP=true ;;
		--version) OMW_COMMAND="version" ;;
		--no-color) OMW_NO_COLOR=true ;;
		*) args+=("$arg") ;;
		esac
	done
	export OMW_NO_COLOR

	if [[ "$OMW_COMMAND" == "version" ]]; then
		((${#args[@]} == 0)) || { _omw_cli_error "--version does not accept a command."; return 1; }
		return 0
	fi
	if ((${#args[@]} == 0)); then
		OMW_COMMAND="help"
		return 0
	fi
	if [[ "$OMW_HELP" == "true" ]]; then
		OMW_HELP_TOPIC="${args[0]:-}"
		OMW_HELP_ACTION="${args[1]:-}"
		OMW_COMMAND="help"
		return 0
	fi

	first="${args[0]}"
	case "$first" in
	help)
		OMW_COMMAND="help"
		((${#args[@]} <= 3)) || { _omw_cli_error "Too many help topics."; return 1; }
		OMW_HELP_TOPIC="${args[1]:-}"
		OMW_HELP_ACTION="${args[2]:-}"
		return 0
		;;
	init)
		OMW_COMMAND="init"
		_omw_cli_parse_leaf "" "${args[@]:1}" || return 1
		_omw_cli_require_positionals "./omw init" 0 0 || return 1
		;;
	all)
		OMW_COMMAND="all"
		_omw_cli_parse_leaf "force refresh" "${args[@]:1}" || return 1
		_omw_cli_require_positionals "./omw all [--force] [--refresh]" 0 0 || return 1
		;;
	build)
		if [[ "${args[1]:-}" == "prepare" ]]; then
			OMW_COMMAND="build prepare"
			_omw_cli_parse_leaf "" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw build prepare <software[@version]|all>" 1 1 || return 1
		else
			OMW_COMMAND="build"
			_omw_cli_parse_leaf "force refresh" "${args[@]:1}" || return 1
			_omw_cli_require_positionals "./omw build <software[@version]|all> [--force] [--refresh]" 1 1 || return 1
		fi
		OMW_TARGET="${OMW_POSITIONAL[0]}"
		;;
	app)
		second="${args[1]:-}"
		case "$second" in
		install)
			OMW_COMMAND="app install"
			_omw_cli_parse_leaf "force" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw app install <app> [--force]" 1 1 || return 1
			OMW_TARGET="${OMW_POSITIONAL[0]}"
			;;
		install-all)
			OMW_COMMAND="app install-all"
			_omw_cli_parse_leaf "force" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw app install-all [--force]" 0 0 || return 1
			;;
		*) _omw_cli_error "Invalid app action. Use: ./omw app install <app> or ./omw app install-all."; return 1 ;;
		esac
		;;
	node)
		second="${args[1]:-}"
		case "$second" in
		pack | verify | restore-cache | install-all)
			OMW_COMMAND="node $second"
			_omw_cli_parse_leaf "" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw node $second" 0 0 || return 1
			;;
		install)
			OMW_COMMAND="node install"
			_omw_cli_parse_leaf "" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw node install <alias>" 1 1 || return 1
			OMW_TARGET="${OMW_POSITIONAL[0]}"
			;;
		*) _omw_cli_error "Invalid node action. Use: pack, verify, restore-cache, install <alias>, or install-all."; return 1 ;;
		esac
		;;
	config)
		if [[ "${args[1]:-}" == "prepare" ]]; then
			OMW_COMMAND="config prepare"
			_omw_cli_parse_leaf "force" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw config prepare <target|all> [--force]" 1 1 || return 1
		else
			OMW_COMMAND="config"
			_omw_cli_parse_leaf "force" "${args[@]:1}" || return 1
			_omw_cli_require_positionals "./omw config <target|all> [--force]" 1 1 || return 1
		fi
		OMW_TARGET="${OMW_POSITIONAL[0]}"
		;;
	offline)
		second="${args[1]:-}"
		case "$second" in
		pack)
			OMW_COMMAND="offline pack"
			_omw_cli_parse_leaf "force" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw offline pack [--force]" 0 0 || return 1
			;;
		verify)
			OMW_COMMAND="offline verify"
			_omw_cli_parse_leaf "" "${args[@]:2}" || return 1
			_omw_cli_require_positionals "./omw offline verify" 0 0 || return 1
			;;
		*) _omw_cli_error "Invalid offline action. Use: ./omw offline pack or ./omw offline verify."; return 1 ;;
		esac
		;;
	upgrade)
		OMW_COMMAND="upgrade"
		_omw_cli_parse_leaf "dry-run replace-packages" "${args[@]:1}" || return 1
		_omw_cli_require_positionals "./omw upgrade <bundle.tar.gz|extracted-dir> [--dry-run] [--replace-packages]" 1 1 || return 1
		if [[ "${OMW_POSITIONAL[0]}" == /* ]]; then
			OMW_TARGET="${OMW_POSITIONAL[0]}"
		else
			OMW_TARGET="$PWD/${OMW_POSITIONAL[0]}"
		fi
		;;
	status)
		OMW_COMMAND="status"
		_omw_cli_parse_leaf "" "${args[@]:1}" || return 1
		_omw_cli_require_positionals "./omw status [installed]" 0 1 || return 1
		OMW_TARGET="${OMW_POSITIONAL[0]:-}"
		[[ -z "$OMW_TARGET" || "$OMW_TARGET" == "installed" ]] || { _omw_cli_error "Invalid status view. Use: ./omw status [installed]"; return 1; }
		;;
	doctor)
		OMW_COMMAND="doctor"
		_omw_cli_parse_leaf "" "${args[@]:1}" || return 1
		_omw_cli_require_positionals "./omw doctor [profile]" 0 1 || return 1
		OMW_TARGET="${OMW_POSITIONAL[0]:-base}"
		;;
	update)
		OMW_COMMAND="update check"
		_omw_cli_parse_leaf "" "${args[@]:1}" || return 1
		_omw_cli_require_positionals "./omw update check" 1 1 || return 1
		[[ "${OMW_POSITIONAL[0]}" == "check" ]] || { _omw_cli_error "Invalid update action. Use: ./omw update check"; return 1; }
		;;
	clean)
		OMW_COMMAND="clean"
		_omw_cli_parse_leaf "dry-run" "${args[@]:1}" || return 1
		_omw_cli_require_positionals "./omw clean <target> [--dry-run]" 1 1 || return 1
		OMW_TARGET="${OMW_POSITIONAL[0]}"
		;;
	-*) _omw_cli_error "Legacy or unknown option: $first. Run './omw --help' for the new command syntax."; return 1 ;;
	*) _omw_cli_error "Invalid command: $first. Run './omw --help' for usage."; return 1 ;;
	esac

}

_omw_cli_is_meta_command() {
	[[ "$OMW_COMMAND" == "help" || "$OMW_COMMAND" == "version" ]]
}

_omw_cli_is_read_only_command() {
	case "$OMW_COMMAND" in
	status | doctor | "offline verify" | "update check") return 0 ;;
	upgrade) [[ "${OMW_DRY_RUN:-false}" == "true" ]] ;;
	*) return 1 ;;
	esac
}

_omw_cli_check_sys_deps() {
	case "$OMW_COMMAND" in
	init | status | doctor | "update check" | clean) return 0 ;;
	build)
		if [[ "$OMW_TARGET" == "local" || "$OMW_TARGET" == "local@"* || "$OMW_TARGET" == "all" ]]; then
			omw_check_sys_deps local
		else
			omw_check_sys_deps build
		fi
		;;
	"build prepare") omw_check_sys_deps download ;;
	"app install" | "app install-all") omw_check_sys_deps app ;;
	config) omw_check_sys_deps config ;;
	"config prepare")
		if [[ "$OMW_TARGET" == "vim" || "$OMW_TARGET" == "all" ]]; then omw_check_sys_deps config-prepare-vim; else omw_check_sys_deps config-prepare; fi
		;;
	node\ *) omw_check_sys_deps node ;;
	"offline pack") omw_check_sys_deps offline ;;
	"offline verify") omw_check_sys_deps base ;;
	upgrade) omw_check_sys_deps base ;;
	all) omw_check_sys_deps offline ;;
	esac
}

_omw_cli_run_command() {
	case "$OMW_COMMAND" in
	help) _omw_cli_print_help "${OMW_HELP_TOPIC:-}" "${OMW_HELP_ACTION:-}" ;;
	version) printf 'OMW %s\n' "$OMW_VERSION" ;;
	init) omw_init_shell_env || exit 1 ;;
	all) omw_workflow_run_all || exit 1 ;;
	build) omw_workflow_run_build "$OMW_TARGET" || exit 1 ;;
	"build prepare") omw_workflow_run_build_prepare "$OMW_TARGET" || exit 1 ;;
	"app install") omw_install_app "$OMW_TARGET" "$OMW_FORCE" || exit 1 ;;
	"app install-all") omw_workflow_run_app_install_all || exit 1 ;;
	"node pack") omw_node_pack || exit 1 ;;
	"node verify") omw_node_verify || exit 1 ;;
	"node restore-cache") omw_node_restore_cache || exit 1 ;;
	"node install") omw_node_install "$OMW_TARGET" || exit 1 ;;
	"node install-all") omw_node_install_all || exit 1 ;;
	config) omw_workflow_run_config "$OMW_TARGET" || exit 1 ;;
	"config prepare") omw_workflow_run_config_prepare "$OMW_TARGET" || exit 1 ;;
	"offline pack") omw_create_offline_bundle "$OMW_FORCE" || exit 1 ;;
	"offline verify") omw_verify_offline || exit 1 ;;
	upgrade) omw_upgrade_from_bundle "$OMW_TARGET" "$OMW_DRY_RUN" "$OMW_REPLACE_PACKAGES" || exit 1 ;;
	status) [[ "$OMW_TARGET" == "installed" ]] && omw_print_status "false" || omw_print_status "true" ;;
	doctor) omw_doctor "$OMW_TARGET" || exit 1 ;;
	"update check") omw_check_updates || exit 1 ;;
	clean) omw_workflow_run_clean "$OMW_TARGET" || exit 1 ;;
	esac
}
