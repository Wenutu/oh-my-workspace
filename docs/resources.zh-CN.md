# 支持资源

OMW 的资源在 `packages.sh` 中通过 Bash 4 兼容的注册函数声明。会进入离线包的资源应固定具体版本。

## 源码软件

当前支持的源码构建：

| 名称 | 版本 | 依赖 |
| --- | --- | --- |
| `openssl` | `1.1.1w` | 无 |
| `ncurses` | `6.6` | 无 |
| `lua` | `5.4.7` | 无 |
| `local` | `1.0.0` | 无 |
| `libevent` | `2.1.12` | `openssl@1.1.1w` |
| `gcc` | `13.2.0` | 无，只打包，显式请求时构建 |
| `python` | `3.12.12` | `openssl@1.1.1w`、`local@1.0.0` |
| `node` | `22.22.3` | 无 |
| `tmux` | `3.6b` | `ncurses@6.6`、`libevent@2.1.12` |
| `zsh` | `5.9.1` | `ncurses@6.6` |
| `vim` | `9.2.0586` | `ncurses@6.6`、`lua@5.4.7`、`local@1.0.0`、`python@3.12.12` |
| `ctags` | `6.2.1` | 无 |

```bash
software <name> <version> <url> <deps> <build-command> <cflags> <ldflags>
```

同一个软件可以声明多个版本。空字段使用 `-` 占位，不要省略位置参数。源码 URL 可以使用 `{VERSION}` 或 `${VERSION}` 作为版本占位符。

如果适合默认 configure/make 流程，可以在 `packages.sh` 中提供构建命令。需要自定义构建时，将构建命令写成 `-`，并在 `lib/build.sh` 中实现 `_omw_build_<name>`。

每个构建完成的软件会生成 modulefile：

```text
tools/modulefiles/<name>/<name>-<version>
```

OMW 会自动设置 `PATH`、`LD_LIBRARY_PATH`、`PKG_CONFIG_PATH` 和 include 路径；`packages.sh` 中的自定义 `CFLAGS`、`LDFLAGS` 也会在需要时注入。

## 预编译应用

当前支持的预编译应用：

| 名称 | 版本 | 暴露命令或路径 |
| --- | --- | --- |
| `exa` | `0.10.1` | `exa` |
| `rg` | `15.1.0` | `rg` |
| `fzf` | `0.73.1` | `fzf` |
| `yazi` | `26.5.6` | `yazi` |
| `fd` | `10.4.2` | `fd` |
| `sd` | `1.1.0` | `sd` |
| `autojump` | `22.5.3` | 专用安装器 |
| `btop` | `1.4.7` | `btop` |
| `hack-nerd-font` | `3.4.0` | 专用安装器 |
| `verible` | `0.0-4053-g89d4d98a` | `verible-verilog-ls`，以及 `bin/` |

```bash
app <name> <version> <url> <executable> <source-url> <bin-dirs>
```

预编译应用会解压到 `apps/`，并通过 `bin/` 中的软链暴露命令。可以提供可执行文件名或 bin 目录；如果都不适用，使用 `-`，并在 `lib/app.sh` 中实现 `_omw_app_install_<name>`。可选的 `_omw_app_status_<name>` 用于自定义安装状态检查。

App URL 和 App 源码 URL 可以使用 `{VERSION}` 或 `${VERSION}` 作为版本占位符。App 声明的源码包会在离线打包时下载并校验。

## Node 包

当前支持的 Node 全局包：

| 别名 | npm 包 | 版本 | 命令 | OMW Node |
| --- | --- | --- | --- | --- |
| `codex` | `@openai/codex` | `0.135.0` | `codex` | `22.22.3` |
| `claude-code` | `@anthropic-ai/claude-code` | `2.1.150` | `claude` | `22.22.3` |

当前没有启用只进入缓存的 Node 包。

```bash
node_package <alias> <package> <version> <bin> <node-version>
node_cache_package <alias> <package> <version> <node-version>
```

Node 包版本必须是固定的具体版本。`node-version` 必须对应 OMW 中已声明的 Node 软件版本；打包、校验或安装该包前，OMW 会加载 `node/node-<node-version>`。

`node_package` 用于需要通过 `./omw node install-all` 和 `./omw all` 安装的全局 CLI 包。`node_cache_package` 用于只需要进入离线 npm cache、供其他项目使用的包。

```bash
node_package "codex" "@openai/codex" "x.y.z" "codex" "22.22.3"
node_package "claude-code" "@anthropic-ai/claude-code" "x.y.z" "claude" "22.22.3"
node_cache_package "typescript" "typescript" "5.9.3" "22.22.3"
```

## 本地系统 RPM 层

`local` 伪软件会拉取 RPM，或使用 `packages/local-<version>-rpms.tar.gz`，将其解压到私有 prefix，修复常见路径问题，调整 pkg-config 文件，并通过 module 暴露。这适合没有 root 权限的环境。

```bash
./omw build prepare local
./omw build local
module load local/local-<version>
```

## 离线缓存产物

下载和生成的部署资产放在 `packages/`：

```text
packages/local-<version>-rpms.tar.gz
packages/npm-cache-$OMW_VERSION.tar.gz
packages/config-tmux-$OMW_VERSION.tar.gz
packages/config-vim-$OMW_VERSION.tar.gz
packages/config-zsh-$OMW_VERSION.tar.gz
```

执行 `offline pack` 时，OMW 会构建 `node_package` 或 `node_cache_package` 需要的 OMW Node 版本，加载对应 module，填充 `builds/node/npm-cache`，再压缩为 `packages/npm-cache-$OMW_VERSION.tar.gz`。最终离线包不包含 `builds`，因此该压缩包就是可移植 npm cache 的来源。
