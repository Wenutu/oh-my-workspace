# Vim Configuration

Vim configuration has two phases:

- Online preparation reads source definition files under `config/vim/`, clones
  Vim plugins, downloads Coc extensions, and writes
  `packages/config-vim-$OMW_VERSION.tar.gz`.
- Offline restore only extracts the prepared archive and writes a small
  `~/.vimrc` loader. It must not modify Vim plugin or Coc definition files.

## Online Source Files

These files are edited before running `./omw config prepare vim` or
`./omw offline pack`:

```text
config/vim/vimrc.default
config/vim/plugins.list
config/vim/coc/coc-settings.json
config/vim/coc/extensions.list
```

`plugins.list`, `coc-settings.json`, and `extensions.list` are online
preparation inputs. Do not treat them as offline local overrides.

## Vim Plugins

Vim 9 plugins use the native package layout:

```text
config/vim/vim9/pack/omw/start/
```

Plugin repositories are declared in:

```text
config/vim/plugins.list
```

Currently supported Vim plugins:

| Directory | Repository | Branch |
| --- | --- | --- |
| `auto-pairs` | `https://github.com/jiangmiao/auto-pairs.git` | default |
| `autoHEADER` | `https://github.com/Wenutu/autoHEADER.git` | default |
| `coc.nvim` | `https://github.com/neoclide/coc.nvim.git` | `release` |
| `fzf` | `https://github.com/junegunn/fzf.git` | default |
| `fzf.vim` | `https://github.com/junegunn/fzf.vim.git` | default |
| `indentline` | `https://github.com/yggdroot/indentline.git` | default |
| `nerdcommenter` | `https://github.com/preservim/nerdcommenter.git` | default |
| `nerdtree` | `https://github.com/preservim/nerdtree.git` | default |
| `rainbow` | `https://github.com/luochen1990/rainbow.git` | default |
| `seoul256.vim` | `https://github.com/junegunn/seoul256.vim.git` | default |
| `tagbar` | `https://github.com/preservim/tagbar.git` | default |
| `vim-airline` | `https://github.com/vim-airline/vim-airline.git` | default |
| `vim-cursorword` | `https://github.com/itchyny/vim-cursorword.git` | default |
| `vim-easy-align` | `https://github.com/junegunn/vim-easy-align.git` | default |
| `vim-matchup` | `https://github.com/andymass/vim-matchup.git` | default |
| `vim-multiple-cursors` | `https://github.com/terryma/vim-multiple-cursors.git` | default |
| `vim-snippets` | `https://github.com/honza/vim-snippets.git` | default |
| `vim-verilog-mode` | `https://github.com/Wenutu/vim-verilog-mode.git` | default |
| `visincr` | `https://github.com/vim-scripts/VisIncr.git` | default |

OMW does not use `vim-plug` and does not run `PlugInstall`. Online preparation
clones the listed plugin repositories into the native package directory.

## Coc Settings and Extensions

Coc settings are prepared from:

```text
config/vim/coc/coc-settings.json
```

Coc extension versions are pinned in:

```text
config/vim/coc/extensions.list
```

Each non-comment line declares one exact npm package version:

```text
coc-json@1.9.3
coc-snippets@3.4.7
coc-yaml@1.9.1
```

Currently supported Coc extensions:

| Extension | Version |
| --- | --- |
| `coc-json` | `1.9.3` |
| `coc-snippets` | `3.4.7` |
| `coc-yaml` | `1.9.1` |
| `coc-pyright` | `1.1.409` |
| `coc-perl` | `3.0.0` |
| `coc-sh` | `1.2.4` |
| `coc-vimlsp` | `0.13.1` |

Running `./omw config prepare vim` reads that list and generates:

```text
config/vim/coc/extensions/package.json
config/vim/coc/extensions/node_modules/
```

The generated `config/vim/coc/extensions` directory is packaged into
`packages/config-vim-$OMW_VERSION.tar.gz`. Offline restore only extracts and
checks the packaged extensions; it does not run npm.

## Coc Snippets

Custom Coc snippet definitions live in:

```text
config/vim/coc/ultisnips/all.snippets
```

The file provides UltiSnips-style snippets — including fold marker helpers —
that are loaded by the `coc-snippets` extension during offline restore.
Edit `all.snippets` before running `./omw config prepare vim` to add or
change project-level snippets.

## Offline Local Override

User-local Vim overrides live in one flat file:

```text
config/local/vimrc.local
```

The generated `~/.vimrc` loader sources files in this order:

```text
$OMW_HOME/config/$OMW_VERSION/vim/vimrc.default
$OMW_HOME/config/local/vimrc.local
```

Use `config/local/vimrc.local` for machine-specific options, mappings, and
commands that should survive offline upgrades. Keep plugin and Coc definition
changes in the online source files listed above.
