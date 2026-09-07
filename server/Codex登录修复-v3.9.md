# v3.9：ChatGPT 授权后一直 pending 的修复与部署

构建标识：`2026-09-07-codex-login-recovery-v3.9`。

## 边界与结论

开发机不是 Super-Sever。本文件及发布包只完成开发、测试和打包；必须在实际服务器升级并由用户完成一次设备码授权，才能确认线上修复。

手机 → AILearningOS HTTPS 后端 → 官方 Codex App Server。Claw 是独立的部署机器人，不承担后端接口、登录或 AI 请求。Windows 下这里使用 `codex app-server --stdio`，不是 Unix 专属的 `app-server daemon` 生命周期管理命令。

`auth.json` 出现说明 Codex 写过登录资料，但文件字段齐全不等同于凭据仍有效。不要把文件发给开发者、解析 token 来绕过官方确认，或按邮箱手工认领目录。新版使用官方 `account/read` 确认 ChatGPT 账号状态，再写数据库。

## 修复内容

1. `account/login/completed` 通知不再是完成登录的唯一条件。两秒后台检查和手机 complete 轮询都会触发 `account/read`。
2. 子进程已退出时，不复用“曾初始化”的失效客户端；在原隔离目录重新启动 Codex，确认已经持久化的登录态。尚未完成的授权不保证能跨子进程重启继续，必要时重新申请设备码。
3. 新增 SQLite schema 14 的 `codex_login_attempts`，持久化发起用户、隔离目录、状态、过期时间及一次性密钥的 SHA-256 哈希。不存 OAuth token 或原始一次性密钥。
4. 在同一个数据库事务中写入 `codex_user_homes` 和 completed 状态。新版本发起的请求，在后端重启后仍能恢复确认；手机仍须持有原 attempt id / secret 和原 LearningOS 会话。
5. complete 等待阶段立即返回 HTTP 202，不让 HTTP 请求等 Codex 的长轮询。完成响应在有效期内可重复获取；迟到的 cancel 不会销毁已绑定的客户端。
6. 已登录 LearningOS 的用户只绑定当前账号，不要求 Codex 返回可选的 accountId，也不会切换成按 ChatGPT 邮箱新建的账号。未登录 LearningOS 的独立 ChatGPT 登录仍要求稳定 accountId；缺失时会明确要求先注册/登录 LearningOS。
7. 连接 ChatGPT 不修改 AI 来源、DeepSeek Key、Canvas 连接或学习数据。`user_ai_settings.provider=deepseek` 是合法状态，不再作为登录失败的证据。用户在“AI 模型源”手动选择 DeepSeek 或 Codex。
8. 手机 v1.3.7 增加登录请求等待预算、complete 网络错误重试，并保留当前账号与来源。模型列表暂时加载失败不会取消已经成功的连接。

## 给 Super-Sever / Claw 的升级步骤

使用 `AILearningOS-server-windows-x64-v3.9.zip`，目标仍是 `D:\AI-自学OS\server`。对应可编译源码在 `AILearningOS-server-source-v3.9.zip`，不必索取任何 auth.json。

1. 先确认实际运行目录、当前服务 PID、`\LearningOS` 计划任务动作及运行账号。历史聊天里的 PID 已过时，不要照抄停止。
2. 暂停任务自动拉起，正常停止核实过的旧后端，确认端口已释放。停止后备份旧程序和 SQLite；若存在 SQLite WAL/SHM，应与数据库一起保留一致备份。保留原 `data`、原 `AILO_SECRETS_MASTER_KEY`、代理、Cloudflare 配置、任务运行账号。备份留在受保护的服务器目录，勿上传聊天或公网。
3. 将新包的 `bin\server.exe`、`bin\sqlite3.dll`、`lib\sqlite3.dll` 和根目录 `start-server.ps1` 覆盖到对应位置。本包不包含 `data` 和隧道配置，不要清空数据或改换主密钥。
4. 在实际运行后端的同一 Windows 账号下确认原生 Codex 可用。优先显式传入那台服务器实测的 `codex.exe` 绝对路径；不要传 `codex.ps1`，不要使用开发机 Codex 路径，也不必给 Claw 自己做 ChatGPT 登录。
5. 在服务器目录经脚本启动，例如：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\AI-自学OS\server\start-server.ps1" -DataDirectory "D:\AI-自学OS\server\data" -Port 8080 -CodexCommand "<服务器实际的 codex.exe 绝对路径>"
   ```

   脚本内容仅 ASCII，路径通过 `$PSScriptRoot` 和显式参数解析，避免 Windows PowerShell 5.1 误读脚本里的中文路径。本次需启用 Codex，**不要加 `-DisableCodex`**。将计划任务动作更新为此脚本，保留原运行账号和必要的环境变量，防止重启后退回直接执行 EXE。

6. 验证本机 `http://127.0.0.1:8080/health`、`/version`，再验证公网 `https://os.georgehan0514.top/version`。必须同时满足：

   ```json
   {
     "build": "2026-09-07-codex-login-recovery-v3.9",
     "codex_gateway_enabled": true,
     "codex_login_recovery": "account-read-durable-binding-idempotent-v1"
   }
   ```

7. 手机安装 v1.3.7，先登录原有 LearningOS 账号，在设置中重新发起一次 ChatGPT 设备码登录。不要继续使用旧版本未落库的 attempt。
8. 浏览器授权完成后确认：complete 从 202 变为 200、返回原 LearningOS user id、`auth.authenticated=true`，`GET /api/codex/account` 显示已连接。数据库应有该用户的 `codex_user_homes` 行和对应 completed attempt。检查状态时不要打印 session_token / attempt_secret / auth.json。
9. 保持 DeepSeek 时不应被自动切换；手动选择 Codex 后测试一条 AI Chat，再切回 DeepSeek。实际模型推理会使用所选来源的额度，此项由用户或经授权的管理员执行。随后重启后端，刷新账号和额度，确认绑定仍在。

仅 `/version` 正常不能证明 ChatGPT 授权或模型推理正常；必须区分服务启动、登录绑定和 AI 请求三层验收。

## 旧孤立目录与回滚

v3.7/v3.8 未落库的登录目录缺少可信的“发起账号 → 目录”关系，新版不会扫描 auth.json 并猜测归属。升级时保留目录，先使用新版重新登录；不要自行删除旧目录或手工插入绑定。

回滚需要一起恢复停止服务时备份的程序和 SQLite 数据库，因为 schema 已升级为 14。恢复旧数据库会丢失升级后新增数据，必须先评估和备份。不要仅覆盖旧 EXE 后强行打开新 schema。

## 源码构建

源码包根目录就是 Dart server 项目，含 `bin`、`lib`、`test`、锁定依赖和部署脚本；不含数据库、Codex 登录态、Canvas token、主密钥或客户端签名密钥。

```powershell
dart pub get
dart analyze
dart test
dart build cli -o build-v3.9
```

需 Dart SDK 3.12.2 或满足 pubspec 的版本。部署 `build-v3.9\bundle` 全部内容，另将 `lib\sqlite3.dll` 复制到 `bin\sqlite3.dll`，并带上本包启动脚本。不要用单独 `dart compile exe` 的结果替代带 Native Assets 的完整 bundle。

自动回归覆盖通知丢失、子进程退出、后端重启、重复/并发 complete、迟到取消、账号隔离、协议错误和 HTTP 202 → 200。测试使用模拟 Codex 和临时数据库，不能替代真实服务器授权验收。
