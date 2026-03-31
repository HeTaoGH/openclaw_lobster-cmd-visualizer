# WSL 中运行 OpenClaw（本机运维手册）

## 开机后启动步骤（WSL：Ubuntu‑24.04）

1. 启动网关（监听 18789）

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw gateway --port 18789'
```

2. 打开仪表盘（获取带令牌链接）

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw dashboard'
```

复制输出中的 Dashboard URL（带 token），在 Windows 浏览器打开。例如：

```
http://127.0.0.1:18789/?token=123456
```

## 常用运维命令

- 健康检查

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw health'
```

- 查看网关日志

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw logs --plain --limit 120'
```

- 查看网关令牌

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw config get gateway.auth'
```

- 查看/切换默认模型

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw models status --plain'
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw models set custom/claude-sonnet-4-6'
```

- 直接测试对话

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw agent --agent main --message "测试：请回复 OK" --json --timeout 120'
```

## 停止与重启

- 停止（前台运行时 Ctrl+C 即可；如遇已后台/服务化）

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw gateway stop || pkill -f clawdbot || pkill -f openclaw'
```

- 重启（先停后启）

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw gateway --port 18789'
```

- systemd 方式重启（推荐）

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'systemctl --user restart openclaw-gateway.service'
```

## 单会话模式

- 查看当前所有会话

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw sessions --json'
```

- 当前主会话固定键

```text
agent:main:main
```

- 用固定 session-id 继续同一个会话

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw agent --agent main --session-id 29f2ed36-8f97-4aca-a878-5c8c34e41168 --message "继续刚才的话题" --json --timeout 120'
```

- 只看最近活跃会话

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw sessions --active 120 --json'
```

- 备份会话文件

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'cp ~/.openclaw/agents/main/sessions/sessions.json ~/.openclaw/agents/main/sessions/sessions.json.bak'
```

- 清理旧 cron/subagent 会话，只保留主会话

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'python3 - <<'"'"'"'"'"'"'"'"'PY'"'"'"'"'"'"'"'"'
import json, pathlib
p = pathlib.Path.home()/".openclaw/agents/main/sessions/sessions.json"
data = json.loads(p.read_text(encoding="utf-8"))
data["sessions"] = [s for s in data.get("sessions", []) if s.get("key") == "agent:main:main"]
p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print("kept", len(data["sessions"]), "session")
PY'
```

- 说明
  - 重启网关本身不会自动增加 token。
  - 旧会话保存在 sessions.json 中，通常不会自动参与当前对话计费。
  - 真正影响 token 的主要是你当前正在继续的那个会话，以及是否反复创建新 session-id。
  - 如果你希望一直只接着“第一个会话”聊，核心做法就是固定使用同一个 session-id。

## 端口占用与强制启动

- 端口占用时强制启动

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw gateway --force --port 18789'
```

- 修改端口（例如 19001）

```bash
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw gateway --port 19001'
```

## 4. 目录说明
```bash
# 日志目录（如果 GUI 清空不管用，来这里看原始文件）
~/.openclaw/logs/

# 会话存储目录（sessions.json 和所有 jsonl 文件都在这）
~/.openclaw/agents/main/sessions/

# 备份目录（所有被归档和重置移走的文件都在这）
~/.openclaw/agents/main/sessions/backup/

# 配置文件（可以通过在 Windows 资源管理器输入 \\wsl$\Ubuntu-24.04\home\<你的用户名>\.openclaw 找到）
~/.openclaw/config.json
```

## 常见问题与处理

- 仪表盘未授权（token missing/mismatch）
  - 使用“带 token 的链接”进入，或在控制台设置中粘贴当前令牌
  - 推荐统一域名（127.0.0.1 或 localhost），避免 LocalStorage 跨域

- 页面提示 Gateway not reachable
  - 确认网关已运行：`openclaw health`
  - 如端口被占用，使用 `--force` 或换端口

## 依赖安装（Ubuntu‑24.04）

- 基础依赖（t64 变种自动选择）

```bash
sudo apt-get update
sudo apt-get install -y \
  libxcb-shm0 libx11-xcb1 libx11-6 libxcb1 libxext6 libxrandr2 \
  libxcomposite1 libxcursor1 libxdamage1 libxfixes3 libxi6 \
  libgtk-3-0 libpangocairo-1.0-0 libpango-1.0-0 libatk1.0-0 \
  libcairo-gobject2 libcairo2 libgdk-pixbuf-2.0-0 libxrender1 \
  libasound2t64 libfreetype6 libfontconfig1 libdbus-1-3 libnss3 libnspr4 \
  libatk-bridge2.0-0 libdrm2 libxkbcommon0 libatspi2.0-0 libcups2 \
  libxshmfence1 libgbm1
```

## 一键示例（启动后打开仪表盘）

```powershell
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw gateway --port 18789' 
wsl -d Ubuntu-24.04 -- bash -lc 'openclaw dashboard'
```
