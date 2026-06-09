# Changelog

All notable changes to **OMW (Oh My Workspace)** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- Unused lib/\*.sh code.
- Outdated README.md descriptions.

## [0.1.0] - 2025-06-08

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

[0.1.0]: https://github.com/shiwentao/oh-my-workspace/releases/tag/v0.1.0
