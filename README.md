# cc-skills

个人开发的 Claude Code skills 及配套 CLI 工具集合。

## 快速开始

```bash
git clone https://github.com/QishuoBai/cc-skills.git
cd cc-skills

# 安装所有 CLI 和 Skills
./install.sh

# 仅安装 CLI 工具
./install.sh --cli

# 仅安装 Skills
./install.sh --skill

# 安装指定项
./install.sh memo

# 查看可用项及状态
./install.sh --list
```

安装后 CLI 工具通过 symlink 链接到 `~/.local/bin/`，首次使用请确保该目录在 PATH 中（install.sh 会自动配置）。Skills 通过 symlink 链接到 `~/.claude/skills/`，需要已安装 [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)。

## 目录结构

```
├── install.sh            # 安装脚本（CLI + Skills）
├── skills/               # Claude Code skills
│   └── memo/
└── clis/                 # 配套 CLI 工具
    ├── memo/
    └── openclaw-watchdog/
```

## CLI 工具

| 工具 | 说明 |
|---|---|
| [memo](clis/memo/) | 提醒事项管理，支持一次性和周期性循环提醒 |
| [openclaw-watchdog](clis/openclaw-watchdog/) | OpenClaw Gateway 健康监控，自动检测异常并重启 |

## Skills

| Skill | 说明 |
|---|---|
| [memo](skills/memo/) | 让 Claude Code 通过 memo CLI 管理提醒事项和备忘 |

## 添加新 CLI

在 `clis/` 下创建目录，目录内放同名可执行文件即可被 `install.sh` 自动发现：

```
clis/
└── my-tool/
    ├── my-tool      # 可执行文件（必须与目录同名）
    └── README.md    # 可选
```

install.sh 脚本会在文件头查找 `VERSION` 和 `—` 描述，用于 `--list` 展示：

```bash
#!/usr/bin/env bash
#
# my-tool — 这个工具的一句话描述
#
readonly VERSION="1.0.0"
```

## 添加新 Skill

在 `skills/` 下创建目录，目录内放 `SKILL.md` 文件即可被 `install.sh` 自动发现：

```
skills/
└── my-skill/
    └── SKILL.md     # 必须包含 YAML frontmatter（name + description）
```

SKILL.md 的 frontmatter 格式：

```yaml
---
name: my-skill
description: >
  这个 skill 的一句话描述。
---
```
