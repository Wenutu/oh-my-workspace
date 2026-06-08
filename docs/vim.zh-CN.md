# Vim 配置

Vim 配置分为两个阶段：

- 在线准备读取 `config/vim/` 下的源定义文件，克隆 Vim 插件，下载 Coc 插件，并写出 `packages/config-vim-$OMW_VERSION.tar.gz`。
- 离线恢复只解压已经准备好的压缩包，并写入一个很小的 `~/.vimrc` loader。离线恢复不能修改 Vim 插件或 Coc 定义文件。

## 在线源文件

这些文件在运行 `./omw config prepare vim` 或 `./omw offline pack` 前编辑：

```text
config/vim/vimrc.default
config/vim/plugins.list
config/vim/coc/coc-settings.json
config/vim/coc/extensions.list
```

`plugins.list`、`coc-settings.json` 和 `extensions.list` 都是在线准备输入文件，不是离线本地覆盖配置。

## Vim 插件

Vim 9 插件使用原生 package 目录：

```text
config/vim/vim9/pack/omw/start/
```

插件仓库声明在：

```text
config/vim/plugins.list
```

当前支持的 Vim 插件：

| 目录 | 仓库 | 分支 |
| --- | --- | --- |
| `auto-pairs` | `https://github.com/jiangmiao/auto-pairs.git` | 默认 |
| `autoHEADER` | `https://github.com/Wenutu/autoHEADER.git` | 默认 |
| `coc.nvim` | `https://github.com/neoclide/coc.nvim.git` | `release` |
| `fzf` | `https://github.com/junegunn/fzf.git` | 默认 |
| `fzf.vim` | `https://github.com/junegunn/fzf.vim.git` | 默认 |
| `indentline` | `https://github.com/yggdroot/indentline.git` | 默认 |
| `nerdcommenter` | `https://github.com/preservim/nerdcommenter.git` | 默认 |
| `nerdtree` | `https://github.com/preservim/nerdtree.git` | 默认 |
| `rainbow` | `https://github.com/luochen1990/rainbow.git` | 默认 |
| `seoul256.vim` | `https://github.com/junegunn/seoul256.vim.git` | 默认 |
| `tagbar` | `https://github.com/preservim/tagbar.git` | 默认 |
| `vim-airline` | `https://github.com/vim-airline/vim-airline.git` | 默认 |
| `vim-cursorword` | `https://github.com/itchyny/vim-cursorword.git` | 默认 |
| `vim-easy-align` | `https://github.com/junegunn/vim-easy-align.git` | 默认 |
| `vim-matchup` | `https://github.com/andymass/vim-matchup.git` | 默认 |
| `vim-multiple-cursors` | `https://github.com/terryma/vim-multiple-cursors.git` | 默认 |
| `vim-snippets` | `https://github.com/honza/vim-snippets.git` | 默认 |
| `vim-verilog-mode` | `https://github.com/Wenutu/vim-verilog-mode.git` | 默认 |
| `visincr` | `https://github.com/vim-scripts/VisIncr.git` | 默认 |

OMW 不使用 `vim-plug`，也不会执行 `PlugInstall`。在线准备会把清单中的插件仓库克隆到原生 package 目录。

## Coc 设置与插件

Coc 设置来自：

```text
config/vim/coc/coc-settings.json
```

Coc 插件版本固定在：

```text
config/vim/coc/extensions.list
```

每个非注释行声明一个精确 npm 包版本：

```text
coc-json@1.9.3
coc-snippets@3.4.7
coc-yaml@1.9.1
```

当前支持的 Coc 插件：

| 插件 | 版本 |
| --- | --- |
| `coc-json` | `1.9.3` |
| `coc-snippets` | `3.4.7` |
| `coc-yaml` | `1.9.1` |
| `coc-pyright` | `1.1.409` |
| `coc-perl` | `3.0.0` |
| `coc-sh` | `1.2.4` |
| `coc-vimlsp` | `0.13.1` |

运行 `./omw config prepare vim` 会读取该清单并生成：

```text
config/vim/coc/extensions/package.json
config/vim/coc/extensions/node_modules/
```

生成的 `config/vim/coc/extensions` 目录会打入 `packages/config-vim-$OMW_VERSION.tar.gz`。离线恢复只解压并检查已打包的插件，不执行 npm。

## Coc 片段

自定义 Coc 片段定义存放于:

```text
config/vim/coc/ultisnips/all.snippets
```

该文件提供 UltiSnips 风格的代码片段（包含折叠标记助手），
在离线恢复时由 `coc-snippets` 插件加载。
运行 `./omw config prepare vim` 前编辑 `all.snippets`
可添加或修改项目级代码片段。

## 离线本地覆盖

用户本地 Vim 覆盖配置使用一个扁平文件：

```text
config/local/vimrc.local
```

生成的 `~/.vimrc` loader 按顺序读取：

```text
$OMW_HOME/config/$OMW_VERSION/vim/vimrc.default
$OMW_HOME/config/local/vimrc.local
```

机器相关的选项、映射和命令放在 `config/local/vimrc.local`。Vim 插件和 Coc 定义变更应继续写在上面的在线源文件中。
