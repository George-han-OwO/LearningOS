# AILearningOS server

这是 AILearningOS 的服务端，负责 DeepSeek 请求、词库、学习笔记、飞书录音回调，以及 Obsidian vault 写入。

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

## 旧数据库迁移

旧版数据库如果有 `deepseek_api_key` 明文项，启动新版服务器时会在主密钥就绪的前提下自动加密旧 Key、写入 `deepseek_api_key_encrypted_v1` 和脱敏提示、删除旧明文项，然后启动后台词条补全 Worker。

如果数据库已有加密 Key 但没有设置主密钥，服务器会拒绝启动；先配置同一枚主密钥再启动即可。启动前建议备份 `data/ai_study_os.sqlite3`，但不要把备份上传到 Git 或公网。

## 待翻译词条自动队列

导入时无法获得 AI 补全的词会保留 `待 AI 翻译`、`待生成`、`待识别` 等占位内容。服务端 Worker 每 30 秒扫描一次，每位用户每轮最多处理 20 个词：

- 没有 Key：不请求 DeepSeek，保持等待状态；
- Key 无效或网络失败：保留占位内容，30 秒后重试；
- Key 恢复并请求成功：自动更新翻译、音标、词性和中英例句；
- 手机 App 关闭也不影响服务器 Worker；App 打开时会同步展示队列状态。

App 调用 `POST /api/words/{userId}/enrich-pending` 时使用后台模式，接口会快速返回；真正的 DeepSeek 请求由服务器完成。外网访问必须使用 HTTPS。

## 数据目录

默认数据目录是当前服务器目录下的 `data/`。如需指定目录，可以设置 `AILO_DATA_DIRECTORY`。生产环境不要更换已有数据库目录，避免词库、笔记和 vault 指向不同数据集。

## 构建与验证

```powershell
dart pub get
dart analyze
dart test
dart compile exe bin/server.dart -o release\server.exe
```

新版 `GET /version` 应包含 `2026-09-01-word-pos-parser-v3.1`。
