# memo — 提醒事项管理 CLI

一个简洁的命令行提醒事项管理工具，支持一次性提醒和周期性循环提醒。

## 特性

- 📝 **一次性提醒**：指定日期添加提醒，每天可有多条
- 🔁 **循环提醒**：支持每天、每周、每月、每年周期性提醒
- ✅ **完成标记**：标记提醒完成/取消完成，循环提醒按日期标记
- 🔍 **搜索**：按关键词搜索所有提醒
- 🎨 **彩色输出**：终端彩色显示，完成项自动变灰
- 📦 **零依赖**：仅需 Python 3，数据以 JSON 格式存储

## 安装

```bash
# 从 cc-skills 仓库安装
./install.sh memo

# 或直接运行
chmod +x clis/memo/memo
./clis/memo/memo help
```

## 快速开始

```bash
# 添加今天的提醒
memo add "下午3点开会"

# 添加到指定日期
memo add "项目截止" -d 2026-06-15

# 添加循环提醒
memo add "吃药" --daily                    # 每天
memo add "提交周报" --weekly 5              # 每周五
memo add "团队站会" --weekly 1,3,5          # 每周一、三、五
memo add "还信用卡" --monthly 1             # 每月1号
memo add "生日祝福" --yearly 12-25          # 每年12月25日

# 查看今天的提醒
memo

# 查看指定日期
memo list 2026-06-05

# 标记完成
memo done 1                    # 标记 ID 1 完成
memo done 2 2026-06-05         # 标记循环提醒某天完成

# 搜索
memo search "开会"
```

## 命令参考

| 命令 | 说明 |
|------|------|
| `memo` | 显示今天的提醒 |
| `memo list [date]` | 列出某天（默认今天）的提醒 |
| `memo add <text> [-d date]` | 添加一次性提醒 |
| `memo add <text> --daily` | 添加每天循环提醒 |
| `memo add <text> --weekly <days>` | 添加每周循环（1=周一..7=周日） |
| `memo add <text> --monthly <days>` | 添加每月循环（1-31号） |
| `memo add <text> --yearly <MM-DD>` | 添加每年循环提醒 |
| `memo done <id> [date]` | 标记完成 |
| `memo undone <id> [date]` | 取消完成 |
| `memo edit <id> <text>` | 修改提醒内容 |
| `memo rm <id>` | 删除提醒 |
| `memo search <keyword>` | 搜索提醒 |
| `memo help` | 显示帮助信息 |

**命令别名**: `ls` = `list`, `remove`/`del` = `rm`, `find` = `search`, `today` = `list`

## 数据存储

数据存储在 `~/.memo/` 目录：

```
~/.memo/
├── config.json              # 配置（ID 计数器）
├── reminders/               # 一次性提醒（按日期分文件）
│   ├── 2026-06-04.json
│   └── 2026-06-15.json
└── recurring.json           # 所有循环提醒
```

### 一次性提醒格式

```json
[
  {
    "id": 1,
    "text": "下午3点开会",
    "done": false,
    "created_at": "2026-06-04T10:00:00"
  }
]
```

### 循环提醒格式

```json
[
  {
    "id": 4,
    "text": "吃药",
    "freq": "daily",
    "done_dates": ["2026-06-04"],
    "created_at": "2026-06-04"
  },
  {
    "id": 5,
    "text": "提交周报",
    "freq": "weekly",
    "days": [5],
    "done_dates": [],
    "created_at": "2026-06-04"
  }
]
```

## 依赖

- Bash 3.2+（macOS 自带）
- Python 3（用于 JSON 操作和显示逻辑）
