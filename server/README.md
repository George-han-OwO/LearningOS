# AILearningOS server

这是 AILearningOS 的服务端，负责账号隔离的 Codex/DeepSeek AI 请求、词库、学习笔记、飞书录音回调，以及 Obsidian vault 写入。

v4.3 新增 PA Evidence Pack 能力声明和学习记录强制账号隔离：客户端把 Journal、飞书录音和 Canvas 作业汇入可搜索证据包，服务端拒绝匿名或跨账号读写学习记录。v4.2 的飞书录音每日归档、账号隔离 Codex 登录防抖、Canvas 首页待办、Codex OSS 会话来源读取和五小时额度自动回切全部保留。部署与验收见 [部署与验收-v4.3.md](部署与验收-v4.3.md)。

v3.8 新增 Canvas LMS 本人账号的只读连接、在读课程和作业 API，令牌按账号加密保存。部署、接口与限制见 [Canvas接入.md](Canvas接入.md)。Canvas 不依赖 Codex CLI；先使用 Canvas 的服务器可通过 `start-server.ps1 -DisableCodex` 启动。

## 安全要求

DeepSeek API Key 不会返回给 App，也不会以明文写入 SQLite。服务器使用 AES-256-GCM 加密，数据库只保存密文；加密主密钥必须放在服务器进程环境变量 `AILO_SECRETS_MASTER_KEY` 中。

主密钥必须是 32 字节的 base64/base64url，或 64 个十六进制字符。生成一枚新主密钥：

```powershell
.\server.exe --generate-master-key
```

把输出保存到服务器的环境变量或受保护的服务管理器配置中。不要把主密钥、DeepSeek API Key 放进聊天、App、Git、公开隧道配置或日志。

```powershell
$env:AILO_SECRETS_MASTER_KEY = '<这里填刚生成的主密钥>'
$env:PORT = '8080'
.\server.exe
```

长期运行时请把变量配置到实际启动 AILearningOS 的计划任务、服务或启动脚本中，而不是只在当前终端临时设置。

## 手机 ChatGPT / Codex 网关

设置 `AILO_CODEX_GATEWAY_ENABLED=1` 后，Android/iOS 会使用 HTTPS 设备码流程登录 ChatGPT；服务器在每个 AILearningOS 账号独立的 `data/codex-users/<匿名目录>` 中启动官方 `codex app-server`。手机不会运行 Codex，也不会接触 ChatGPT token。

这里的“服务器”指实际运行 `server.exe` 的 AILearningOS 后端主机。Codex 登录、账号隔离、请求路由和额度消耗全部由该后端负责，不依赖 Claw。Claw 是另一个独立的更新机器人；即使没有运行 Claw，正确配置的 AILearningOS 后端也必须能够独立提供 Codex 功能。

```powershell
codex --version
.\start-server.ps1 -DataDirectory 'C:\AI_OS_Server\data' -Port 8080
```

`codex --version` 必须在**实际启动 server.exe 的同一个 Windows 服务账号**下成功。Windows 发布包应使用根目录的 `start-server.ps1` 启动；它会设置网关开关、数据目录和 Codex 绝对路径，防止计划任务重启后丢失临时环境变量。不要公开 App Server WebSocket 或它的标准输入输出协议；只将现有 HTTPS API 通过 Cloudflare Tunnel 暴露。`data/codex-users` 可能包含 Codex 受管的登录态，必须限制为该服务账号可读写，禁止加入 Git、静态目录、日志或普通云备份。

如果 Codex CLI 通过 npm 全局安装，Windows 通常会同时生成 `codex.ps1` 和 `codex.cmd`；发布包的启动脚本会优先选择 `codex.exe` 或 `codex.cmd`，避免计划任务把 PowerShell shim 当成后端子进程。部署机器人或管理员不应预先运行全局 `codex login`，手机设备码登录会由后端按 AILearningOS 账号分别完成。

同一用户在已有未完成流程时再次请求设备码，会触发登录防抖：服务器通过官方 `account/login/cancel` 取消该用户近期未完成流程，返回 HTTP `429`，并要求连续 5 秒无新请求后再创建。静默期内再次请求会重新计时；状态保存在 SQLite schema 16 中并可跨服务重启恢复。该规则按 LearningOS 用户隔离，匿名登录按客户端安全存储的随机安装标识隔离，不会退出已完成登录或影响其他用户。

网关启用后，服务端保持每个已登录账号的 App Server 连接，每 2 秒增量检查工作目录名为 `OSS` 的线程。只保存用户消息与助手正文，排除推理、命令、工具输出与文件差异；原始对话幂等写入 `data/obsidian-vault/<userId>/Codex Raw`。

服务器数据库只保存每台 App 设备会话的 SHA-256 哈希，不保存原始 Bearer token。旧的服务器全局 `app_session` 只可用作显式迁移兼容，生产环境不要设置 `AILO_ALLOW_LEGACY_SESSION=1`。

## 旧数据库迁移

旧版数据库如果有 `deepseek_api_key` 明文项，启动新版服务器时会在主密钥就绪的前提下自动加密旧 Key、写入 `deepseek_api_key_encrypted_v1` 和脱敏提示、删除旧明文项，然后启动后台词条补全 Worker。

如果数据库已有加密 Key 但没有设置主密钥，服务器会拒绝启动；先配置同一枚主密钥再启动即可。启动前建议备份 `data/ai_study_os.sqlite3`，但不要把备份上传到 Git 或公网。

## 待翻译词条自动队列

导入时无法获得 AI 补全的词会保留 `待 AI 翻译`、`待生成`、`待识别` 等占位内容。服务端 Worker 每 30 秒扫描一次，每位用户每轮最多处理 20 个词：

- Codex 模式：使用该账号服务器端的 ChatGPT/Codex 登录态与额度；
- DeepSeek 模式没有 Key：不发起请求，保持等待状态；
- Key 无效或网络失败：保留占位内容，30 秒后重试；
- Key 恢复并请求成功：自动更新翻译、音标、词性和中英例句；
- 手机 App 关闭也不影响服务器 Worker；App 打开时会同步展示队列状态。

App 调用 `POST /api/words/{userId}/enrich-pending` 时使用后台模式，接口会快速返回；真正的 Codex 或 DeepSeek 请求由服务器完成。外网访问必须使用 HTTPS。

## 数据目录

默认数据目录是当前服务器目录下的 `data/`。如需指定目录，可以设置 `AILO_DATA_DIRECTORY`。生产环境不要更换已有数据库目录，避免词库、笔记和 vault 指向不同数据集。

## 构建与验证

```powershell
dart pub get
dart analyze
dart test
dart build cli -o release
```

必须整体部署 `dart build cli` 生成的 `bundle`，其中包含 `bin/server.exe` 和 Native Assets 生成的 `lib/sqlite3.dll`。正式发布包还在 `bin` 中保留一份 SQLite DLL，使独立 EXE 在不同 Windows 服务启动目录下也能稳定加载。

新版 `GET /version` 应包含 `mobile_codex_login`。
