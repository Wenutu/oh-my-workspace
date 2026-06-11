# Changelog

All notable changes to **OMW (Oh My Workspace)** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-06-11

### Added

- Added batch modulefile refresh with `omw build all --refresh`.
- Added directory-aware modulefile generation for existing `bin`, `lib`, `lib64`, `pkgconfig`, `share/man`, and `include` directories.
- Added `CC` and `CXX` environment variables to GCC modulefiles.

### Changed

- Made modulefile refresh bypass build dependency checks and skip missing installation prefixes with warnings.
- Made normal `omw build all` skip GCC directly while allowing batch refresh to include it.

### Removed

- Removed the `SOFTWARE_BUILD_ALL_EXCLUDES` configuration.

## [0.2.0] - 2026-06-09

### Changed

- Split runtime initialization into read-only and mutating modes.
- Kept the offline bundle contract at format v2 with fast MD5 integrity checks.
- Added strict bundle metadata and manifest validation.
- Added explicit build and upgrade execution plans.
- Extended transactions to approved HOME paths and persisted interrupted transaction journals.
- Added installation receipts with installed, legacy, and partial state reporting.
- Enhanced `omw update check` with colored and precise results for source software, apps, Node packages, Coc extensions, and Vim Git plugins.
- Made upgrades transactionally replace the installed Bundle v2 metadata and manifest control files.

### Package Updates

- Updated Vim from `9.2.0586` to `9.2.0604`.
- Updated Codex from `0.135.0` to `0.138.0`.
- Updated Claude Code from `2.1.150` to `2.1.169`.

### Removed

- Unused lib/\*.sh code.
- Outdated README.md descriptions.

[0.2.0]: https://github.com/Wenutu/oh-my-workspace/releases/tag/v0.2.0

## [0.1.0] - 2026-06-08

### Added

**Project Init**

- Scaffold: CLI entrypoint, directory layout, build system skeleton, config framework
- Unified `omw` command with subcommand dispatch and `--help`/`--version`/`--no-color`
- Single-source `VERSION` file, cross-validated by CLI and release pipeline
- Full CI/CD pipeline: linting, static checks, Docker build verification, GitHub Release publishing

**Core Capabilities**

- **Source builds**: compile gcc, python, node, vim, tmux, zsh, and other dev tools from source with automatic `modulefile` generation for PATH/env injection; local RPM extraction for rootless environments
- **Prebuilt apps**: install and symlink CLI tools — exa, rg, fzf, fd, btop, and more
- **Node packages**: offline npm cache with install, verify, backup, and restore lifecycle
- **Configuration**: one-command restore for vim, tmux, zsh configs (online/offline)

**Offline Workflow**

- `omw offline pack`: one-command bundle — build artifacts + source archives + npm cache + config tarballs
- `omw offline verify`: bundle integrity validation
- `omw upgrade`: transactional upgrade with dry-run preview, manifest diff, rollback, and `config/local/` preservation

**Documentation**

- Bilingual docs: README, resources, vim configuration guides (EN & CN)
- Built-in `omw help <command>` for every registered subcommand

[0.1.0]: https://github.com/Wenutu/oh-my-workspace/releases/tag/v0.1.0
