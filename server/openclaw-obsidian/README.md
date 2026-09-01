# AILearningOS → OpenClaw → Obsidian

这套文件把 AILearningOS 服务器生成的 Markdown 知识库挂载给服务器上的
OpenClaw（Claw）。它不是另起一个图形化 Obsidian 容器：Obsidian vault 就是
文件夹，桌面端 Obsidian 可以直接打开同一个目录，OpenClaw 则在服务器上读写
同一份 Markdown。

## 当前可用范围

AILearningOS 已经会把 ChatGPT、Outlook 和 QQ 的自动摘要写到：

```text
server/data/obsidian-vault/{userId}/{category}/...
```

同一个 `source_id` 重试时会覆盖同一条笔记，避免重复。Claw 接入后可以用
`memory-wiki` 对这个 vault 做检索、编译、反向链接和仪表盘维护。

## 部署步骤

以下命令在 OpenClaw 官方仓库根目录执行。先确保官方 Docker 安装已经完成，且
该目录存在 `docker-compose.yml`。

### 1. 设置宿主机 vault 路径

把 `.env.example` 的内容合并到 OpenClaw 的 `.env`，把路径改成实际服务器上
某一个用户的绝对路径。例如 Linux：

```dotenv
AI_STUDY_OBSIDIAN_VAULT_HOST_PATH=/opt/ai-study-os/server/data/obsidian-vault/1
OPENCLAW_TZ=Asia/Shanghai
```

Windows Docker Desktop 示例：

```dotenv
AI_STUDY_OBSIDIAN_VAULT_HOST_PATH=D:/AI-自学OS/server/data/obsidian-vault/1
OPENCLAW_TZ=Asia/Shanghai
```

### Windows 原生 OpenClaw

如果 Claw 是 Windows 原生安装，不要使用 `docker-compose.obsidian.yml`、
`deploy.sh` 或 `deploy.ps1`。使用
`openclaw.windows.obsidian.json5`，把其中的 `vault.path` 改成 Windows
本机的绝对路径，例如：

```text
D:/AI-自学OS/server/data/obsidian-vault/1
```

然后把 `plugins.entries.memory-wiki` 合并进原生 OpenClaw 的
`openclaw.json`。可以先备份配置，再让 Claw 执行配置检查；确认无误后才重启
Gateway。不要把容器内路径 `/home/node/.openclaw/wiki/main` 写进 Windows
原生配置。

把本目录的 `AGENTS.md` 复制到 vault 根目录：

```text
D:/AI-自学OS/server/data/obsidian-vault/1/AGENTS.md
```

原生 Windows OpenClaw 验证命令：

```powershell
openclaw wiki status
openclaw wiki compile
openclaw wiki lint
openclaw wiki search "AILearningOS"
```

如果 `openclaw wiki` 命令不可用，先确认 `memory-wiki` 已启用；不要为了修复
命令直接覆盖整个 `openclaw.json`。

这里的 `1` 是 AILearningOS 的 `userId`。如果部署多个用户，建议每个用户使用
独立的 OpenClaw 实例或独立的 vault，避免不同用户的邮件和对话互相可见。

### 2. 合并 OpenClaw 配置

把 `openclaw.obsidian.json5` 中的 `plugins.entries.memory-wiki` 对象合并到
OpenClaw 的 `openclaw.json`。不要直接覆盖整个配置文件，因为其中可能已有
Gateway、模型、渠道和权限配置。

容器内路径必须保持为：

```text
/home/node/.openclaw/wiki/main
```

配置模板使用 `vaultMode: "isolated"`，只处理挂载的 vault，不读取其他
OpenClaw agent 的私有 memory。`useOfficialCli` 保持为 `false`，服务器没有
安装 Obsidian 桌面 CLI 也不影响 Markdown、搜索和编译。

### 3. 启动并验证

```bash
docker compose \
  -f docker-compose.yml \
  -f /path/to/AI-自学OS/server/openclaw-obsidian/docker-compose.obsidian.yml \
  config --quiet

docker compose \
  -f docker-compose.yml \
  -f /path/to/AI-自学OS/server/openclaw-obsidian/docker-compose.obsidian.yml \
  up -d openclaw-gateway

docker compose \
  -f docker-compose.yml \
  -f /path/to/AI-自学OS/server/openclaw-obsidian/docker-compose.obsidian.yml \
  exec -T openclaw-gateway \
  sh -lc 'curl -fsS http://127.0.0.1:18789/healthz'
```

也可以直接使用同目录下的 `deploy.sh`：

```bash
OPENCLAW_DIR=/opt/openclaw \
AI_STUDY_PROJECT_DIR=/opt/ai-study-os \
OBSIDIAN_USER_ID=1 \
bash /opt/ai-study-os/server/openclaw-obsidian/deploy.sh
```

Windows Docker Desktop 服务器可以使用 PowerShell 版本：

```powershell
& 'C:\path\to\AI-自学OS\server\openclaw-obsidian\deploy.ps1' `
  -OpenClawDir 'C:\path\to\openclaw' `
  -ProjectDir 'C:\path\to\AI-自学OS' `
  -ObsidianUserId 1
```

### 4. 初始化 memory-wiki

首次部署后执行：

```bash
docker compose \
  -f docker-compose.yml \
  -f /path/to/AI-自学OS/server/openclaw-obsidian/docker-compose.obsidian.yml \
  run --rm openclaw-cli wiki init

docker compose \
  -f docker-compose.yml \
  -f /path/to/AI-自学OS/server/openclaw-obsidian/docker-compose.obsidian.yml \
  run --rm openclaw-cli wiki compile

docker compose \
  -f docker-compose.yml \
  -f /path/to/AI-自学OS/server/openclaw-obsidian/docker-compose.obsidian.yml \
  run --rm openclaw-cli wiki lint
```

以后 AILearningOS 每 15 分钟写入新笔记后，如果需要让编译索引立即更新，执行
`wiki compile`；原始 Markdown 本身不依赖编译也可以用 Obsidian 打开。

### 让 wiki search 检索 AILearningOS 的 Learning/录音笔记

`memory-wiki` 的 `wiki search` 默认检索它已经 ingest 并编译的 wiki 内容。
AILearningOS 原始笔记仍然保留在 `Learning/`、`captures/`、`Recording/` 等目录，
不会被移动或覆盖。要让它们也进入 OpenClaw 的 `sources` 检索层，使用同目录的
`sync-ai-study-vault.ps1`：

```powershell
Set-Location 'D:\AI-自学OS\server'
& 'D:\AI-自学OS\server\openclaw-obsidian\sync-ai-study-vault.ps1'
```

脚本会按 SHA-256 记录已经 ingest 的文件，只处理新增或内容有变化的 Markdown，
成功后自动执行一次 `openclaw wiki compile`。导入状态保存在：

```text
D:\AI-自学OS\server\data\openclaw-ai-study-ingest.json
```

它不放进 vault，也不会被 wiki 当作知识内容。

注册 Windows 每 15 分钟运行一次：

```powershell
$action = New-ScheduledTaskAction `
  -Execute 'PowerShell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "D:\AI-自学OS\server\openclaw-obsidian\sync-ai-study-vault.ps1"'
$trigger = New-ScheduledTaskTrigger `
  -Once `
  -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Minutes 15)
Register-ScheduledTask `
  -TaskName 'AILearningOS - OpenClaw Wiki Ingest' `
  -Action $action `
  -Trigger $trigger `
  -Description 'Ingest changed AILearningOS Markdown into OpenClaw memory-wiki.' `
  -Force
```

任务必须以和 OpenClaw 相同的 Windows 用户运行，并且该用户能执行 `openclaw`
命令。第一次运行后验证：

```powershell
openclaw wiki status
openclaw wiki compile
openclaw wiki lint
openclaw wiki search "AP Statistics"
openclaw wiki search "sample population variable"
```

如果你的 OpenClaw CLI 不在 `PATH`，手动传入完整路径：

```powershell
& 'D:\AI-自学OS\server\openclaw-obsidian\sync-ai-study-vault.ps1' `
  -OpenClawPath 'D:\path\to\openclaw.exe'
```

## AILearningOS 服务端的持久化

服务端 Docker 镜像现在以 `/app` 为工作目录，因此数据库和 vault 都在
`/app/data` 下。运行 AILearningOS 服务时请把宿主机的数据目录挂载到：

```yaml
services:
  ai-study-server:
    volumes:
      - /opt/ai-study-os/server/data:/app/data
```

OpenClaw 的 `AI_STUDY_OBSIDIAN_VAULT_HOST_PATH` 必须指向同一个宿主机目录下的
`server/data/obsidian-vault/{userId}`，不要指向 AILearningOS 容器内部的路径。

如果 OpenClaw 在另一台服务器上，AILearningOS 服务端也必须部署在同一台服务器，
或者把同一个数据目录通过可靠的网络盘挂载给两者。当前这台开发电脑上的
`C:\Users\GeorgeGao\Documents\ChatGPT\AI-自学OS\server\data` 不会自动同步到
远程 Claw 的 `D:\AI-自学OS\server\data`；Flutter 客户端只需要访问 AILearningOS
的 HTTPS API，不需要直接访问 vault 路径。

## 安全和权限

- vault 里有私人 ChatGPT 对话和邮件，不能公开映射到公网，也不要把它加入 Git。
- Linux 上官方 OpenClaw 容器默认使用非 root 的 `node` 用户（通常 uid 1000）。
  如果出现 `EACCES`，对目标用户 vault 授予 uid 1000 的读写权限：

  ```bash
  sudo chown -R 1000:1000 /opt/ai-study-os/server/data/obsidian-vault/1
  ```

- Gateway 对外暴露前应继续使用已有的认证、Cloudflare Tunnel 或防火墙策略；
  不要为了方便把 18789 端口裸露到公网。
- `.env`、`openclaw.json`、OAuth 凭据目录和 vault 内容都属于私密部署状态，
  只备份到受控位置。
