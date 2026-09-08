# AILearningOS

AILearningOS 是一个聚焦“待办 + 单词 + Learning Journal”的学习工具。Android 和 Windows 客户端保留主页、单词、学习笔记三个主入口，并从头像或侧栏进入 `Settings`。桌面端采用简洁的三栏信息流布局，移动端采用底部导航。

## 当前产品范围

### 主页

- `今日待办`：Canvas 未提交作业、截止时间、到期单词和今日 Learning Journal。
- `已完成`：Canvas 已提交/已评分作业、今日单词复习次数和 Journal 数量。
- 头像与桌面右栏：当前账号、所选 AI、Codex 剩余额度和 Canvas 状态。
- `Settings`：账号、Canvas、DeepSeek、ChatGPT-Codex、额度与自动回切。

### 单词

- `手动导入`：粘贴单词、词表或英文段落，完成提取、归一化和去重。
- `AI 导入`：粘贴课文、学习材料或 AI 对话，使用当前选中的 AI 提取单词、分析总结，并同时生成 Learning Journal。
- 保留搜索、详情、主动回忆和间隔复习数据。

### 学习笔记

- `新建 Journal`：预填充固定 Markdown 模板，由用户手动填写。
- `AI 分析`：提取学习目标、内容、概念、证据、行动项与候选单词，并保存成同一模板。
- 新建笔记统一使用 `# Learning Journal` 的八段式结构：基本信息、学习目标、内容记录、学习过程、反思与理解、成果输出、下一步计划、今日自评与自由记录。
- 升级前的旧笔记不删除，仍可在学习笔记列表中查看。

## AI 双路由

`Settings > AI 模型源` 是账号级开关，可在下列两条路线中选择一条：

1. `DeepSeek`：使用后端保存的 DeepSeek API Key 和模型。
2. `ChatGPT-Codex`：手机向 AILearningOS 后端发起官方设备码登录，由后端按 LearningOS 账号保存隔离登录态，并在服务器上调用 Codex 消耗该 ChatGPT 账号的 Codex 额度。

默认情况下，单词 AI 导入和 Learning Journal AI 分析只使用手动选中的路线。用户可显式开启“额度恢复后自动切回 Codex”：只有 Codex 返回额度/usage limit/429，且该用户已配置 DeepSeek 时，后端才临时走 DeepSeek；到官方 `resetsAt` 后，后端确认五小时窗口已有剩余额度再自动切回 Codex。登录、网络或模型错误不会触发切换。

这不是多账号号池：一个 LearningOS 用户只绑定自己的一个 ChatGPT-Codex 隔离登录态，不轮换其他人的账号或额度。

## Canvas 信息源

- Canvas 连接在 `Settings > 信息源` 管理，课程与作业由后端只读获取。
- 作业按 submission 状态进入主页待办或已完成；支持截止时间、逾期/缺交、迟交与得分状态。
- Canvas access token 只在后端按 LearningOS 账号加密保存，不写入客户端或仓库。

## Codex OSS 会话

- 后端使用[官方 Codex App Server 文档](https://learn.chatgpt.com/docs/app-server)中的 `thread/list` 与 `thread/turns/list` 读取历史，并显式包含 `appServer` 等来源，避免只依赖默认 `cli`/`vscode` 来源而漏会话。
- 仅处理工作目录最后一级名为 `OSS` 的会话；只同步用户与助手文本，排除 reasoning、命令和工具输出。
- 后端每两秒做增量检查并写入该 LearningOS 用户的会话收件箱与 Obsidian 原始记录。
- 源码和模拟协议测试已经通过；实际服务器仍需部署 v4.0 后，用真实已登录账号完成线上历史接口验收。

## 系统边界

```text
手机 / Windows App
        |
        | HTTPS
        v
AILearningOS 后端（部署在另一台服务器电脑）
        |
        +-- DeepSeek API
        |
        +-- 按账号隔离的 Codex / ChatGPT 登录态与额度

Claw = 独立的 AI 部署/更新机器人
```

- Codex 不在手机上运行；手机只调用后端提供的 Codex 能力。
- Claw 不是后端，不参与登录、AI 请求路由或额度消耗。它只能在被授权时协助更新服务器文件。
- Canvas 已作为主页待办信息源重新接入。邮件、飞书、课程、采集等旧界面仍不在当前精简客户端主流程中；后端旧接口和数据表暂时保留用于升级兼容。
- 客户端不再启动旧的邮件/对话自动采集定时器；AI 分析由用户手动触发。

## 运行与验证

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

客户端默认连接 `https://os.georgehan0514.top`。本地开发可覆盖：

```powershell
flutter run -d windows --dart-define=AI_STUDY_OS_API_URL=http://127.0.0.1:8080
flutter run -d emulator-5554 --dart-define=AI_STUDY_OS_API_URL=http://10.0.2.2:8080
```

启动服务端源码：

```powershell
cd server
dart pub get
dart run bin/server.dart
```

## 发布产物

- Android：`release/AILearningOS-android-v1.5.0.apk`
- Windows 后端：`release/AILearningOS-server-windows-x64-v4.0.zip`
- 后端源码：`release/AILearningOS-server-source-v4.0.zip`
- v4.0 部署与验收：[server/部署与验收-v4.0.md](server/部署与验收-v4.0.md)

Canvas 首页待办、OSS 来源修复和五小时额度自动回切需要同时更新 v1.5.0 客户端与另一台电脑上的 v4.0 后端。ChatGPT-Codex 设备码登录仍只由后端完成。

## 数据与安全

- 账号、单词、复习和笔记保存在服务端 SQLite，按 LearningOS 账号关联。
- ChatGPT 登录使用官方设备码/OAuth 流程，App 不接收 ChatGPT 密码，不要把 OAuth token 粘贴到 App 里。
- 生产部署必须使用 HTTPS，并在反向代理/WAF 上配置 IP、设备和账号限流。
- 更新客户端不会删除旧单词、笔记、DeepSeek Key 或 ChatGPT-Codex 登录态。
