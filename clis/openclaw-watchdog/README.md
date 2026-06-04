# openclaw-watchdog

OpenClaw Gateway 健康监控工具。每 5 分钟自动检查 Gateway 状态，异常时自动重启。

## 为什么需要它

OpenClaw 连接微信时使用 HTTP 长轮询机制，监控循环是单线程串行的。当 AI 模型响应慢、Session 过期（errcode -14 会暂停 1 小时）、或网络抖动导致连续失败时，可能出现长时间无法响应消息的情况。

此工具通过定时健康检查 + 自动重启来解决这类问题。

## 安装

```bash
# 创建符号链接到 PATH
ln -sf /path/to/cc-skills/clis/openclaw-watchdog/openclaw-watchdog /usr/local/bin/
```

## 用法

```bash
# 启动监控（安装 launchd 定时任务）
openclaw-watchdog start

# 查看运行状态
openclaw-watchdog status

# 手动执行一次健康检查（调试用）
openclaw-watchdog check

# 停止监控
openclaw-watchdog stop
```

## 健康检查项

| 检查项 | 方式 | 说明 |
|---|---|---|
| HTTP 健康 | `curl http://127.0.0.1:18789/healthz` | Gateway HTTP 层是否存活 |
| CLI 运行时 | `openclaw gateway status --json` | 进程是否 running |
| 微信 Channel | `openclaw gateway health` | WeChat channel 是否 configured |

任一项失败即触发 `openclaw gateway restart`。

## 防抖机制

- **冷却期 10 分钟**：上次重启后 10 分钟内不会重复重启，避免重启风暴
- **日志轮转**：超过 2000 行时自动保留最后 500 行

## 文件位置

| 文件 | 说明 |
|---|---|
| `~/.openclaw-watchdog/watchdog.sh` | 实际执行的监控脚本（自动生成） |
| `~/.openclaw-watchdog/logs/watchdog.log` | 运行日志 |
| `~/.openclaw-watchdog/state/last-result.json` | 最后一次检查结果 |
| `~/.openclaw-watchdog/state/total-checks` | 累计检查次数 |
| `~/.openclaw-watchdog/state/total-restarts` | 累计重启次数 |
| `~/Library/LaunchAgents/com.cc-skills.openclaw-watchdog.plist` | macOS LaunchAgent |

## 配置

所有参数硬编码在脚本常量中，如需调整可直接修改 `openclaw-watchdog` 脚本顶部的常量：

| 常量 | 默认值 | 说明 |
|---|---|---|
| `INTERVAL_SECONDS` | 300 (5 分钟) | launchd 调度间隔 |
| `COOLDOWN_SECONDS` | 600 (10 分钟) | 重启冷却期 |
| `MAX_LOG_LINES` | 2000 | 日志轮转阈值 |
| `HEALTH_TIMEOUT` | 15 (秒) | HTTP 健康检查超时 |

## 卸载

```bash
openclaw-watchdog stop
rm -rf ~/.openclaw-watchdog    # 可选：清理所有数据
```
