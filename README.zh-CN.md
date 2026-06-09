# OMW (Oh My Workspace)

[English](./README.md) | [简体中文](./README.zh-CN.md)

OMW 是一个面向 Linux 的自包含工作区管理工具。它负责源码构建、预编译应用安装、Shell 与编辑器配置，并可生成适用于离线机器的完整部署包。

补充文档：

- [支持资源](docs/resources.zh-CN.md)
- [Vim 配置](docs/vim.zh-CN.md)

## 功能

- 按依赖顺序构建源码软件，并生成 modulefile
- 安装预编译命令行工具并建立软链
- 使用离线 npm cache 管理全局 Node 包
- 准备 Zsh、Tmux、Vim 配置压缩包
- 生成和校验完整离线部署包
- 将系统 RPM 解压到私有目录，无需 root 安装

## 环境要求

- Linux 与 Bash 4 或更新版本
- 常用工具：`wget tar make git rpm2cpio cpio sed find nproc yumdownloader unzip`
- 提供 `module` 命令的 Environment Modules 或 Lmod
- 在线准备阶段需要网络；离线恢复阶段不需要网络

在 RHEL/CentOS 系统中，通常需要安装 `environment-modules` 和 `yum-utils`。

## 快速开始

```bash
chmod +x ./omw

# 将 env.sh 加入 ~/.bashrc
./omw init
source ~/.bashrc

# 查看可安装项与状态
./omw status

# 源码构建 -> 配置恢复 -> 应用安装 -> Node 全局包安装
./omw all
```

`./omw init` 只负责将 `env.sh` 接入 Shell，不会自动构建或安装软件。

## 常用命令

运行 `./omw --help` 查看紧凑的命令总览，或运行
`./omw help <command>` 查看对应命令的详细帮助。

### 初始化

- `./omw init`：将 OMW 环境接入 `~/.bashrc`。
- `./omw all [--force] [--refresh]`：依次执行源码构建、配置恢复、应用安装和 Node 全局包安装。

### 软件包

- `./omw build <software[@version]|all> [--force] [--refresh]`：构建源码软件。
- `./omw build prepare <software[@version]|all>`：只下载源码包和构建依赖包，不执行编译。
- `./omw app install <app> [--force]`：安装一个预编译应用。
- `./omw app install-all [--force]`：安装全部预编译应用。
- `./omw node pack|verify|restore-cache`：管理离线 npm cache。
- `./omw node install <alias>`：安装一个已声明的 Node 全局包。
- `./omw node install-all`：安装全部已声明的 Node 全局包。

### 配置

- `./omw config <tmux|vim|zsh|all> [--force]`：离线恢复 Shell 或编辑器配置。
- `./omw config prepare <tmux|vim|zsh|all> [--force]`：在线准备配置资产和压缩包。

### 离线工作流

- `./omw offline pack [--force]`：准备全部资源并生成完整离线包。
- `./omw offline verify`：校验离线资源。
- `./omw upgrade <bundle.tar.gz|extracted-dir> [--dry-run] [--replace-packages]`：从新版离线包升级当前工作区。

### 维护

- `./omw status [installed]`：查看可安装项目，或只查看已安装项目。
- `./omw doctor [profile]`：检查本地 OMW 运行环境，不修改文件。
- `./omw update check`：检查受支持的上游版本。
- `./omw clean <builds|packages|config|installs|apps|node|all> [--dry-run]`：删除或预览生成物。`all` 会保留可部署缓存，便于随后通过 `./omw all` 恢复工作区；使用 `packages` 可删除下载包与打包缓存。

`./omw config prepare <target|all> --force` 会重新下载生成资产并覆盖配置压缩包。
`./omw offline pack --force` 会在生成完整离线包前执行同样的刷新。刷新失败时会恢复原有资产。
通用参数 `--no-color` 可关闭颜色输出，`--version` 可显示 OMW 版本。使用
`--refresh` 可只重新生成 modulefile 并跳过源码重建，使用 `clean --dry-run`
可预览待删除路径。`upgrade --replace-packages` 会用离线包中的 `packages/`
完整替换当前 package 缓存；默认只合并新增或更新的资产。

## 支持资源

源码软件、预编译应用、Node 全局包、只进入缓存的 Node 包、modulefile 和本地 RPM 层都通过 `packages.sh` 声明和准备。支持的资源类型、注册函数和离线缓存产物见 [docs/resources.zh-CN.md](docs/resources.zh-CN.md)。

## 离线工作流

### 在线机器

```bash
chmod +x ./omw
./omw init
source ~/.bashrc

# 下载缺失资源、准备配置压缩包并生成总离线包
./omw offline pack
```

`./omw offline pack` 会自动执行：

1. 下载源码包和预编译应用。
2. 准备 GCC 依赖和本地 RPM。
3. 准备并覆盖生成 `packages/config-<target>-$OMW_VERSION.tar.gz`。
4. 准备 Node 全局包 npm cache。
5. 校验离线资源。
6. 生成 `$OMW_HOME/omw-offline-bundle-vVERSION.tar.gz`。

也可以只准备配置：

```bash
./omw config prepare vim
./omw config prepare all
```

### 离线机器

```bash
tar -xzf omw-offline-bundle-*.tar.gz
cd oh-my-workspace
chmod +x ./omw
./omw init
source ~/.bashrc

./omw offline verify
./omw all
```

普通 `config` 和 `./omw all` 只解压已有配置包，不会 clone 仓库，也不会执行联网 npm 安装。

### 升级已有工作区

当离线机器上已经有一个 OMW 工作区时，可以直接用新版离线包升级，而不必重新解压到新目录。
支持的升级基线是 `0.1.0`，0.1.0 之前的旧 bundle 布局不支持：

```bash
./omw upgrade /path/to/omw-offline-bundle-vVERSION.tar.gz --dry-run
./omw upgrade /path/to/omw-offline-bundle-vVERSION.tar.gz
```

输入可以是 `.tar.gz` 离线包，也可以是已解压的 bundle 目录。升级会事务化更新
OMW 管理文件，安装 `lib/$OMW_VERSION/`，合并 `packages/`，并在最后切换
`VERSION`。升级不会直接替换 `config/`；之后由 `./omw config` 或 `./omw all`
从新版 `packages/config-<target>-$OMW_VERSION.tar.gz` 恢复版本化运行配置，
因此 `config/local/` 会保持不变。

`--dry-run` 会打印真实执行路径使用的同一份升级计划，并展示 source/target 路径、
manifest 摘要、路径策略以及每个管理路径的执行决策。新版离线包必须包含
`.omw-bundle-manifest`；旧离线包需要先用
`./omw offline pack` 重新生成。manifest 采用 tab 分隔的 v2 格式，记录文件、目录、软链、文件 md5 和 mode，不使用
JSON。真实执行时未变化的路径会跳过。升级过程中任一步骤失败时，OMW 会在返回前回滚事务。

默认情况下，`packages/` 采用临时目录合并后事务替换：先复制当前 package 缓存，
再按 manifest 覆盖离线包中记录不同或本地缺失的条目，最后整体替换回
`packages/`。普通 OMW 管理路径采用精确替换策略，未出现在 bundle manifest 中的
本地额外 package 压缩包会保留。离线包中
包含 `packages/npm-cache-$OMW_VERSION.tar.gz` 时，OMW 会
先把当前 npm cache 备份到 `backups/npm-cache/`，清理 staged cache，然后一律采用
离线包里的 npm cache。需要让 package 缓存与离线包完全一致时，使用：

```bash
./omw upgrade /path/to/extracted/oh-my-workspace --replace-packages
```

## 配置目录

配置包规则：

```text
packages/config-tmux-$OMW_VERSION.tar.gz
packages/config-vim-$OMW_VERSION.tar.gz
packages/config-zsh-$OMW_VERSION.tar.gz
```

仓库中维护的配置源目录不带版本号：

```text
config/tmux/tmux.default
config/vim/vimrc.default
config/zsh/zshrc.default
```

离线 bundle 不直接包含版本化运行目录，而是携带：

```text
packages/config-tmux-$OMW_VERSION.tar.gz
packages/config-vim-$OMW_VERSION.tar.gz
packages/config-zsh-$OMW_VERSION.tar.gz
```

目标机器运行 `./omw config` 或 `./omw all` 后，再将它们恢复到
`config/$OMW_VERSION/<target>`。

以下用户覆盖配置始终保留本地版本，`--force` 也不会覆盖：

```text
config/local/tmux.local
config/local/vimrc.local
config/local/zshrc.local
```

`config/vim/plugins.list`、`config/vim/coc/coc-settings.json` 和
`config/vim/coc/extensions.list` 是在线准备输入文件。离线恢复不会修改这些文件，
只会解压已有压缩包并写入 `~/.vimrc` loader。本地覆盖仅涉及一个扁平文件：
`config/local/vimrc.local`。Vim/Coc 准备流程见 [docs/vim.zh-CN.md](docs/vim.zh-CN.md)。
使用 `--force` 时，只刷新默认配置和生成依赖目录。
### Zsh

在线准备时下载：

```text
config/zsh/.oh-my-zsh
config/zsh/.oh-my-zsh/custom/themes/powerlevel10k
config/zsh/.oh-my-zsh/custom/plugins/zsh-autosuggestions
config/zsh/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

离线恢复到 `config/$OMW_VERSION/zsh` 后会链接 `~/.oh-my-zsh`，并从模板重建 `~/.zshrc`。

### Tmux

在线准备时下载：

```text
config/tmux/.tmux
```

离线恢复会建立：

```text
~/.tmux.conf       -> $OMW_HOME/config/$OMW_VERSION/tmux/.tmux/.tmux.conf
~/.tmux.conf.local -> $OMW_HOME/config/$OMW_VERSION/tmux/tmux.default
```

本地覆盖配置放在 `config/local/tmux.local`。

### Vim

Vim 9 插件、Coc 设置、Coc 插件固定版本和离线本地覆盖规则见 [docs/vim.zh-CN.md](docs/vim.zh-CN.md)。离线本地覆盖文件为 `config/local/vimrc.local`。

## 清理

```bash
./omw clean config
```

该命令会同时清理仓库源配置和版本化运行配置中的下列可重新生成依赖：

```text
config/tmux/.tmux
config/vim/vim9/pack
config/vim/coc/extensions
config/zsh/.oh-my-zsh
config/$OMW_VERSION/tmux/.tmux
config/$OMW_VERSION/vim/vim9/pack
config/$OMW_VERSION/vim/coc/extensions
config/$OMW_VERSION/zsh/.oh-my-zsh
```

`./omw clean packages` 会删除整个 `packages/`，并同时执行相同的配置依赖清理。

## 目录结构

```text
VERSION     OMW 全局版本
config/     仓库配置源 config/<target>，运行配置 config/<version>，本地覆盖 config/local
lib/        OMW 实现模块，发布包优先加载 lib/<version>/
packages/   扁平化下载包与离线压缩包
builds/     临时构建目录
tools/      编译安装的软件与 modulefile
apps/       预编译应用
bin/        应用软链
```

`lib/` 按职责拆分：

```text
common.sh    初始化、日志、配置校验、备份与链接辅助函数
fs.sh        安全文件操作、下载、解压与压缩包校验
tx.sh        事务备份、回滚、提交与临时路径清理
registry.sh  packages.sh 声明查询与 URL 渲染
workflow.sh  all、build-all、config-all、clean 等命令编排
doctor.sh    本地运行环境健康检查
cli.sh    命令解析、注册、分发与内置帮助
status.sh    状态表与上游版本检查
build.sh     源码构建、专用构建钩子与 modulefile
app.sh       预编译应用安装与专用安装钩子
node.sh      npm cache 打包、校验与离线安装
config.sh    tmux/vim/zsh 配置准备与恢复
offline.sh   离线资源校验、配置打包与 bundle 创建
upgrade.sh   离线升级计划、预览与事务化执行
```

## 常见问题

- 缺少依赖：在在线机器安装日志列出的系统工具。
- 找不到 `module`：安装 Environment Modules 或 Lmod，并确保 `module` 已载入。
- Coc 插件缺失：在在线机器重新执行 `./omw config prepare vim` 或 `./omw offline pack`。
- 构建失败：检查 `builds/<name>-<version>/logs/`。
- SELinux 或权限错误：检查目标目录权限与 SELinux context。
