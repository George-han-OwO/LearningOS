# AILearningOS

AILearningOS 是一个聚焦“单词 + Learning Journal”的学习工具。Android 和 Windows 客户端只保留三个主界面：主页、单词、学习笔记；`Settings` 从主页底部进入。

## 当前产品范围

### 主页

- `今日待办`：到期单词和今日 Learning Journal。
- `已完成`：今日单词复习次数和今日 Learning Journal 数量。
- `Settings`：账号、DeepSeek 和 ChatGPT-Codex 连接与切换。

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

`Settings > AI 模型源` 是账号级的手动开关，可在下列两条路线中选择一条：

1. `DeepSeek`：使用后端保存的 DeepSeek API Key 和模型。
2. `ChatGPT-Codex`：手机向 AILearningOS 后端发起官方设备码登录，由后端按 LearningOS 账号保存隔离登录态，并在服务器上调用 Codex 消耗该 ChatGPT 账号的 Codex 额度。

单词 AI 导入和 Learning Journal AI 分析只使用当前手动选中的路线。登录失效、Key 无效、模型不可用或额度耗尽时会明确报错，不会暗中切到另一条路线。

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
- Canvas、邮件、飞书、课程、采集、自动对话同步和 Obsidian 等旧界面已从当前客户端功能范围移除。后端的旧接口和数据表暂时保留，用于升级兼容，不等于当前 App 仍会启动这些功能。
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

- Android 精简版：`release/AILearningOS-android-v1.4.0.apk`（SHA-256 `7DCB5A49E3D031E495D4E689E2F0092AB0C9BEE6AFF71878C4361A1A682B9281`，48,380,040 bytes）
- Windows 后端：`release/AILearningOS-server-windows-x64-v3.9.zip`
- 后端源码：`release/AILearningOS-server-source-v3.9.zip`
- v3.9 登录修复部署与验收：[server/Codex登录修复-v3.9.md](server/Codex登录修复-v3.9.md)

客户端界面精简不需要更换 v3.9 后端；ChatGPT-Codex 设备码登录仍由部署在另一台电脑上的 AILearningOS 后端完成。

## 数据与安全

- 账号、单词、复习和笔记保存在服务端 SQLite，按 LearningOS 账号关联。
- ChatGPT 登录使用官方设备码/OAuth 流程，App 不接收 ChatGPT 密码，不要把 OAuth token 粘贴到 App 里。
- 生产部署必须使用 HTTPS，并在反向代理/WAF 上配置 IP、设备和账号限流。
- 更新客户端不会删除旧单词、笔记、DeepSeek Key 或 ChatGPT-Codex 登录态。
