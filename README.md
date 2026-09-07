# AILearningOS · ChatGPT 自动笔记

一个面向 Android 与 Windows 的双语 AI 辅助学习系统。手机通过实际部署的 AILearningOS 后端完成 ChatGPT 设备码登录；后端为每个账号启动隔离的官方 Codex App Server，并从 `model/list` 自动选择该账号当前可用的模型。后端每 2 秒增量读取 `OSS` 工作区对话并幂等归档到账号隔离的 Obsidian Vault，手机退到后台也不依赖客户端定时器。笔记、词库、对话、邮件、飞书摘要和课程计划在 Codex 模式下均通过后端消耗该账号的 Codex 额度，失败时不会静默回退到 DeepSeek。Claw 是另一个独立的服务器更新机器人；AILearningOS 后端和 Codex 接入均不依赖 Claw。

## 当前可用功能

- Canvas LMS 个人账号接入（需部署 v3.9 后端和 v1.3.7 客户端）：验证账号、读取在读课程、作业、截止时间和提交状态；令牌按用户在后端加密保存，详见 [Canvas 接入](server/Canvas接入.md)。
- 服务端账号注册、密码登录与会话恢复（客户端通过 HTTPS API 调用）
- PBKDF2-HMAC-SHA256 加盐密码哈希，不保存明文密码
- 服务端 SQLite 数据库；账号、词库、复习、打卡、笔记与采集记录彼此关联
- 艾宾浩斯思路的间隔重复（Spaced Repetition）与主动回忆（Active Recall）
- 按“忘记了 / 较困难 / 记住了 / 很简单”动态安排下次复习
- 每日复习概览、学习分钟数和本地打卡
- 相机、相册及本地文件采集；原文件复制进应用本地资料库
- Word Bank 英文提取、大小写归一、去重、搜索和表格/卡片视图
- 内置基础词典的中文释义、音标与双语例句；未知词保留“待 AI 翻译”状态
- DeepSeek 联网补全：可在本机填写 API Key 后，用 `DeepSeek-V4-flash` 为词库补齐音标、词性、释义与双语例句
- ChatGPT Codex 订阅额度：通过官方 `account/rateLimits/read` 读取短周期/长周期已用比例、剩余比例和重置时间；设置页每分钟刷新，也可手动刷新。手机使用服务器隔离目录，Windows 使用本机目录
- Codex OSS 会话实时读取：AILearningOS 后端通过官方 `thread/list` 与 `thread/turns/list` 每 2 秒增量检查；只同步用户消息和助手正文，不采集推理、命令、工具输出或文件变更
- 输入关键信息，自动整理中英双语笔记。拥有新建笔记和 Markdown 导出
- 自动安排生成笔记：默认每天 23:00 统一检查；打开高频开关后才每 15 分钟检查同步收件箱。Codex 只处理最新一条的上一条已完成对话；自动生成中英双语摘要、学习概念和待复习行动，并将可复习英文词自动加入 Word Bank
- 对话同步状态：记录上次检查、上次已处理会话、跳过未完成会话和错误原因，避免重复生成笔记
- Outlook / QQ 邮箱自动摘要：按邮件 ID 增量处理完整邮件，生成摘要、分类和标签
- 飞书录音豆接入：服务器提供录音完成事件/转写文本入口，调用当前全局选择的 DeepSeek V4 或 ChatGPT-Codex 生成摘要、学习要点和词汇，并写入今日 Note、Word Bank 与 Obsidian，见 [`server/飞书录音豆接入.md`](server/飞书录音豆接入.md)
- 服务器 Obsidian 归档：每条自动摘要按知识分类写入 `server/data/obsidian-vault/{userId}/{category}`，并维护 `00 Index.md`
- Obsidian 知识管理：导出带 YAML frontmatter、证据类型、AI 标记、标签和 `[[wikilink]]` 的 Vault，保留原始对话与摘要的关系
- OpenClaw / Claw 部署包：将服务器 Vault 挂载给 Claw 的 Gateway 与 CLI，并接入 `memory-wiki` 检索和编译，见 [`server/openclaw-obsidian/README.md`](server/openclaw-obsidian/README.md)
- 18 个月 AI 课程：从 AP 统计和微积分补基础开始，用章节打卡、选择题测试、错题归因和人生信息库个性化布置，最终学习 DeepSeek-V4-Pro 并手搓小型语言模型，见 [`课程/README.md`](课程/README.md)
- 登录防爆破：失败计数持久化、第 3 次起指数退避、最长锁定 15 分钟
- 服务端防爆破：失败计数持久化，第 3 次起指数退避，最长锁定 15 分钟；生产环境仍应在反向代理/WAF 上做 IP、设备和账号限流
- DDoS 上线方案清单：CDN/Anycast、WAF、API Gateway、IP/账号/设备限流、熔断与告警
- 精简响应式布局：Windows 侧边栏与 Android 底部标签栏只保留今日 Note、Word Bank 和 Library，设置从今日页进入
- 固定纯黑深色外观，使用白色文字、克制的系统蓝强调色与高对比分隔线
- Liquid Glass 视觉层：动态模糊、半透明渐变、高光边缘与悬浮阴影
- 玻璃仅用于导航、主要控件和瞬态弹窗；正文内容仍使用稳定的深色表面，避免影响阅读层级
- 危险操作采用半透明红色液态玻璃提示框，图标、标题、正文和操作文字均使用白色

## AI 双路由

设置页的“AI 模型源”是账号级全局开关。当前已经接入 AI 的功能——词库补全、手动对话分析、Codex 对话自动笔记、Outlook/QQ 邮件摘要、飞书录音摘要、每日课程计划和 AI Chat——全部只使用当前手动选择的一条路径：`DeepSeek V4` 或 `ChatGPT-Codex`。任一路径登录失效、Key 无效、模型不可用或额度耗尽时都会明确报错，不会偷偷切换到另一条路径。图片 OCR 尚未实现，因此不列入双路由能力。

## 尚未接入

- 图片 OCR、错题自动切分与书页摘要
- ChatGPT 网页版普通聊天的浏览器采集端（Codex 的 `OSS` 项目会话已经接入；这不等同于读取 chatgpt.com 的全部网页聊天）
- Outlook OAuth / Microsoft Graph Bridge 和 QQ IMAP / 授权码 Bridge 的具体采集端（服务端邮箱收件箱接口已经提供）
- Android 进程被系统挂起时的 15 分钟/23:00 **AI 摘要调度**仍由客户端调度；但 OSS 原始对话的 Obsidian 增量归档已由 AILearningOS 后端常驻执行
- 跨设备同步

图片 OCR 仍未接入。Windows 端的 ChatGPT 登录、Codex 额度与本机 Codex 会话历史均通过官方 Codex App Server 完成；Android 通过 AILearningOS 后端内的隔离 App Server 使用同一官方设备码流程。App 只拿账号元数据、额度窗口和经过过滤的用户/助手消息，绝不读取或保存 ChatGPT 密码/token。自动分类结果写入服务器 Obsidian，详见 [产品定义-ChatGPT自动笔记.md](产品定义-ChatGPT自动笔记.md)。独立的 Claw 更新/知识库工具说明见 [server/openclaw-obsidian/README.md](server/openclaw-obsidian/README.md)，它不参与 Codex 登录和 AI 请求。

## 运行与验证

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
dart run tool/verify_codex_bridge.dart
```

客户端服务地址默认是 `https://os.georgehan0514.top`，本地开发可覆盖：

```powershell
flutter run -d windows --dart-define=AI_STUDY_OS_API_URL=http://127.0.0.1:8080
flutter run -d emulator-5554 --dart-define=AI_STUDY_OS_API_URL=http://10.0.2.2:8080
```

Codex 会话默认匹配工作目录名为 `OSS` 的线程。如果有多个同名目录，建议在 Windows 启动时固定完整路径：

```powershell
flutter run -d windows --dart-define="AI_STUDY_OS_CODEX_SYNC_CWD=C:\Users\GeorgeGao\Documents\ChatGPT\OSS"
```

`tool/verify_codex_bridge.dart` 只输出安全的连接状态、额度剩余比例和可读线程数量，不输出账号凭据或聊天正文。

启动服务端：

```powershell
cd server
dart pub get
dart run bin/server.dart
```

Android Release APK：

`release/AILearningOS-android-v1.3.7.apk`

SHA-256：

`95B90A697E5E6E1B205FE111CA6E3A5BE6B01B6A94B9A551DEE057E7ACD28B07`

大小：

`50,070,348` bytes（约 `47.8` MiB）

Windows 后端部署包（可由管理员手工升级，也可由独立的 Claw 更新机器人执行文件更新）：

`release/AILearningOS-server-windows-x64-v3.9.zip`

SHA-256：

`BF043E62E7973010133200D9285EB8FBCB9447D36032229431AC1785211BBB39`

大小：

`5,800,796` bytes（约 `5.5` MiB）

后端源码包为 `release/AILearningOS-server-source-v3.9.zip`，SHA-256 `AC7B3C862EB16C85C88E8D9885F561FFACCBF41C1A6B320A1E4B6AFCC2EF06C5`，大小 118,627 bytes。v3.9 修复 ChatGPT 授权后一直 pending，并保留当前 LearningOS 账号、数据、DeepSeek Key 与手动选择的 AI 来源；部署和线上验收见 [v3.9 登录修复指南](server/Codex登录修复-v3.9.md)。v1.3.7 APK 已包含 Canvas 设置页；Canvas 账号实测仍需要学校域名。

## Windows 构建环境

Windows 工程代码已经生成。当前电脑的 Visual Studio 2022 还需通过 Visual Studio Installer 安装 **Desktop development with C++**，并包含：

- MSVC v142 - VS 2019 C++ x64/x86 build tools（Flutter Doctor 当前要求）
- C++ CMake tools for Windows
- Windows 10 SDK

安装后运行：

```powershell
flutter build windows --release
```

Windows 目标程序名为 `AILearningOS.exe`。

## 数据位置

当前客户端的数据源是服务端 API，服务端默认在工作目录的 `server/data/ai_study_os.sqlite3` 创建 SQLite 数据库。客户端的 `databasePath` 显示为 API 地址；笔记导出和拍照文件仍由客户端按平台保存。请为公网部署配置 HTTPS、WAF/CDN 和限流，不要直接暴露 Dart 进程端口。
