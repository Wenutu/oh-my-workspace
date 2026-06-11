# Supported Resources

OMW resources are declared in `packages.sh` with Bash 4-compatible registration
functions. Keep versions pinned when a resource is used by offline packaging.

## Source Software

Currently supported source builds:

| Name | Version | Dependencies |
| --- | --- | --- |
| `openssl` | `1.1.1w` | none |
| `ncurses` | `6.6` | none |
| `lua` | `5.4.7` | none |
| `local` | `1.0.0` | none |
| `libevent` | `2.1.12` | `openssl@1.1.1w` |
| `gcc` | `13.2.0` | none, packaged for explicit builds |
| `python` | `3.12.12` | `openssl@1.1.1w`, `local@1.0.0` |
| `node` | `22.22.3` | none |
| `tmux` | `3.6b` | `ncurses@6.6`, `libevent@2.1.12` |
| `zsh` | `5.9.1` | `ncurses@6.6` |
| `vim` | `9.2.0586` | `ncurses@6.6`, `lua@5.4.7`, `local@1.0.0`, `python@3.12.12` |
| `ctags` | `6.2.1` | none |

```bash
software <name> <version> <url> <deps> <build-command> <cflags> <ldflags>
```

Declare the same software more than once to support multiple versions. Use `-`
as the placeholder for empty fields; do not omit positional fields. Software
URLs may use `{VERSION}` or `${VERSION}` as the version placeholder.

For the default configure/make flow, provide a build command in `packages.sh`.
For custom builds, use `-` for the build command and implement
`_omw_build_<name>` in `lib/build.sh`.

Each built package gets a modulefile under:

```text
tools/modulefiles/<name>/<name>-<version>
```

OMW inspects the installed prefix and adds only paths that exist. Standard
`bin`, `lib`, `lib64`, pkg-config, man, and include directories are mapped to
their matching environment variables. GCC modulefiles also set `CC` and `CXX`
when the compiler executables exist. Custom `CFLAGS` and `LDFLAGS` from
`packages.sh` are injected when present.

Use `./omw build all --refresh` to refresh modulefiles for every declared,
installed source tool, including GCC. Missing install prefixes are reported and
skipped, and refresh does not require build dependencies. Normal
`./omw build all` skips GCC; build it explicitly when needed.

## Prebuilt Apps

Currently supported prebuilt apps:

| Name | Version | Exposed command or path |
| --- | --- | --- |
| `exa` | `0.10.1` | `exa` |
| `rg` | `15.1.0` | `rg` |
| `fzf` | `0.73.1` | `fzf` |
| `yazi` | `26.5.6` | `yazi` |
| `fd` | `10.4.2` | `fd` |
| `sd` | `1.1.0` | `sd` |
| `autojump` | `22.5.3` | custom installer |
| `btop` | `1.4.7` | `btop` |
| `hack-nerd-font` | `3.4.0` | custom installer |
| `verible` | `0.0-4053-g89d4d98a` | `verible-verilog-ls`, plus `bin/` |

```bash
app <name> <version> <url> <executable> <source-url> <bin-dirs>
```

Prebuilt apps are unpacked under `apps/` and exposed through symlinks in
`bin/`. Provide an executable name, bin directories, or use `-` and implement
`_omw_app_install_<name>` in `lib/app.sh`. Optional `_omw_app_status_<name>`
hooks handle custom installed-state checks.

App URLs and app source URLs may use `{VERSION}` or `${VERSION}` as the version
placeholder. Source archives declared on apps are downloaded and verified for
offline bundles.

## Node Packages

Currently supported global Node packages:

| Alias | Package | Version | Binary | OMW Node |
| --- | --- | --- | --- | --- |
| `codex` | `@openai/codex` | `0.135.0` | `codex` | `22.22.3` |
| `claude-code` | `@anthropic-ai/claude-code` | `2.1.150` | `claude` | `22.22.3` |

No cache-only Node packages are currently enabled.

```bash
node_package <alias> <package> <version> <bin> <node-version>
node_cache_package <alias> <package> <version> <node-version>
```

Node package versions must be concrete, pinned versions. The `node-version`
field must match a declared OMW Node software version; OMW loads
`node/node-<node-version>` before packing, verifying, or installing that
package.

Use `node_package` for global CLI packages that OMW should install with
`./omw node install-all` and `./omw all`. Use `node_cache_package` for packages
that should only be available in the offline npm cache for other projects.

```bash
node_package "codex" "@openai/codex" "x.y.z" "codex" "22.22.3"
node_package "claude-code" "@anthropic-ai/claude-code" "x.y.z" "claude" "22.22.3"
node_cache_package "typescript" "typescript" "5.9.3" "22.22.3"
```

## Local System RPM Layer

The `local` pseudo-software pulls RPMs, or uses
`packages/local-<version>-rpms.tar.gz`, extracts them into a private prefix,
fixes common path issues, adjusts pkg-config files, and exposes the layer via a
module. This is useful for environments without root access.

```bash
./omw build prepare local
./omw build local
module load local/local-<version>
```

## Offline Cache Artifacts

Downloaded and generated deployment assets live in `packages/`.

```text
packages/local-<version>-rpms.tar.gz
packages/npm-cache-$OMW_VERSION.tar.gz
packages/config-tmux-$OMW_VERSION.tar.gz
packages/config-vim-$OMW_VERSION.tar.gz
packages/config-zsh-$OMW_VERSION.tar.gz
```

During `offline pack`, OMW builds any declared OMW Node versions needed by
`node_package` or `node_cache_package`, loads the matching module, populates
`builds/node/npm-cache`, and compresses that cache to
`packages/npm-cache-$OMW_VERSION.tar.gz`. The final offline bundle excludes
`builds`, so the archive is the portable npm cache source.
