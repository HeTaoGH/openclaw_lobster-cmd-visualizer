# openclaw_lobster-cmd-visualizer
龙虾指令可视化助手
# OpenClaw WSL Launcher

这是一款专为 Windows 用户设计的 **OpenClaw WSL 桌面启动器与会话管理工具**。它提供了一个直观的 GUI 界面，让你无需记忆繁琐的命令行，就能轻松管理运行在 WSL (Ubuntu) 中的 OpenClaw 网关。

## 主要功能

- **一键启动/停止**：快速启动或关闭 OpenClaw 网关。
- **状态监控**：实时查看网关健康状态与本地端口监听情况。
- **双模式管理**：
  - **WebChat 模式**：专为本地仪表盘场景设计，支持清理、重置和归档本地主会话 (`agent:main:main`)。
  - **Feishu 模式**：专为飞书机器人场景设计，提供智能会话识别，支持查看活跃飞书会话摘要，并能安全关闭或归档冗长的历史会话以优化大模型性能。
- **安全退出**：支持保存当前运行快照并安全停止服务，方便下次无缝恢复工作。

## 环境要求

- **操作系统**：Windows 10/11
- **子系统**：WSL2 (默认支持 `Ubuntu-24.04`)
- **环境依赖**：
  - WSL 中已安装并配置好 OpenClaw
  - WSL 中包含 Python 3 (用于执行辅助管理脚本)
  - Windows 端支持 PowerShell 5.1+

## 文件结构

- `OpenClaw-WSL-Launcher.bat`：双击即可运行的启动入口。
- `OpenClaw-WSL-Launcher.ps1`：核心 GUI 与控制逻辑的 PowerShell 脚本。
- `OpenClaw-WSL-Launcher-Guide.md`：详尽的使用说明书。
- `*.py`：辅助会话管理的 Python 脚本（运行于 WSL 环境）。

## 快速上手

1. 将本项目克隆或下载到本地。
2. 确保你的 WSL 环境（默认 `Ubuntu-24.04`）中已经正确部署了 OpenClaw。
3. 双击运行 `OpenClaw-WSL-Launcher.bat`。
4. 在弹出的 GUI 窗口中，根据你当前的对话场景选择 **WebChat** 或 **Feishu** 模式。
5. 点击上方按钮执行对应操作，右侧面板会实时显示执行结果与帮助说明。

## 详细指南

请参阅 [OpenClaw-WSL-Launcher-Guide.md](OpenClaw-WSL-Launcher-Guide.md) 了解每个按钮的具体作用与风险提示。

## 贡献与反馈

欢迎提交 Issue 和 Pull Request，帮助我们一起完善这个启动器！
