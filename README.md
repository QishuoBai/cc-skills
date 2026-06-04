# cc-skills

个人开发的 Claude Code skills 及配套 CLI 工具集合。

## 快速开始

```bash
git clone https://github.com/QishuoBai/cc-skills.git
cd cc-skills

# 安装所有 CLI 工具
./install

# 或安装指定工具
./install openclaw-watchdog

# 查看可用工具
./install --list
```

安装后 CLI 工具通过 symlink 链接到 `~/.local/bin/`，首次使用请确保该目录在 PATH 中：

```bash
# ~/.zshrc 或 ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
```

## 目录结构

```
├── install           # 安装脚本
├── skills/           # Claude Code skills
└── clis/             # 配套 CLI 工具
    └── openclaw-watchdog/
```

## CLI 工具

| 工具 | 说明 |
|---|---|
| [openclaw-watchdog](clis/openclaw-watchdog/) | OpenClaw Gateway 健康监控，自动检测异常并重启 |

## 添加新 CLI

在 `clis/` 下创建目录，目录内放同名可执行文件即可被 `install` 自动发现：

```
clis/
└── my-tool/
    ├── my-tool      # 可执行文件（必须与目录同名）
    └── README.md    # 可选
```

install 脚本会在文件头查找 `VERSION` 和 `—` 描述，用于 `--list` 展示：

```bash
#!/usr/bin/env bash
#
# my-tool — 这个工具的一句话描述
#
readonly VERSION="1.0.0"
```
