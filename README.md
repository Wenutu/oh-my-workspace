# OMW (Oh My Workspace)

A self-contained development environment manager for Linux. OMW builds common developer tools from source, installs prebuilt apps, wires environment modules automatically, and can produce a fully offline bundle for air-gapped machines.

## Highlights
- Source builds with dependency orchestration and modulefiles
- Prebuilt app installation with simple symlink exposure
- Offline bundle generation and verification
- Local system RPM extraction to a private prefix
- Clean logs, spinners, and colored status output

## Requirements
- Linux with Bash
- System tools: `wget tar make git rpm2cpio cpio sed find nproc yumdownloader unzip`
- Environment Modules (Modules or Lmod) providing the `module` command
- Network access (unless using an offline bundle)

Tip: On RHEL/CentOS-like systems, install `environment-modules` and `yum-utils`.

## Quick Start
```bash
# From the repo root
chmod +x ./omw

# Build all software, install all apps, and configure tmux/zsh
./omw --all
```

## Usage
OMW groups actions into build (from source), install (prebuilt apps), config, and packaging.

Commands:
- Build software from source
  - ./omw --build <software> [--force] [--refresh]
- Install a prebuilt app
  - ./omw --install <app> [--force]
- Install all prebuilt apps
  - ./omw --install-all-apps
- Configure a tool (tmux | zsh)
  - ./omw --config <target>
- Create an offline bundle
  - ./omw --pack
- Verify offline completeness
  - ./omw --verify-offline
- View installed and installable items
  - ./omw --status
  - ./omw --installed
- Check for newer upstream versions
  - ./omw --check-updates
- Clean artifacts
  - ./omw --clean <builds|packages|installs|apps|all>
- Help
  - ./omw --help

Common options:
- --force    Force reinstallation (backs up existing install)
- --refresh  Regenerate modulefile only (skip rebuild)

Examples:
```bash
# Force rebuild vim
./omw --build vim --force

# See installed and installable software/apps
./omw --status

# Check for newer configured versions
./omw --check-updates

# Install the exa CLI
./omw --install exa

# Create a portable offline bundle
./omw --pack
```

## Software and Apps
Software and apps are defined in `software.conf` via arrays such as:
- SOFTWARE_LIST, SOFTWARE_VERSIONS, SOFTWARE_URLS, SOFTWARE_DEPS, SOFTWARE_CONFIG_CMDS, SOFTWARE_CFLAGS, SOFTWARE_LDFLAGS
- APP_LIST, APP_VERSIONS, APP_URLS, APP_EXECUTABLE_NAME, APP_SOURCE_URLS

You can add or override entries in `software.conf` to customize builds and app sources.

## Modulefiles
Each built package gets a modulefile under:
- tools/modulefiles/<name>/<name>-<version>

OMW automatically adds PATH, LD_LIBRARY_PATH, PKG_CONFIG_PATH, and include paths. Custom CFLAGS/LDFLAGS from `software.conf` are also injected when present.

## Local (System RPM) Layer
The `local` pseudo-software pulls RPMs (or uses `packages/rpms.tar.gz`), extracts them into a private prefix, fixes common path issues, adjusts pkg-config files, and exposes the layer via a module. Useful for environments without root access.

```bash
./omw --build local
module load local/local-<version>
```

## Offline Workflow
1) On an online machine:
```bash
./omw --pack
```
This downloads all sources/apps, GCC prerequisites, local RPMs, and config repos; verifies integrity; then creates `~/omw-offline-bundle-YYYYMMDD.tar.gz`.

2) On an offline machine:
```bash
tar -xzf omw-offline-bundle-*.tar.gz
cd oh-my-workspace
./omw --all
```

To re-verify completeness offline:
```bash
./omw --verify-offline
```

## Configuration Targets
- tmux: Clones `gpakosz/.tmux`, backs up existing config under `backups/tmux/`, symlinks `.tmux.conf`, and preserves local overrides.
- zsh: Clones Oh My Zsh + common plugins/themes, backs up existing config under `backups/zsh/`, keeps an existing `~/.oh-my-zsh` unchanged, ensures OMW env sourcing, and creates a `~/.zshrc_custom` hook.

```bash
./omw --config tmux
./omw --config zsh
```

## Directory Layout
- config/                Config resources (tmux, zsh)
- packages/              Downloaded source and app archives (+ SHA256SUMS)
- builds/                Temporary build directories
- tools/software/        Installed software prefixes
- tools/modulefiles/     Generated modulefiles
- apps/                  Installed app payloads
- bin/                   Symlinks for installed apps

Apps can optionally define `APP_SOURCE_URLS`; those source archives are downloaded and verified for offline bundles.

## Troubleshooting
- Missing dependencies: Run `./omw` on a machine with the listed system tools or install them first.
- module command missing: Install Environment Modules or Lmod and ensure `module` is in PATH.
- Build failures: Check logs under `builds/<name>-<version>/logs/` (configure/make/install).
- GCC prerequisites: OMW prefetches from GCC’s infrastructure; ensure those tarballs exist in `packages/software/` for offline builds.
- SELinux/permissions: If extraction or symlinks fail, check permissions and SELinux context.

## Notes
- OMW sets `OMW_HOME` internally; it also injects OMW sourcing lines into zsh if missing.
- For reproducibility, avoid modifying generated modulefiles; edit `software.conf` instead.
