# OMW (Oh My Workspace)

[English](README.md) | [简体中文](README.zh-CN.md)

A self-contained Linux workspace manager organized around three core phases: build source tools, install prebuilt apps, and apply workspace configs. OMW also wires environment modules and can produce a fully offline bundle for air-gapped machines.

## Highlights

- Source builds with dependency orchestration and modulefiles
- Prebuilt app installation with simple symlink exposure
- Declarative global npm packages backed by an offline npm cache
- Offline bundle generation and verification
- Local system RPM extraction to a private prefix
- Clean logs, spinners, and colored status output

Additional documentation:

- [Supported resources](docs/resources.md)
- [Vim configuration](docs/vim.md)

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

Run `./omw --help` for the compact command overview or
`./omw help <command>` for contextual help.

### Setup

- `./omw init`: Add OMW environment sourcing to `~/.bashrc`.
- `./omw all [--force] [--refresh]`: Run build -> config -> app -> Node package installation.

### Packages

- `./omw build <software[@version]|all> [--force] [--refresh]`: Build source software.
- `./omw build prepare <software[@version]|all>`: Download source archives and build dependency packages without compiling.
- `./omw app install <app> [--force]`: Install one prebuilt app.
- `./omw app install-all [--force]`: Install all prebuilt apps.
- `./omw node pack|verify|restore-cache`: Manage the offline npm cache.
- `./omw node install <alias>`: Install one declared global npm package.
- `./omw node install-all`: Install all declared global npm packages.

### Configuration

- `./omw config <tmux|vim|zsh|all> [--force]`: Apply shell/editor configs offline.
- `./omw config prepare <tmux|vim|zsh|all> [--force]`: Prepare config assets and archives online.

### Offline Workflow

- `./omw offline pack [--force]`: Create a portable offline bundle.
- `./omw offline verify`: Verify bundled offline assets.
- `./omw upgrade <bundle.tar.gz|extracted-dir> [--dry-run] [--replace-packages]`: Upgrade this checkout from a newer bundle.

### Maintenance

- `./omw status [installed]`: Show installable items or limit the view to installed items.
- `./omw doctor [profile]`: Check local OMW runtime health without modifying files.
- `./omw update check`: Check supported upstream versions.
- `./omw clean <builds|packages|config|installs|apps|node|all> [--dry-run]`: Remove or preview generated artifacts. The `all` target preserves deployment packages so `./omw all` can restore the workspace. Use `packages` to remove downloaded and packed caches.

Common options:

- `--force`: Force rebuild/reinstall, or refresh generated config assets during prepare.
- `--refresh`: Regenerate modulefiles only and skip source rebuilds.
- `--dry-run`: Preview paths removed by `clean`.
- `--replace-packages`: Replace `packages/` during `upgrade` instead of merging bundle assets.
- `--no-color`: Disable colored output.
- `--version`: Show the OMW version.

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

# Preview an upgrade from a newer bundle
./omw upgrade ~/omw-offline-bundle-v0.1.0.tar.gz --dry-run
```

## Supported Resources

Software, prebuilt apps, Node packages, cache-only Node packages, modulefiles,
and the local RPM layer are declared and prepared through `packages.sh`. See
[docs/resources.md](docs/resources.md) for the supported resource types,
registration functions, and generated offline cache artifacts.

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

This downloads all sources/apps, GCC prerequisites, local RPMs, packages existing config directories, prepares the npm cache archive for declared Node packages, verifies that required archives are readable, and then creates `$OMW_HOME/omw-offline-bundle-vVERSION.tar.gz`.

During `offline pack`, OMW first builds any declared OMW Node versions needed by `node_package` or `node_cache_package`, then loads the matching module to populate `builds/node/npm-cache`. Existing cache archives are restored before new package specs are added. After verification, OMW compresses that cache to `packages/npm-cache-$OMW_VERSION.tar.gz`; if the new archive has the same sha256 as the existing archive, the existing archive is kept. The final offline bundle excludes `builds`, so it only carries the archive. On the offline machine, `./omw node restore-cache`, `./omw node verify`, and `./omw node install <alias>` automatically extract the cache archive when needed.

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

### Upgrading an Existing OMW Checkout

Use `upgrade` when an offline machine already has an OMW checkout and you want
to move it to a newer offline bundle without reinstalling everything from a
fresh directory. The supported upgrade baseline is `0.1.0`; older bundle
layouts are intentionally unsupported:

```bash
./omw upgrade /path/to/omw-offline-bundle-vVERSION.tar.gz --dry-run
./omw upgrade /path/to/omw-offline-bundle-vVERSION.tar.gz
```

The command accepts either the `.tar.gz` bundle or an extracted bundle
directory. It updates managed OMW files (`VERSION`, `omw`, `env.sh`, `packages.sh`,
`README.md`, `docs/`, `compose.yaml`, `lib/`, and `config/`) in one transaction. Local
configuration override files under `config/local/` are preserved.

`--dry-run` prints the same upgrade plan used by the real execution path,
including source and target paths, manifest summaries, per-path policies, and
the decision for each managed path. New bundles must include
`.omw-bundle-meta` and `.omw-bundle-manifest`; regenerate older bundles with
`./omw offline pack`. The metadata is a shell-friendly `key=value` file, and the
manifest is a tab-delimited v2 format that records files, directories, symlinks,
file md5s, and modes without using JSON. Unchanged paths are skipped during
real execution. If an upgrade step fails, OMW rolls back the transaction before
returning.

By default, `packages/` is merged through a staged replacement: OMW copies the
current package cache into a temporary directory, overlays bundle entries whose
manifest record differs from the same local path or whose local path is missing,
then replaces the cache in one transaction. Managed OMW paths use an exact
replacement policy, while stale local package archives that are not listed in
the bundle manifest are left in place. When the bundle
contains `packages/npm-cache-$OMW_VERSION.tar.gz`,
OMW backs up the current npm cache under `backups/npm-cache/`, clears the staged
cache, and adopts the bundle cache. Use `--replace-packages` when the bundle
should become the exact package cache:

```bash
./omw upgrade /path/to/extracted/oh-my-workspace --replace-packages
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

Re-run `./omw offline verify` any time you want to check that the extracted offline assets are still complete. This check only inspects bundled assets, so it can run before Node or other tools are built on the offline machine. The online packing flow separately simulates offline npm installs before creating the bundle.

## Configuration Targets

`./omw config prepare <target|all>` and `./omw offline pack` are the only
configuration flows that access GitHub or npm. They reuse prepared config
dependencies when present, download missing ones, and overwrite the matching
`packages/config-<target>-$OMW_VERSION.tar.gz` archives. Repository config
sources stay in `config/<target>`; the offline bundle stages them as
`config/$OMW_VERSION/<target>` so installed releases can keep versioned runtime
config. Prepared config directories are archived with their Git metadata so
offline restore only needs extraction.
Pass `--force` to either command to refresh generated config dependencies before
creating archives. Existing generated assets are restored if refresh fails.
Normal `config` commands and `./omw all` only restore those archives. A missing
config archive emits a warning and does not block software installation.
When restoring an archive, OMW replaces `config/$OMW_VERSION/<target>`.
User override files live directly under `config/local/` and are loaded
separately.
`--force` refreshes generated source assets before packaging.

Managed source files:

```text
config/tmux/tmux.default
config/vim/vimrc.default
config/vim/plugins.list
config/vim/coc/coc-settings.json
config/vim/coc/extensions.list
config/zsh/zshrc.default
```

Local override files:

```text
config/local/tmux.local
config/local/vimrc.local
config/local/zshrc.local
```

Vim plugin and Coc definition files are online preparation inputs. Their
source definitions live under `config/vim/` — `plugins.list`, `coc/coc-settings.json`,
and `coc/extensions.list`. Offline restore does not touch them; it only
extracts the prepared archive and writes the `~/.vimrc` loader. The local
override contract covers one flat file: `config/local/vimrc.local`.
See [docs/vim.md](docs/vim.md) for the full Vim/Coc preparation flow.
```bash
./omw config tmux
./omw config vim
./omw config zsh
```

Prepare one or all configuration archives online:

```bash
./omw config prepare vim
./omw config prepare all
```

`./omw clean config` removes generated config dependencies from both repository
source config and versioned runtime config (`.tmux`, Vim `pack`, Coc
`extensions`, and `.oh-my-zsh`). `./omw clean packages` removes all downloaded
packages and performs the same generated config cleanup for compatibility.

## Directory Layout

- VERSION OMW release version used for lib/config/cache versioning
- config/ Repository config sources under config/<target>; runtime releases under config/<version>; local overrides under config/local/
- lib/ OMW implementation modules grouped by responsibility
- packages/ Flat downloaded source/app/config/cache archives using URL basenames where applicable
  - local-<version>-rpms.tar.gz Versioned local RPM bundle
  - npm-cache-<OMW_VERSION>.tar.gz Offline npm cache archive for declared Node packages
- builds/ Temporary build directories
- tools/software/ Installed software prefixes
- tools/modulefiles/ Generated modulefiles
- apps/ Installed app payloads
- bin/ Symlinks for installed apps

Implementation modules under `lib/` are grouped by responsibility:

- common.sh: initialization, logging, config validation, shared backup/link helpers
- fs.sh: safe filesystem operations, downloads, archive extraction, archive checks
- tx.sh: transactional backup, rollback, commit, and temporary path cleanup
- registry.sh: package URL rendering and registry lookups from `packages.sh`
- workflow.sh: high-level command workflows such as `all`, build-all, config-all, and clean
- doctor.sh: local runtime health checks
- cli.sh: command parsing, registration, dispatch, and built-in help
- status.sh: status tables and upstream update checks
- build.sh: source-build orchestration, package-specific builders, modulefiles
- app.sh: prebuilt app installation and app-specific installers
- node.sh: global npm package cache packing, verification, and offline install
- config.sh: tmux/vim/zsh configuration flows and shell environment setup
- offline.sh: offline asset verification, config packaging, bundle creation
- upgrade.sh: offline bundle upgrade planning, preview, and transactional execution

Apps can optionally declare source archives in `packages.sh`; those source archives are downloaded and verified for offline bundles.

## Troubleshooting

- Missing dependencies: Run `./omw` on a machine with the listed system tools or install them first.
- module command missing: Install Environment Modules or Lmod and ensure `module` is in PATH.
- Build failures: Check logs under `builds/<name>-<version>/logs/` (configure/make/install).
- GCC prerequisites: During offline packing, OMW first fetches GCC's `contrib/download_prerequisites` script from the matching `gcc-mirror` release branch. If that fetch fails, it extracts the GCC source archive and reads the bundled script instead. Ensure the resulting prerequisite tarballs exist in flat `packages/` for offline builds.
- SELinux/permissions: If extraction or symlinks fail, check permissions and SELinux context.

## Notes

- OMW sets `OMW_HOME` internally; it also injects OMW sourcing lines into zsh if missing.
- For reproducibility, avoid modifying generated modulefiles; edit `packages.sh` instead.
