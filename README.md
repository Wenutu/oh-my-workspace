# OMW (Oh My Workspace)

A self-contained Linux workspace manager organized around three core phases: build source tools, install prebuilt apps, and apply workspace configs. OMW also wires environment modules and can produce a fully offline bundle for air-gapped machines.

## Highlights

- Source builds with dependency orchestration and modulefiles
- Prebuilt app installation with simple symlink exposure
- Declarative global npm packages backed by an offline npm cache
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

# Add OMW env sourcing to ~/.bashrc, then reload your shell
./omw init
source ~/.bashrc

# Inspect configured software, apps, configs, and Node packages
./omw status

# Run build -> config -> app -> Node package install
./omw all
```

`./omw init` only wires `env.sh` into your shell startup file. It does not build or install packages by itself.

## Usage

OMW groups actions by functional area. Legacy flags such as `--build`, `--install`, and `--pack` are still supported, but the preferred form is:

Commands:

- Build source software
  - ./omw build <software[@version]> [--force] [--refresh]
  - ./omw build all
- Install prebuilt apps
  - ./omw app install <app> [--force]
  - ./omw app install-all
- Manage global npm packages
  - ./omw node pack
  - ./omw node verify
  - ./omw node restore-cache
  - ./omw node install <alias>
  - ./omw node install-all
- Configure shell/editor targets
  - ./omw config <tmux|vim|zsh|all>
  - ./omw init
- Offline bundle operations
  - ./omw offline pack
  - ./omw offline verify
- View status and updates
  - ./omw status
  - ./omw status installed
  - ./omw update check
- Clean artifacts
  - ./omw clean <builds|packages|installs|apps|node|all>
  - `packages` and `all` preserve `packages/config/*.tar.gz`
- Full workspace setup
  - ./omw all # build -> config -> app -> node packages

Common options:

- --force Force reinstallation (backs up existing install)
- --refresh Regenerate modulefile only (skip rebuild)

Examples:

```bash
# Force rebuild vim
./omw build vim --force

# See installed and installable software/apps
./omw status

# Check for newer configured versions
./omw update check

# Install the exa CLI
./omw app install exa

# Install a declared global npm package from the offline cache
./omw node install codex

# Create a portable offline bundle
./omw offline pack
```

## Software and Apps

Software and apps are declared in `packages.sh` with Bash 4-compatible registration functions:

- `software <name> <version> <url> <deps> <build-command> <cflags> <ldflags>`
- `app <name> <version> <url> <executable> <source-url> <bin-dirs>`
- `node_package <alias> <package> <version> <bin> <node-version>`
- `node_cache_package <alias> <package> <version> <node-version>`

Declare the same software more than once to support multiple versions. The registration functions populate OMW's internal arrays automatically, including version-specific dependency keys.
Use `-` as the placeholder for empty fields; do not omit positional fields.

Node package versions must be pinned to concrete versions. The `node-version` field must match a declared OMW Node software version; OMW loads `node/node-<node-version>` before packing, verifying, or installing that package.

Use `node_package` for global CLI packages that OMW should install with `./omw node install-all` and `./omw all`. Use `node_cache_package` for packages that should only be available in the offline npm cache for other projects.

```bash
node_package "codex" "@openai/codex" "x.y.z" "codex" "22.22.3"
node_package "claude-code" "@anthropic-ai/claude-code" "x.y.z" "claude" "22.22.3"
node_cache_package "typescript" "typescript" "5.9.3" "22.22.3"
```

## Modulefiles

Each built package gets a modulefile under:

- tools/modulefiles/<name>/<name>-<version>

OMW automatically adds PATH, LD_LIBRARY_PATH, PKG_CONFIG_PATH, and include paths. Custom CFLAGS/LDFLAGS from `packages.sh` are also injected when present.

## Local (System RPM) Layer

The `local` pseudo-software pulls RPMs (or uses `packages/rpms.tar.gz`), extracts them into a private prefix, fixes common path issues, adjusts pkg-config files, and exposes the layer via a module. Useful for environments without root access.

```bash
./omw --build local
module load local/local-<version>
```

## Offline Workflow

### Online Packing Machine

1. Prepare the shell environment:

```bash
chmod +x ./omw
./omw init
source ~/.bashrc
```

2. Review the package definitions in `packages.sh`. Pin every `node_package` and `node_cache_package` version before packing.

3. Create and verify the offline bundle:

```bash
./omw status
./omw offline pack
```

This downloads all sources/apps, GCC prerequisites, local RPMs, packages existing config directories, prepares the npm cache archive for declared Node packages, verifies integrity, and then creates `~/omw-offline-bundle-YYYYMMDD.tar.gz`.

During `offline pack`, OMW first builds any declared OMW Node versions needed by `node_package` or `node_cache_package`, then loads the matching module to populate `builds/node/npm-cache`. After verification, it compresses that cache to `packages/node/npm-cache.tar.gz`; the final offline bundle excludes `builds`, so it only carries the archive. On the offline machine, `./omw node restore-cache`, `./omw node verify`, and `./omw node install <alias>` automatically extract the cache archive when needed.

### Offline Install Machine

1. Extract the bundle and initialize the shell environment:

```bash
tar -xzf omw-offline-bundle-*.tar.gz
cd oh-my-workspace
chmod +x ./omw
./omw init
source ~/.bashrc
```

2. Verify and install the workspace:

```bash
./omw offline verify
./omw all
```

3. Restore the npm cache if other offline projects need it:

```bash
./omw node restore-cache
```

### Using OMW's npm Cache Elsewhere

Other offline projects can consume the restored cache directly. Restore the cache once, load the matching Node module, then point npm at OMW's cache:

```bash
cd /path/to/oh-my-workspace
./omw node restore-cache
module load node/node-22.22.3

cd /path/to/other-node-project
npm ci --offline --cache "$OMW_HOME/builds/node/npm-cache"
```

For a project-local default, create `.npmrc` in that project:

```ini
offline=true
cache=/path/to/oh-my-workspace/builds/node/npm-cache
audit=false
fund=false
```

Then normal npm commands in that project use the restored cache:

```bash
npm ci
npm install
```

Re-run `./omw offline verify` any time you want to check that the extracted offline assets are still complete.

## Configuration Targets

- tmux: Restores `packages/config/tmux.tar.gz` first; if missing, clones `gpakosz/.tmux`, backs up existing config under `backups/tmux/`, symlinks `.tmux.conf`, and preserves local overrides.
- vim: Restores `packages/config/vim.tar.gz` when present and installs an OMW-managed `~/.vimrc`; if no Vim config package exists, Vim config is skipped.
- zsh: Restores `packages/config/zsh.tar.gz` first; if missing, clones Oh My Zsh + common plugins/themes, backs up existing config under `backups/zsh/`, keeps an existing `~/.oh-my-zsh` unchanged, ensures OMW env sourcing, and creates a `~/.zshrc_custom` hook.

```bash
./omw --config tmux
./omw --config zsh
```

Before creating a bundle for upload, manually prepare your config directories and pack them:

```bash
make pack-vim OUT_DIR=packages/config
make pack-configs OUT_DIR=packages/config
```

## Directory Layout

- config/ Config resources (tmux, zsh)
- lib/ OMW implementation modules grouped by responsibility
- packages/ Downloaded source and app archives (+ SHA256SUMS)
  - node/npm-cache.tar.gz Offline npm cache archive for declared Node packages
- builds/ Temporary build directories
- tools/software/ Installed software prefixes
- tools/modulefiles/ Generated modulefiles
- apps/ Installed app payloads
- bin/ Symlinks for installed apps

Implementation modules under `lib/` are intentionally coarse-grained:

- common.sh: initialization, logging, filesystem helpers, downloads, extraction
- status.sh: status tables and upstream update checks
- build.sh: source-build orchestration, package-specific builders, modulefiles
- app.sh: prebuilt app installation and app-specific installers
- node.sh: global npm package cache packing, verification, and offline install
- config.sh: tmux/vim/zsh configuration flows and shell environment setup
- offline.sh: offline asset verification, config packaging, bundle creation

Apps can optionally declare source archives in `packages.sh`; those source archives are downloaded and verified for offline bundles.

## Troubleshooting

- Missing dependencies: Run `./omw` on a machine with the listed system tools or install them first.
- module command missing: Install Environment Modules or Lmod and ensure `module` is in PATH.
- Build failures: Check logs under `builds/<name>-<version>/logs/` (configure/make/install).
- GCC prerequisites: OMW prefetches from GCC’s infrastructure; ensure those tarballs exist in `packages/software/` for offline builds.
- SELinux/permissions: If extraction or symlinks fail, check permissions and SELinux context.

## Notes

- OMW sets `OMW_HOME` internally; it also injects OMW sourcing lines into zsh if missing.
- For reproducibility, avoid modifying generated modulefiles; edit `packages.sh` instead.
