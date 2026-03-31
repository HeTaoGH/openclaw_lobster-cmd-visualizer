param(
  [switch]$NoGui,
  [ValidateSet('start','dashboard','status','stop','health','prune','launch','help','resetmain','archivemain','detectfeishu','archivefeishu','closefeishu','safeexit')]
  [string]$Action = 'status',
  [string]$Distro = 'Ubuntu-24.04',
  [int]$Port = 18789
)

$PSNativeCommandUseErrorActionPreference = $false
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$globalConfigPath = Join-Path $PSScriptRoot 'launcher_config.json'

function Load-LauncherConfig {
  if (Test-Path -LiteralPath $globalConfigPath) {
    try {
      $config = Get-Content -LiteralPath $globalConfigPath -Encoding UTF8 | ConvertFrom-Json
      if ($config.Distro) { $script:Distro = $config.Distro }
      if ($config.Port) { $script:Port = $config.Port }
    } catch {}
  }
}

function Save-LauncherConfig {
  param([string]$NewDistro, [int]$NewPort)
  $config = @{
    Distro = $NewDistro
    Port = $NewPort
  }
  $config | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $globalConfigPath -Encoding UTF8
  $script:Distro = $NewDistro
  $script:Port = $NewPort
}

Load-LauncherConfig

function Invoke-WslCommand {
  param([string]$Command)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "wsl.exe"
  $wslCommand = "export LANG=C.UTF-8 LC_ALL=C.UTF-8; $Command"
  $escapedCommand = $wslCommand.Replace('"', '\"')
  $psi.Arguments = "-d $Distro -- bash -lc ""$escapedCommand"""
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  try {
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  } catch {}
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  [void]$proc.Start()
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  $output = ($stdout + [Environment]::NewLine + $stderr).Trim()
  $code = $proc.ExitCode
  [PSCustomObject]@{
    ExitCode = $code
    Output = $output.TrimEnd()
  }
}

function Get-WslPath {
  param([string]$WindowsPath)
  $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
  $normalized = $fullPath -replace '\\', '/'
  if ($normalized -match '^([A-Za-z]):/(.*)$') {
    $drive = $matches[1].ToLower()
    $rest = $matches[2]
    return "/mnt/$drive/$rest"
  }
  return $normalized
}

function Get-GuidePath {
  return (Join-Path $PSScriptRoot 'OpenClaw-WSL-Launcher-Guide.md')
}

function Get-CleanOpenClawSessionsScriptPath {
  return (Join-Path $PSScriptRoot 'clean_openclaw_sessions.py')
}

function Get-ManageMainSessionScriptPath {
  return (Join-Path $PSScriptRoot 'manage_openclaw_main_session.py')
}

function Get-DetectFeishuScriptPath {
  return (Join-Path $PSScriptRoot 'detect_feishu_sessions.py')
}

function Get-ManageFeishuCandidateScriptPath {
  return (Join-Path $PSScriptRoot 'manage_feishu_candidate.py')
}

function Get-SafeExitScriptPath {
  return (Join-Path $PSScriptRoot 'safe_exit_openclaw.py')
}

function Get-ClosedFeishuFilePath {
  return (Join-Path $PSScriptRoot 'closed_feishu_candidates.json')
}

function Get-GuideText {
  $guidePath = Get-GuidePath
  if (Test-Path -LiteralPath $guidePath) {
    return [System.IO.File]::ReadAllText($guidePath, [System.Text.Encoding]::UTF8)
  }
  return "未找到说明书 / Guide file not found.`r`n$guidePath"
}

function Get-DashboardUrl {
  param([string]$Text)
  $m = [regex]::Match($Text, 'http://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9]+')
  if ($m.Success) { return $m.Value }
  $m2 = [regex]::Match($Text, 'http://localhost:\d+/\?token=[A-Za-z0-9]+')
  if ($m2.Success) { return $m2.Value }
  return $null
}

function Normalize-OutputText {
  param([string]$Text)
  if (-not $Text) {
    return $Text
  }
  $normalized = $Text -replace '\x1b\[[0-9;?]*[A-Za-z]', ''
  $normalized = $normalized -replace '\u0000', ''
  return $normalized.Trim()
}

function Get-ButtonGuideText {
  param([string]$Name)
  switch ($Name) {
    'start' {
      return @"
启动网关 / Start

作用
- 启动 WSL 中的 OpenClaw 网关。

执行
- systemctl --user start openclaw-gateway.service
- 如未监听 18789，则回退 openclaw gateway --force --port 18789

影响
- 网关会在线
- 不会自动打开浏览器
- 不会删除任何会话
"@
    }
    'restart' {
      return @"
重启网关 / Restart

实际使用场景
- 【何时用】当网关卡死、模型无响应，或者修改了系统级配置需要生效时。
- 【为什么】相当于强制先停止 (Stop) 再重新启动 (Start)，能解决大部分“僵尸进程”或网络端口占用的问题。

作用
- 强制停止当前正在运行的 OpenClaw 网关。
- 等待资源释放后，重新启动网关。

执行
- 先执行 openclaw gateway stop 和清理残留进程
- 再执行 systemctl --user restart openclaw-gateway.service

影响
- 当前正在进行中的所有对话请求会被打断
- 已经连接的仪表盘/WebChat 可能会提示断开并自动重连
- 【不影响】之前的聊天历史记录和会话数据均安全保留，不会丢失
"@
    }
    'dashboard' {
      return @"
打开仪表盘 / Dashboard

作用
- 获取带 token 的仪表盘地址，并自动打开浏览器。

执行
- openclaw dashboard

影响
- 会打开默认浏览器
- 不会重启网关
"@
    }
    'status' {
      return @"
查看状态 / Status

作用
- 查看网关、渠道、会话与模型摘要。

执行
- timeout 12 openclaw status
- 超时后回退 openclaw health

影响
- 只读，不修改配置
"@
    }
    'health' {
      return @"
健康检查 / Health

作用
- 检查当前运行环境是否正常。

执行
- openclaw health

影响
- 只读，不改配置
"@
    }
    'stop' {
      return @"
停止网关 / Stop

作用
- 停止 WSL 中的 OpenClaw 网关。

执行
- openclaw gateway stop
- 必要时 pkill -f clawdbot / openclaw

影响
- 仪表盘会断开连接
- 不删除历史记录
"@
    }
    'clear' {
      return @"
清空日志 / Clear

作用
- 仅清空左侧窗口日志。

影响
- 不删除 WSL 中真实日志
- 不影响网关和会话
"@
    }
    'prune' {
      return @"
清理单会话 / Prune

实际使用场景
- 【何时用】当你的仪表盘/WebChat 里同时挂着好几个 agent:main:xxx 的会话，看着很乱，想一键清空只留一个主会话时。
- 【为什么】它能快速把环境打扫干净，减少多会话带来的干扰。

作用
- 清理多余会话，只保留主会话 agent:main:main。

执行
- clean_openclaw_sessions.py

影响
- 会备份 sessions.json
- 会刷新顶部主会话信息
"@
    }
    'launch' {
      return (
        "一键启动并打开 / Launch",
        "",
        "作用",
        "- 一次完成 '启动网关 + 打开仪表盘'。",
        "",
        "执行",
        "- 先执行 Start",
        "- 再执行 Dashboard",
        "",
        "影响",
        "- 最适合日常使用"
      ) -join "`r`n"
    }
    'resetmain' {
      return (
        "重置默认主会话 / Reset Main",
        "",
        "实际使用场景",
        "- 【何时用】当你在本地 WebChat/Dashboard 里觉得对话太长，想开一个新话题时。",
        "- 【为什么】只从索引中移除当前默认会话 agent:main:main，旧记录还在硬盘上。",
        "",
        "执行",
        "- manage_openclaw_main_session.py --mode reset",
        "",
        "影响",
        "- 会备份 sessions.json",
        "- 会从索引中移除 agent:main:main",
        "- 不移动旧 jsonl 文件",
        "- 不保证影响飞书当前正在聊的那个会话"
      ) -join "`r`n"
    }
    'archivemain' {
      return (
        "归档并重置主会话 / Archive Main",
        "",
        "实际使用场景",
        "- 【何时用】当你在本地 WebChat 遇到模型反复读旧上下文导致很卡，想彻底切断历史时。",
        "- 【为什么】不仅重置索引，还会把旧的聊天文件移走，比 Reset Main 更彻底。",
        "",
        "执行",
        "- manage_openclaw_main_session.py --mode archive",
        "",
        "影响",
        "- 会备份 sessions.json",
        "- 会把当前主会话 jsonl / lock 文件移到备份目录",
        "- 会从索引中移除 agent:main:main",
        "- 不保证影响飞书当前正在聊的那个会话"
      ) -join "`r`n"
    }
    'help' {
      return Get-GuideText
    }
    'detectfeishu' {
      return @"
识别最近飞书会话 / Detect Feishu

实际使用场景
- 【何时用】当你在飞书里感觉机器人回复越来越慢、或者总是带入旧上下文，但不知道是哪条历史造成的。
- 【为什么】它能帮你把最近活跃的飞书相关会话找出来，让你能看到它们最近聊了什么，辅助你定位“罪魁祸首”。

作用
- 扫描最近会话文件中的飞书标记。
- 给出“最像飞书会话”的候选列表。

影响
- 只读，不删除任何会话，不重置任何上下文。

注意
- 当前仍是启发式识别，不保证 100% 就是你正在聊天的飞书线程。
"@
    }
    'archivefeishu' {
      return @"
归档最近飞书候选 / Archive Feishu

实际使用场景
- 【何时用】当你通过 Detect Feishu 确认某条会话就是导致飞书卡顿的旧历史，并且你想彻底摆脱它时。
- 【为什么】这是最彻底的清理方式，把那个长会话的记录文件直接移走，防止大模型继续读取它。

作用
- 归档当前选中的飞书候选会话文件。
- 尝试从索引中移除对应 sessionId。

影响
- 会备份 sessions.json
- 会移动候选 jsonl / lock 文件到备份目录

注意
- 在 GUI 中，建议先在候选列表里手动选中再执行。
- 执行前请先用 Detect Feishu 看看候选是否合理。
"@
    }
    'closefeishu' {
      return @"
关闭选中飞书候选 / Close Selected

实际使用场景
- 【何时用】当你怀疑某条飞书会话有问题，想先“试着停用一下”看看情况，但又怕误删重要记录时。
- 【为什么】这是一种“软关闭”，它只是告诉系统暂时别用这个会话，但原来的聊天记录文件还稳稳地躺在硬盘里。

作用
- 从会话索引中移除当前选中的飞书候选。

影响
- 会备份 sessions.json
- 原始会话文件仍保留在磁盘上

注意
- 如果软关闭后问题仍在，可以再考虑使用 Archive Feishu 进行彻底归档。
"@
    }
    'safeexit' {
      return @"
安全退出 OpenClaw / Safe Exit

作用
- 保存当前会话索引与活动会话文件快照。
- 记录退出前状态。
- 然后安全停止 OpenClaw 网关。

执行
- safe_exit_openclaw.py

影响
- 不删除会话
- 不清理历史
- 会生成 safe-exit 快照，便于下次继续工作

有什么用
- 适合你今天先收工，想把当前上下文状态尽量稳妥保存下来。
- 下次重新启动后，仍然可以基于已有会话继续干活。
"@
    }
    default {
      return Get-GuideText
    }
  }
}

function Get-ModeGuideText {
  param([string]$Mode)
  switch ($Mode) {
    'feishu' {
      return @"
飞书模式 / Feishu Mode

适用场景
- 你主要在飞书里和 OpenClaw 对话。

请理解
- 飞书会话通常不是当前界面里显示的本地默认主会话 agent:main:main。
- 因此，WebChat 专属的会话管理按钮不会在这里显示，以免误导。

当前建议
- 使用“启动网关 / Start”“查看状态 / Status”“健康检查 / Health”“停止网关 / Stop”做通用运维。
- 可以使用“识别最近飞书会话 / Detect Feishu”查看候选会话。
- 如确认候选合理，可使用“归档最近飞书候选 / Archive Feishu”尝试切断旧上下文。
- 如果你只是想让飞书机器人继续可用，优先处理网关状态，不要误用 WebChat 会话重置按钮。

当前限制
- 这个版本只有启发式识别，还没有精准重置“飞书当前活跃会话”的能力。
"@
    }
    default {
      return @"
WebChat 模式 / WebChat Mode

适用场景
- 你主要通过本地仪表盘 / WebChat 使用 OpenClaw。

你可以使用
- 打开仪表盘 / Dashboard
- 一键启动并打开 / Launch
- 清理单会话 / Prune
- 重置默认主会话 / Reset Main
- 归档并重置主会话 / Archive Main

注意
- 这些“会话管理”按钮作用于本地默认主会话 agent:main:main。
- 它们不等于飞书当前聊天线程。
"@
    }
  }
}

function Get-MainSessionInfo {
  $script = 'python3 -c ''import json, pathlib; p = pathlib.Path.home() / ".openclaw/agents/main/sessions/sessions.json"; d=json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}; s=d.get("agent:main:main", {}); print("agent:main:main|%s" % (s.get("sessionId") or "unknown"))'''
  $res = Invoke-WslCommand -Command $script
  $line = ($res.Output -split "`r?`n" | Select-Object -First 1)
  if (-not $line) {
    return [PSCustomObject]@{ Key = "agent:main:main"; SessionId = "unknown" }
  }
  $parts = $line -split '\|', 2
  return [PSCustomObject]@{
    Key = $parts[0]
    SessionId = if ($parts.Count -gt 1) { $parts[1] } else { "unknown" }
  }
}

function Get-LatestSafeExitInfo {
  $script = @'
python3 - <<'PY'
import json
import pathlib

p = pathlib.Path.home() / ".openclaw/agents/main/safe-exit/latest.json"
if not p.exists():
    print("{}")
    raise SystemExit(0)

try:
    data = json.loads(p.read_text(encoding="utf-8"))
except Exception:
    print("{}")
    raise SystemExit(0)

print(json.dumps(data, ensure_ascii=True))
PY
'@
  $res = Invoke-WslCommand -Command $script
  if ($res.ExitCode -ne 0 -or -not $res.Output) {
    return [PSCustomObject]@{
      HasData = $false
      Timestamp = $null
      SnapshotDir = $null
      ResumeHint = $null
      GatewayStopped = $null
      DryRun = $null
    }
  }
  try {
    $parsed = $res.Output | ConvertFrom-Json
    if (-not $parsed -or -not $parsed.timestamp) {
      throw "no latest safe exit"
    }
    return [PSCustomObject]@{
      HasData = $true
      Timestamp = [string]$parsed.timestamp
      SnapshotDir = [string]$parsed.snapshotDir
      ResumeHint = [string]$parsed.resumeHint
      GatewayStopped = [bool]$parsed.gatewayStopped
      DryRun = [bool]$parsed.dryRun
    }
  } catch {
    return [PSCustomObject]@{
      HasData = $false
      Timestamp = $null
      SnapshotDir = $null
      ResumeHint = $null
      GatewayStopped = $null
      DryRun = $null
    }
  }
}

function Run-OpenClawAction {
  param([string]$Name)
  switch ($Name) {
    'start' {
      $cmd = "systemctl --user start openclaw-gateway.service || true; sleep 1; ss -ltn | grep ':$Port' || true"
      $r = Invoke-WslCommand -Command $cmd
      if ($r.Output -notmatch ":$Port") {
        $fallback = "openclaw gateway --force --port $Port >/tmp/openclaw_manual.log 2>&1 & sleep 1; ss -ltn | grep ':$Port' || true"
        $r = Invoke-WslCommand -Command $fallback
      }
      return $r
    }
    'restart' {
      $stopResult = Run-OpenClawAction -Name 'stop'
      Invoke-WslCommand -Command "sleep 2" | Out-Null
      $startCmd = "systemctl --user restart openclaw-gateway.service || true; sleep 1; ss -ltn | grep ':$Port' || true"
      $r = Invoke-WslCommand -Command $startCmd
      if ($r.Output -notmatch ":$Port") {
        $fallback = "openclaw gateway --force --port $Port >/tmp/openclaw_manual.log 2>&1 & sleep 1; ss -ltn | grep ':$Port' || true"
        $r = Invoke-WslCommand -Command $fallback
      }
      return [PSCustomObject]@{
        ExitCode = $r.ExitCode
        Output = (($stopResult.Output + [Environment]::NewLine + "--- 网关已停止，准备重启 ---" + [Environment]::NewLine + $r.Output).Trim())
      }
    }
    'dashboard' {
      return Invoke-WslCommand -Command "openclaw dashboard"
    }
    'status' {
      return Invoke-WslCommand -Command "timeout 12 openclaw status || openclaw health || true"
    }
    'health' {
      return Invoke-WslCommand -Command "openclaw health"
    }
    'stop' {
      return Invoke-WslCommand -Command "openclaw gateway stop || pkill -f clawdbot || pkill -f openclaw || true"
    }
    'prune' {
      $scriptPath = Get-WslPath -WindowsPath (Get-CleanOpenClawSessionsScriptPath)
      return Invoke-WslCommand -Command "python3 $scriptPath"
    }
    'launch' {
      $startResult = Run-OpenClawAction -Name 'start'
      # 等待网关真正就绪
      Invoke-WslCommand -Command "for i in {1..10}; do if ss -tuln | grep -q ':$Port'; then break; fi; sleep 0.5; done; sleep 1" | Out-Null
      $dashboardResult = Run-OpenClawAction -Name 'dashboard'
      return [PSCustomObject]@{
        ExitCode = $dashboardResult.ExitCode
        Output = (($startResult.Output + [Environment]::NewLine + [Environment]::NewLine + $dashboardResult.Output).Trim())
      }
    }
    'resetmain' {
      $scriptPath = Get-WslPath -WindowsPath (Get-ManageMainSessionScriptPath)
      return Invoke-WslCommand -Command "python3 $scriptPath --mode reset"
    }
    'archivemain' {
      $scriptPath = Get-WslPath -WindowsPath (Get-ManageMainSessionScriptPath)
      return Invoke-WslCommand -Command "python3 $scriptPath --mode archive"
    }
    'detectfeishu' {
      $scriptPath = Get-WslPath -WindowsPath (Get-DetectFeishuScriptPath)
      return Invoke-WslCommand -Command "python3 $scriptPath"
    }
    'archivefeishu' {
      $scriptPath = Get-WslPath -WindowsPath (Get-ManageFeishuCandidateScriptPath)
      return Invoke-WslCommand -Command "python3 $scriptPath --mode archive-top"
    }
    'closefeishu' {
      $scriptPath = Get-WslPath -WindowsPath (Get-ManageFeishuCandidateScriptPath)
      $excludePath = Get-WslPath -WindowsPath (Get-ClosedFeishuFilePath)
      return Invoke-WslCommand -Command "python3 $scriptPath --mode close-top --exclude-file $excludePath"
    }
    'safeexit' {
      $scriptPath = Get-WslPath -WindowsPath (Get-SafeExitScriptPath)
      return Invoke-WslCommand -Command "python3 $scriptPath"
    }
    'help' {
      return [PSCustomObject]@{
        ExitCode = 0
        Output = (Get-GuideText)
      }
    }
    default {
      return [PSCustomObject]@{ ExitCode = 1; Output = "Unknown action: $Name" }
    }
  }
}

if ($NoGui) {
  $res = Run-OpenClawAction -Name $Action
  $text = Normalize-OutputText -Text $res.Output
  $text
  if ($Action -in @('dashboard', 'launch')) {
    $url = Get-DashboardUrl -Text $res.Output
    if ($url) { Start-Process $url | Out-Null }
  }
  exit $res.ExitCode
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$mainSession = Get-MainSessionInfo
$safeExitInfo = Get-LatestSafeExitInfo
$script:pendingAction = $null
$script:pendingButton = $null
$script:pendingOpenUrl = $false
$script:currentMode = 'webchat'
$script:feishuCandidates = @()

$form.Text = "OpenClaw WSL 启动器 / Launcher"
$form.Size = New-Object System.Drawing.Size(1480, 900)
$form.StartPosition = "CenterScreen"

$title = New-Object System.Windows.Forms.Label
$title.Text = "WSL: $Distro  |  端口 / Port: $Port"
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 10)
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)

$sessionLabel = New-Object System.Windows.Forms.Label
$sessionLabel.Text = "固定主会话 / Main Session: $($mainSession.Key)  |  Session ID: $($mainSession.SessionId)"
$sessionLabel.AutoSize = $true
$sessionLabel.Location = New-Object System.Drawing.Point(20, 36)
$sessionLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.Controls.Add($sessionLabel)

$groupCore = New-Object System.Windows.Forms.GroupBox
$groupCore.Text = "通用运维 / Shared"
$groupCore.Location = New-Object System.Drawing.Point(20, 65)
$groupCore.Size = New-Object System.Drawing.Size(980, 85)
$groupCore.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupCore)

$groupConfirm = New-Object System.Windows.Forms.GroupBox
$groupConfirm.Text = "执行控制 / Confirm"
$groupConfirm.Location = New-Object System.Drawing.Point(1020, 65)
$groupConfirm.Size = New-Object System.Drawing.Size(440, 85)
$groupConfirm.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupConfirm)

$groupMode = New-Object System.Windows.Forms.GroupBox
$groupMode.Text = "选择你的使用场景 / Select Mode"
$groupMode.Location = New-Object System.Drawing.Point(20, 160)
$groupMode.Size = New-Object System.Drawing.Size(420, 60)
$groupMode.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupMode)

$radioWebChat = New-Object System.Windows.Forms.RadioButton
$radioWebChat.Text = "WebChat / 仪表盘"
$radioWebChat.Location = New-Object System.Drawing.Point(20, 26)
$radioWebChat.AutoSize = $true
$radioWebChat.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$radioWebChat.Checked = $true
$groupMode.Controls.Add($radioWebChat)

$radioFeishu = New-Object System.Windows.Forms.RadioButton
$radioFeishu.Text = "Feishu / 飞书"
$radioFeishu.Location = New-Object System.Drawing.Point(220, 26)
$radioFeishu.AutoSize = $true
$radioFeishu.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$groupMode.Controls.Add($radioFeishu)

$groupWebChat = New-Object System.Windows.Forms.GroupBox
$groupWebChat.Text = "WebChat 专属 / WebChat"
$groupWebChat.Location = New-Object System.Drawing.Point(20, 230)
$groupWebChat.Size = New-Object System.Drawing.Size(980, 140)
$groupWebChat.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupWebChat)

$groupFeishu = New-Object System.Windows.Forms.GroupBox
$groupFeishu.Text = "飞书操作 / Feishu"
$groupFeishu.Location = New-Object System.Drawing.Point(20, 230)
$groupFeishu.Size = New-Object System.Drawing.Size(980, 140)
$groupFeishu.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5, [System.Drawing.FontStyle]::Bold)
$groupFeishu.Visible = $false
$form.Controls.Add($groupFeishu)

$groupSupport = New-Object System.Windows.Forms.GroupBox
$groupSupport.Text = "帮助说明 / Help"
$groupSupport.Location = New-Object System.Drawing.Point(1020, 160)
$groupSupport.Size = New-Object System.Drawing.Size(440, 210)
$groupSupport.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($groupSupport)

function Set-ButtonAppearance {
  param(
    [System.Windows.Forms.Button]$Button,
    [System.Windows.Forms.Control]$Parent,
    [string]$Text,
    [int]$X,
    [int]$Y,
    [int]$Width,
    [System.Drawing.Color]$BaseColor,
    [System.Drawing.Color]$ActiveColor
  )
  $Button.Text = $Text
  $Button.Size = New-Object System.Drawing.Size($Width, 40)
  $Button.Location = New-Object System.Drawing.Point($X, $Y)
  $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $Button.FlatAppearance.BorderSize = 1
  $Button.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5, [System.Drawing.FontStyle]::Bold)
  $Button.BackColor = $BaseColor
  $Button.ForeColor = [System.Drawing.Color]::Black
  $Button.Tag = [PSCustomObject]@{
    BaseColor = $BaseColor
    ActiveColor = $ActiveColor
  }
  $Parent.Controls.Add($Button)
}

$btnStart = New-Object System.Windows.Forms.Button
$btnRestart = New-Object System.Windows.Forms.Button
$btnDashboard = New-Object System.Windows.Forms.Button
$btnStatus = New-Object System.Windows.Forms.Button
$btnHealth = New-Object System.Windows.Forms.Button
$btnStop = New-Object System.Windows.Forms.Button
$btnClear = New-Object System.Windows.Forms.Button
$btnSafeExit = New-Object System.Windows.Forms.Button
$btnSettings = New-Object System.Windows.Forms.Button
$btnPrune = New-Object System.Windows.Forms.Button
$btnLaunch = New-Object System.Windows.Forms.Button
$btnHelp = New-Object System.Windows.Forms.Button
$btnDetectFeishu = New-Object System.Windows.Forms.Button
$btnArchiveFeishu = New-Object System.Windows.Forms.Button
$btnCloseFeishu = New-Object System.Windows.Forms.Button

$form.Controls.Add($btnSettings)
Set-ButtonAppearance -Button $btnSettings -Parent $form -Text "基础配置 / Settings" -X 1300 -Y 20 -Width 160 -BaseColor ([System.Drawing.Color]::FromArgb(239, 239, 239)) -ActiveColor ([System.Drawing.Color]::FromArgb(180, 180, 180))

Set-ButtonAppearance -Button $btnStart -Parent $groupCore -Text "启动网关 / Start" -X 20 -Y 32 -Width 130 -BaseColor ([System.Drawing.Color]::FromArgb(214, 239, 255)) -ActiveColor ([System.Drawing.Color]::FromArgb(130, 196, 255))
Set-ButtonAppearance -Button $btnRestart -Parent $groupCore -Text "重启网关 / Restart" -X 160 -Y 32 -Width 130 -BaseColor ([System.Drawing.Color]::FromArgb(219, 244, 221)) -ActiveColor ([System.Drawing.Color]::FromArgb(135, 220, 151))
Set-ButtonAppearance -Button $btnStatus -Parent $groupCore -Text "查看状态 / Status" -X 300 -Y 32 -Width 130 -BaseColor ([System.Drawing.Color]::FromArgb(245, 245, 245)) -ActiveColor ([System.Drawing.Color]::FromArgb(210, 210, 210))
Set-ButtonAppearance -Button $btnHealth -Parent $groupCore -Text "健康检查 / Health" -X 440 -Y 32 -Width 130 -BaseColor ([System.Drawing.Color]::FromArgb(235, 230, 200)) -ActiveColor ([System.Drawing.Color]::FromArgb(200, 190, 150))
Set-ButtonAppearance -Button $btnStop -Parent $groupCore -Text "停止网关 / Stop" -X 580 -Y 32 -Width 120 -BaseColor ([System.Drawing.Color]::FromArgb(255, 226, 232)) -ActiveColor ([System.Drawing.Color]::FromArgb(245, 163, 179))
Set-ButtonAppearance -Button $btnClear -Parent $groupCore -Text "清空日志 / Clear" -X 710 -Y 32 -Width 120 -BaseColor ([System.Drawing.Color]::FromArgb(245, 245, 245)) -ActiveColor ([System.Drawing.Color]::FromArgb(210, 210, 210))
Set-ButtonAppearance -Button $btnSafeExit -Parent $groupCore -Text "安全退出 / Safe Exit" -X 840 -Y 32 -Width 130 -BaseColor ([System.Drawing.Color]::FromArgb(230, 244, 255)) -ActiveColor ([System.Drawing.Color]::FromArgb(151, 208, 255))

$btnResetMain = New-Object System.Windows.Forms.Button
$btnArchiveMain = New-Object System.Windows.Forms.Button
Set-ButtonAppearance -Button $btnDashboard -Parent $groupWebChat -Text "打开仪表盘 / Dashboard" -X 20 -Y 32 -Width 180 -BaseColor ([System.Drawing.Color]::FromArgb(220, 255, 224)) -ActiveColor ([System.Drawing.Color]::FromArgb(135, 220, 151))
Set-ButtonAppearance -Button $btnLaunch -Parent $groupWebChat -Text "一键启动并打开 / Launch" -X 210 -Y 32 -Width 220 -BaseColor ([System.Drawing.Color]::FromArgb(255, 230, 186)) -ActiveColor ([System.Drawing.Color]::FromArgb(247, 190, 94))
Set-ButtonAppearance -Button $btnPrune -Parent $groupWebChat -Text "清理单会话 / Prune" -X 440 -Y 32 -Width 180 -BaseColor ([System.Drawing.Color]::FromArgb(240, 226, 255)) -ActiveColor ([System.Drawing.Color]::FromArgb(196, 161, 240))
Set-ButtonAppearance -Button $btnResetMain -Parent $groupWebChat -Text "重置默认主会话 / Reset Main" -X 20 -Y 88 -Width 260 -BaseColor ([System.Drawing.Color]::FromArgb(255, 240, 214)) -ActiveColor ([System.Drawing.Color]::FromArgb(245, 195, 118))
Set-ButtonAppearance -Button $btnArchiveMain -Parent $groupWebChat -Text "归档并重置主会话 / Archive Main" -X 290 -Y 88 -Width 300 -BaseColor ([System.Drawing.Color]::FromArgb(255, 226, 232)) -ActiveColor ([System.Drawing.Color]::FromArgb(245, 163, 179))

$btnConfirm = New-Object System.Windows.Forms.Button
$btnCancelPending = New-Object System.Windows.Forms.Button
Set-ButtonAppearance -Button $btnConfirm -Parent $groupConfirm -Text "确认执行 / Confirm" -X 20 -Y 32 -Width 185 -BaseColor ([System.Drawing.Color]::FromArgb(219, 244, 221)) -ActiveColor ([System.Drawing.Color]::FromArgb(135, 220, 151))
Set-ButtonAppearance -Button $btnCancelPending -Parent $groupConfirm -Text "取消待执行 / Cancel" -X 215 -Y 32 -Width 205 -BaseColor ([System.Drawing.Color]::FromArgb(255, 239, 214)) -ActiveColor ([System.Drawing.Color]::FromArgb(245, 214, 130))
Set-ButtonAppearance -Button $btnHelp -Parent $groupSupport -Text "按钮说明 / Help" -X 20 -Y 32 -Width 170 -BaseColor ([System.Drawing.Color]::FromArgb(230, 244, 255)) -ActiveColor ([System.Drawing.Color]::FromArgb(151, 208, 255))
Set-ButtonAppearance -Button $btnDetectFeishu -Parent $groupFeishu -Text "识别最近飞书会话 / Detect Feishu" -X 20 -Y 32 -Width 300 -BaseColor ([System.Drawing.Color]::FromArgb(214, 239, 255)) -ActiveColor ([System.Drawing.Color]::FromArgb(130, 196, 255))
Set-ButtonAppearance -Button $btnArchiveFeishu -Parent $groupFeishu -Text "归档选中飞书候选 / Archive Selected" -X 340 -Y 32 -Width 300 -BaseColor ([System.Drawing.Color]::FromArgb(255, 226, 232)) -ActiveColor ([System.Drawing.Color]::FromArgb(245, 163, 179))
Set-ButtonAppearance -Button $btnCloseFeishu -Parent $groupFeishu -Text "关闭选中会话 / Close Selected" -X 650 -Y 32 -Width 280 -BaseColor ([System.Drawing.Color]::FromArgb(255, 245, 214)) -ActiveColor ([System.Drawing.Color]::FromArgb(245, 214, 130))

$feishuList = New-Object System.Windows.Forms.ListBox
$feishuList.Location = New-Object System.Drawing.Point(20, 88)
$feishuList.Size = New-Object System.Drawing.Size(760, 48)
$feishuList.Font = New-Object System.Drawing.Font("Consolas", 9)
$groupFeishu.Controls.Add($feishuList)

$chkShowClosedFeishu = New-Object System.Windows.Forms.CheckBox
$chkShowClosedFeishu.Text = "显示已关闭 / Show Closed"
$chkShowClosedFeishu.Location = New-Object System.Drawing.Point(790, 102)
$chkShowClosedFeishu.AutoSize = $true
$chkShowClosedFeishu.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$groupFeishu.Controls.Add($chkShowClosedFeishu)

$modeNote = New-Object System.Windows.Forms.Label
$modeNote.Text = "当前显示的会话管理按钮默认只针对 WebChat / 本地主会话。"
$modeNote.Location = New-Object System.Drawing.Point(460, 166)
$modeNote.Size = New-Object System.Drawing.Size(530, 50)
$modeNote.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.Controls.Add($modeNote)

function Get-SafeExitSummaryText {
  if (-not $safeExitInfo.HasData) {
    return "上次安全退出 / Last Safe Exit: 暂无记录 / None"
  }
  $stopped = if ($safeExitInfo.GatewayStopped) { "yes" } else { "no" }
  return "上次安全退出 / Last Safe Exit: $($safeExitInfo.Timestamp)`r`n网关已停止 / Gateway stopped: $stopped"
}

$split = New-Object System.Windows.Forms.SplitContainer
$split.Location = New-Object System.Drawing.Point(20, 390)
$split.Size = New-Object System.Drawing.Size(1440, 455)
$split.SplitterDistance = 940
$split.IsSplitterFixed = $false
$split.FixedPanel = [System.Windows.Forms.FixedPanel]::None
$form.Controls.Add($split)

$output = New-Object System.Windows.Forms.TextBox
$output.Multiline = $true
$output.ScrollBars = "Vertical"
$output.ReadOnly = $true
$output.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$output.Dock = [System.Windows.Forms.DockStyle]::Fill
$split.Panel1.Controls.Add($output)

$guideBox = New-Object System.Windows.Forms.RichTextBox
$guideBox.ReadOnly = $true
$guideBox.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$guideBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$guideBox.BackColor = [System.Drawing.Color]::FromArgb(252, 252, 252)
$guideBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$guideBox.Text = Get-GuideText
$split.Panel2.Controls.Add($guideBox)

function Highlight-Button {
  param([System.Windows.Forms.Button]$ActiveButton)
  foreach ($button in @($btnStart, $btnRestart, $btnDashboard, $btnStatus, $btnHealth, $btnStop, $btnClear, $btnPrune, $btnLaunch, $btnHelp, $btnResetMain, $btnArchiveMain, $btnConfirm, $btnCancelPending, $btnDetectFeishu, $btnArchiveFeishu, $btnCloseFeishu, $btnSafeExit, $btnSettings)) {
    $style = $button.Tag
    $button.BackColor = $style.BaseColor
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $button.FlatAppearance.BorderSize = 1
  }
  if ($ActiveButton) {
    $activeStyle = $ActiveButton.Tag
    $ActiveButton.BackColor = $activeStyle.ActiveColor
    $ActiveButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $ActiveButton.FlatAppearance.BorderSize = 2
  }
}

function Append-Log {
  param([string]$Text)
  $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $output.AppendText("[$time] $Text`r`n")
}

function Get-FeishuCandidates {
  $scriptPath = Get-WslPath -WindowsPath (Get-DetectFeishuScriptPath)
  $excludePath = Get-WslPath -WindowsPath (Get-ClosedFeishuFilePath)
  $includeClosed = if ($chkShowClosedFeishu.Checked) { " --include-excluded" } else { "" }
  $res = Invoke-WslCommand -Command "python3 $scriptPath --json --exclude-file $excludePath$includeClosed"
  if ($res.ExitCode -ne 0 -or -not $res.Output) {
    return @()
  }
  try {
    $parsed = $res.Output | ConvertFrom-Json
    if ($parsed.candidates) {
      return @($parsed.candidates)
    }
  } catch {}
  return @()
}

function Format-FeishuCandidateItem {
  param($Candidate)
  $shortId = if ($Candidate.sessionId.Length -gt 8) { $Candidate.sessionId.Substring(0, 8) } else { $Candidate.sessionId }
  $sizeKb = [math]::Round(([double]$Candidate.size / 1KB), 1)
  $timeText = if ($Candidate.lastActivityText) { $Candidate.lastActivityText } else { "unknown" }
  $summary = if ($Candidate.humanSummary) { $Candidate.humanSummary } else { $Candidate.preview }
  $summary = if ($summary.Length -gt 56) { $summary.Substring(0, 56) + "..." } else { $summary }
  $closedTag = if ($Candidate.excluded) { "[closed] " } else { "" }
  return "{0}{1} | s={2} | {3} | {4}KB | {5}" -f $closedTag, $shortId, $Candidate.score, $timeText, $sizeKb, $summary
}

function Get-FeishuCandidateDetailText {
  param($Candidate)
  if (-not $Candidate) {
    return "未选中飞书候选 / No Feishu candidate selected"
  }
  $sizeKb = [math]::Round(([double]$Candidate.size / 1KB), 1)
  $markers = if ($Candidate.markers) { $Candidate.markers -join ',' } else { "none" }
  $preview = if ($Candidate.preview) { $Candidate.preview } else { "none" }
  $summary = if ($Candidate.humanSummary) { $Candidate.humanSummary } else { "none" }
  $recentEvents = if ($Candidate.recentEvents) { @($Candidate.recentEvents) } else { @() }
  $recentText = if ($recentEvents.Count -gt 0) { ($recentEvents | ForEach-Object { "- $_" }) -join "`r`n" } else { "- none" }
  $closedText = if ($Candidate.excluded) { "yes" } else { "no" }
  return (
    "飞书候选详情 / Feishu Candidate",
    "- sessionId: $($Candidate.sessionId)",
    "- score: $($Candidate.score)",
    "- closed: $closedText",
    "- lastActivity: $($Candidate.lastActivityText)",
    "- sizeKB: $sizeKb",
    "- markers: $markers",
    "- summary: $summary",
    "- preview: $preview",
    "",
    "最近对话摘要 / Recent Activity",
    $recentText
  ) -join "`r`n"
}

function Show-SelectedFeishuCandidate {
  $selected = Get-SelectedFeishuCandidate
  if ($selected) {
    $guideBox.Text = Get-FeishuCandidateDetailText -Candidate $selected
  } else {
    $guideBox.Text = Get-ModeGuideText -Mode 'feishu'
  }
  $guideBox.SelectionStart = 0
  $guideBox.ScrollToCaret()
}

function Refresh-FeishuCandidates {
  $script:feishuCandidates = @(Get-FeishuCandidates)
  $feishuList.Items.Clear()
  foreach ($candidate in $script:feishuCandidates) {
    [void]$feishuList.Items.Add((Format-FeishuCandidateItem -Candidate $candidate))
  }
  if ($feishuList.Items.Count -gt 0) {
    $feishuList.SelectedIndex = 0
  }
}

function Get-SelectedFeishuCandidate {
  if ($feishuList.SelectedIndex -lt 0) {
    return $null
  }
  if ($feishuList.SelectedIndex -ge $script:feishuCandidates.Count) {
    return $null
  }
  return $script:feishuCandidates[$feishuList.SelectedIndex]
}

function Set-PendingAction {
  param(
    [string]$Name,
    [System.Windows.Forms.Button]$Button,
    [bool]$OpenUrl = $false
  )
  Highlight-Button -ActiveButton $Button
  $guideBox.Text = Get-ButtonGuideText -Name $Name
  if ($Name -in @('archivefeishu', 'closefeishu')) {
    $selected = Get-SelectedFeishuCandidate
    if ($selected) {
      $guideBox.Text += "`r`n`r`n" + (Get-FeishuCandidateDetailText -Candidate $selected)
    } else {
      $guideBox.Text += "`r`n`r`n当前未选中候选 / No candidate selected"
    }
  }
  $guideBox.SelectionStart = 0
  $guideBox.ScrollToCaret()
  $script:pendingAction = $Name
  $script:pendingButton = $Button
  $script:pendingOpenUrl = $OpenUrl
  Append-Log "已选择操作 / Selected action: $Name"
  Append-Log "请阅读右侧说明，然后点击“确认执行 / Confirm”"
  Append-Log "----------------------------------------"
}

function Clear-PendingAction {
  $script:pendingAction = $null
  $script:pendingButton = $null
  $script:pendingOpenUrl = $false
}

function Set-ModeUI {
  param([string]$Mode)
  $script:currentMode = $Mode
  Clear-PendingAction
  if ($Mode -eq 'feishu') {
    $groupWebChat.Visible = $false
    $groupFeishu.Visible = $true
    $modeNote.Text = "当前为飞书模式：只显示通用运维；WebChat 会话管理已隐藏。`r`n$(Get-SafeExitSummaryText)"
    Refresh-FeishuCandidates
    Show-SelectedFeishuCandidate
  } else {
    $groupWebChat.Visible = $true
    $groupFeishu.Visible = $false
    $modeNote.Text = "当前为 WebChat 模式：会话管理按钮作用于本地默认主会话。`r`n$(Get-SafeExitSummaryText)"
  }
  if ($Mode -ne 'feishu') {
    $guideBox.Text = Get-ModeGuideText -Mode $Mode
    $guideBox.SelectionStart = 0
    $guideBox.ScrollToCaret()
  }
  Highlight-Button -ActiveButton $btnHelp
  Append-Log "已切换模式 / Mode switched: $Mode"
  Append-Log "----------------------------------------"
}

function Execute-Action {
  if (-not $script:pendingAction) {
    Append-Log "没有待执行动作 / No pending action"
    return
  }
  $Name = $script:pendingAction
  $OpenUrl = $script:pendingOpenUrl
  $Button = $script:pendingButton
  Append-Log "执行 / Run: $Name"
  Highlight-Button -ActiveButton $Button
  if ($Name -eq 'clear') {
    $output.Clear()
    $guideBox.Text = Get-ButtonGuideText -Name 'clear'
    Clear-PendingAction
    return
  }
  if ($Name -in @('archivefeishu', 'closefeishu')) {
    $selected = Get-SelectedFeishuCandidate
    if (-not $selected) {
      Append-Log "未选择飞书候选 / No Feishu candidate selected"
      Append-Log "----------------------------------------"
      Clear-PendingAction
      return
    }
    $scriptPath = Get-WslPath -WindowsPath (Get-ManageFeishuCandidateScriptPath)
    $modeArg = if ($Name -eq 'closefeishu') { 'close-session' } else { 'archive-session' }
    $excludePath = Get-WslPath -WindowsPath (Get-ClosedFeishuFilePath)
    $res = Invoke-WslCommand -Command "python3 $scriptPath --mode $modeArg --session-id $($selected.sessionId) --exclude-file $excludePath"
  } else {
    $res = Run-OpenClawAction -Name $Name
  }
  $text = Normalize-OutputText -Text $res.Output
  if ($text) {
    Append-Log $text
  } else {
    Append-Log "无输出 / No output"
  }
  Append-Log "ExitCode=$($res.ExitCode)"
  if ($OpenUrl -or $Name -eq 'launch') {
    $url = Get-DashboardUrl -Text $res.Output
    if ($url) {
      Start-Process $url | Out-Null
      Append-Log "已打开 / Opened: $url"
    } else {
      Append-Log "未找到带 token 的仪表盘链接 / No tokenized dashboard URL found"
    }
  }
  if ($Name -eq 'prune') {
    $script:mainSession = Get-MainSessionInfo
    $sessionLabel.Text = "固定主会话 / Main Session: $($script:mainSession.Key)  |  Session ID: $($script:mainSession.SessionId)"
    Append-Log "已刷新主会话信息 / Main session info refreshed"
  }
  if ($Name -in @('resetmain', 'archivemain')) {
    $script:mainSession = Get-MainSessionInfo
    $sessionLabel.Text = "固定主会话 / Main Session: $($script:mainSession.Key)  |  Session ID: $($script:mainSession.SessionId)"
    Append-Log "已更新默认主会话索引 / Main session index updated"
  }
  if ($Name -in @('detectfeishu', 'archivefeishu', 'closefeishu')) {
    Refresh-FeishuCandidates
    if ($script:currentMode -eq 'feishu') {
      Show-SelectedFeishuCandidate
    }
  }
  Append-Log "----------------------------------------"
  Clear-PendingAction
  if ($Name -eq 'safeexit' -and $res.ExitCode -eq 0) {
    Append-Log "安全退出完成 / Safe exit completed"
    $form.Close()
  }
}

$btnSettings.Add_Click({
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "基础配置 / Settings"
  $dlg.Size = New-Object System.Drawing.Size(400, 240)
  $dlg.StartPosition = "CenterParent"
  $dlg.FormBorderStyle = "FixedDialog"
  $dlg.MaximizeBox = $false
  $dlg.MinimizeBox = $false

  $lblDistro = New-Object System.Windows.Forms.Label
  $lblDistro.Text = "WSL 发行版名称 (Distro):"
  $lblDistro.Location = New-Object System.Drawing.Point(20, 20)
  $lblDistro.AutoSize = $true
  $dlg.Controls.Add($lblDistro)

  $txtDistro = New-Object System.Windows.Forms.TextBox
  $txtDistro.Text = $script:Distro
  $txtDistro.Location = New-Object System.Drawing.Point(20, 45)
  $txtDistro.Size = New-Object System.Drawing.Size(340, 25)
  $dlg.Controls.Add($txtDistro)

  $lblPort = New-Object System.Windows.Forms.Label
  $lblPort.Text = "网关监听端口 (Port):"
  $lblPort.Location = New-Object System.Drawing.Point(20, 85)
  $lblPort.AutoSize = $true
  $dlg.Controls.Add($lblPort)

  $txtPort = New-Object System.Windows.Forms.TextBox
  $txtPort.Text = $script:Port.ToString()
  $txtPort.Location = New-Object System.Drawing.Point(20, 110)
  $txtPort.Size = New-Object System.Drawing.Size(340, 25)
  $dlg.Controls.Add($txtPort)

  $btnSave = New-Object System.Windows.Forms.Button
  $btnSave.Text = "保存并重启 / Save"
  $btnSave.Location = New-Object System.Drawing.Point(80, 155)
  $btnSave.Size = New-Object System.Drawing.Size(120, 30)
  $btnSave.Add_Click({
    $newDistro = $txtDistro.Text.Trim()
    $newPort = 0
    if (-not [int]::TryParse($txtPort.Text.Trim(), [ref]$newPort)) {
      [System.Windows.Forms.MessageBox]::Show("端口号必须是数字！", "错误", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
      return
    }
    Save-LauncherConfig -NewDistro $newDistro -NewPort $newPort
    $dlg.DialogResult = "OK"
    $dlg.Close()
  })
  $dlg.Controls.Add($btnSave)

  $btnCancel = New-Object System.Windows.Forms.Button
  $btnCancel.Text = "取消 / Cancel"
  $btnCancel.Location = New-Object System.Drawing.Point(210, 155)
  $btnCancel.Size = New-Object System.Drawing.Size(100, 30)
  $btnCancel.DialogResult = "Cancel"
  $dlg.Controls.Add($btnCancel)

  if ($dlg.ShowDialog() -eq "OK") {
    Append-Log "配置已更新，重启启动器以生效 / Config saved, restarting..."
    Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $form.Close()
  }
})
$btnStart.Add_Click({ Set-PendingAction -Name 'start' -Button $btnStart })
$btnRestart.Add_Click({ Set-PendingAction -Name 'restart' -Button $btnRestart })
$btnDashboard.Add_Click({ Set-PendingAction -Name 'dashboard' -Button $btnDashboard -OpenUrl $true })
$btnStatus.Add_Click({ Set-PendingAction -Name 'status' -Button $btnStatus })
$btnHealth.Add_Click({ Set-PendingAction -Name 'health' -Button $btnHealth })
$btnStop.Add_Click({ Set-PendingAction -Name 'stop' -Button $btnStop })
$btnClear.Add_Click({ Set-PendingAction -Name 'clear' -Button $btnClear })
$btnSafeExit.Add_Click({ Set-PendingAction -Name 'safeexit' -Button $btnSafeExit })
$btnPrune.Add_Click({ Set-PendingAction -Name 'prune' -Button $btnPrune })
$btnLaunch.Add_Click({ Set-PendingAction -Name 'launch' -Button $btnLaunch -OpenUrl $true })
$btnHelp.Add_Click({
  Highlight-Button -ActiveButton $btnHelp
  $guideBox.Text = (Get-ModeGuideText -Mode $script:currentMode) + "`r`n`r`n------------------------------`r`n`r`n" + (Get-GuideText)
  $guideBox.SelectionStart = 0
  $guideBox.ScrollToCaret()
  Clear-PendingAction
  Append-Log "已显示说明书 / Guide shown"
  Append-Log "----------------------------------------"
})
$btnResetMain.Add_Click({ Set-PendingAction -Name 'resetmain' -Button $btnResetMain })
$btnArchiveMain.Add_Click({ Set-PendingAction -Name 'archivemain' -Button $btnArchiveMain })
$btnDetectFeishu.Add_Click({ Set-PendingAction -Name 'detectfeishu' -Button $btnDetectFeishu })
$btnArchiveFeishu.Add_Click({ Set-PendingAction -Name 'archivefeishu' -Button $btnArchiveFeishu })
$btnCloseFeishu.Add_Click({ Set-PendingAction -Name 'closefeishu' -Button $btnCloseFeishu })
$feishuList.Add_SelectedIndexChanged({
  if ($script:currentMode -eq 'feishu') {
    Show-SelectedFeishuCandidate
  }
})
$btnConfirm.Add_Click({ Execute-Action })
$btnCancelPending.Add_Click({
  Clear-PendingAction
  Highlight-Button -ActiveButton $btnHelp
  $guideBox.Text = (Get-ModeGuideText -Mode $script:currentMode) + "`r`n`r`n------------------------------`r`n`r`n" + (Get-GuideText)
  $guideBox.SelectionStart = 0
  $guideBox.ScrollToCaret()
  Append-Log "已取消待执行动作 / Pending action cancelled"
  Append-Log "----------------------------------------"
})
$radioWebChat.Add_CheckedChanged({ if ($radioWebChat.Checked) { Set-ModeUI -Mode 'webchat' } })
$radioFeishu.Add_CheckedChanged({ if ($radioFeishu.Checked) { Set-ModeUI -Mode 'feishu' } })
$chkShowClosedFeishu.Add_CheckedChanged({
  if ($script:currentMode -eq 'feishu') {
    Refresh-FeishuCandidates
    Show-SelectedFeishuCandidate
  }
})

Append-Log "启动器已就绪 / Launcher is ready."
Append-Log "固定主会话 / Main Session: $($mainSession.Key)"
Append-Log "会话ID / Session ID: $($mainSession.SessionId)"
Append-Log "交互方式 / Interaction: 先点按钮查看右侧说明，再点确认执行"
if ($safeExitInfo.HasData) {
  Append-Log "上次安全退出 / Last Safe Exit: $($safeExitInfo.Timestamp)"
  Append-Log "快照位置 / Snapshot: $($safeExitInfo.SnapshotDir)"
  Append-Log "恢复提示 / Resume: $($safeExitInfo.ResumeHint)"
}
Set-ModeUI -Mode 'webchat'

[void]$form.ShowDialog()
