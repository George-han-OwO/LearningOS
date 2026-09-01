# AILearningOS · ChatGPT 自动笔记

一个面向 Android 与 Windows 的本地优先、双语 AI 辅助学习系统。产品核心是个人信息自动摘要：默认每天 23:00 统一生成一次；用户打开“自动安排生成笔记”开关后才改为每 15 分钟检查 ChatGPT、Outlook、QQ 邮箱，生成摘要并自动分类写入服务器 Obsidian 知识库。飞书录音转写按 webhook 事件即时处理；ChatGPT 仍只总结按更新时间排序后的倒数第二条、且已经生成完成的对话。主界面只保留今日 Note、Word Bank 和“用户名 Library”三个核心入口。界面使用 Flutter 的 Cupertino 组件和自定义 Apple 风格设计系统，不依赖 Material UI。

## 当前可用功能

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
- 输入关键信息，自动整理中英双语笔记。拥有新建笔记和 Markdown 导出
- 自动安排生成笔记：默认每天 23:00 统一检查；打开高频开关后才每 15 分钟检查 Bridge 收件箱。ChatGPT 只处理最新一条的上一条已完成对话；自动生成中英双语摘要、学习概念和待复习行动，并将可复习英文词自动加入 Word Bank
- 对话同步状态：记录上次检查、上次已处理会话、跳过未完成会话和错误原因，避免重复生成笔记
- Outlook / QQ 邮箱自动摘要：按邮件 ID 增量处理完整邮件，生成摘要、分类和标签
- 飞书录音豆接入：服务器提供录音完成事件/转写文本入口，调用 DeepSeek 生成摘要、学习要点和词汇，并写入今日 Note、Word Bank 与 Obsidian，见 [`server/飞书录音豆接入.md`](server/飞书录音豆接入.md)
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

## 尚未接入

- 图片 OCR、错题自动切分与书页摘要
- ChatGPT Web Bridge 的具体浏览器采集端（服务端收件箱接口已经提供）
- Outlook OAuth / Microsoft Graph Bridge 和 QQ IMAP / 授权码 Bridge 的具体采集端（服务端邮箱收件箱接口已经提供）
- Android 进程被系统挂起时的真正后台 15 分钟/23:00 定时任务（当前由客户端进程调度；需要接入系统 WorkManager/后台任务能力才能保证进程被系统挂起时仍执行）
- 跨设备同步

图片 OCR 仍未接入。Windows 端的 ChatGPT 登录已经接入官方 Codex App Server 浏览器授权流程；App 只拿到账号元数据，绝不读取或保存 ChatGPT 密码/token。Android 端需要部署受信任的 Codex 网关后才能使用订阅额度，不能在 APK 内伪造或抓取 ChatGPT 登录态。自动摘要的 ChatGPT/邮箱读取采用 Bridge 收件箱设计，自动分类结果写入服务器 Obsidian，详见 [产品定义-ChatGPT自动笔记.md](产品定义-ChatGPT自动笔记.md)。Claw 与 Obsidian 的服务器部署步骤详见 [server/openclaw-obsidian/README.md](server/openclaw-obsidian/README.md)。

## 运行与验证

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

客户端服务地址默认是 `https://os.georgehan0514.top`，本地开发可覆盖：

```powershell
flutter run -d windows --dart-define=AI_STUDY_OS_API_URL=http://127.0.0.1:8080
flutter run -d emulator-5554 --dart-define=AI_STUDY_OS_API_URL=http://10.0.2.2:8080
```

启动服务端：

```powershell
cd server
dart pub get
dart run bin/server.dart
```

Android Release APK：

`release/AILearningOS-android-v1.3.1.apk`

SHA-256：

`51FAED087E5945FD24F1C4B4CDDFE59F0FDADAD066524C1C32A05336579CE233`

大小：

`49,201,236` bytes（约 `46.9` MiB）

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
