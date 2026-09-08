# AILearningOS 发布包

## 当前版本

- Android：`AILearningOS-android-v1.5.1.apk`
- 应用显示名：`AILearningOS`
- Android 包名：`com.georgegao.ai_study_os`（为覆盖旧版安装而保留）
- 版本：`1.5.1`，versionCode `18`
- 构建产物及 SHA-256：由 `v1.5.1` GitHub Release 的 `SHA256SUMS.txt` 给出
- 最新后端：`AILearningOS-server-windows-x64-v4.0.zip`
- 后端源码：`AILearningOS-server-source-v4.0.zip`
- ChatGPT 登录：保留 v3.9 的 durable binding 与恢复机制；每个 LearningOS 用户仍只有自己的隔离 Codex 登录态
- Canvas：课程作业成为主页待办信息源，并按提交状态分到“今日待办”与“已完成”
- AI 路由：默认手动选择；用户显式开启后，Codex 额度用尽才临时走 DeepSeek，并在官方五小时窗口恢复后由后端自动切回
- Codex OSS：显式包含 `appServer` 等会话来源，只同步用户与助手文本，不保存 reasoning、命令或工具输出

## 历史版本

- 历史文件：`AIStudyOS-android-v0.1.0.apk`（旧品牌名，不包含当前功能，请勿作为最新版安装）
- 大小：53,419,115 bytes（约 51.0 MiB）
- SHA-256：`30DDBEA65FDAB1E1ACE81A5647087912AB74B12F29BEA3641B23963725E584E1`
- 构建模式：Flutter Android Release

当前版本采用纯黑 Apple 风格与自定义 Liquid Glass 导航。手机不运行 Codex；Android 通过 AILearningOS HTTPS 后端使用当前选择的 AI 来源。DeepSeek API Key 只以服务器加密密文保存；ChatGPT 凭据由后端启动的 Codex App Server 管理，不会返回手机。Claw 是独立更新机器人，不参与 Codex 登录、凭据管理或 AI 请求。
