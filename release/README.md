# AILearningOS 发布包

## 当前版本

- Android：`AILearningOS-android-v1.3.7.apk`
- 应用显示名：`AILearningOS`
- Android 包名：`com.georgegao.ai_study_os`（为覆盖旧版安装而保留）
- 版本：`1.3.7`，versionCode `15`
- 大小：50,070,348 bytes（约 47.8 MiB）
- SHA-256：`95B90A697E5E6E1B205FE111CA6E3A5BE6B01B6A94B9A551DEE057E7ACD28B07`
- 已验证：APK v2 签名有效，并与 v1.3.0 使用相同签名，可直接覆盖升级
- 最新后端：`AILearningOS-server-windows-x64-v3.9.zip`
- 后端大小：5,800,796 bytes（约 5.5 MiB）
- 后端 SHA-256：`BF043E62E7973010133200D9285EB8FBCB9447D36032229431AC1785211BBB39`
- 后端源码：`AILearningOS-server-source-v3.9.zip`，118,627 bytes，SHA-256 `AC7B3C862EB16C85C88E8D9885F561FFACCBF41C1A6B320A1E4B6AFCC2EF06C5`
- ChatGPT 登录：v3.9 修复授权完成后一直 pending、子进程退出、后端重启和完成响应丢失；登录绑定当前 LearningOS 账号，但不自动改变所选 AI 来源
- Canvas：v3.9 后端保留账号验证、课程与作业只读 API；v1.3.7 APK 已包含 Canvas 设置页
- 双路由：词库补全、对话笔记、邮件/飞书摘要、每日课程计划和 AI Chat 全部使用账号当前手动选择的 DeepSeek V4 或 ChatGPT-Codex，失败时不自动回退

## 历史版本

- 历史文件：`AIStudyOS-android-v0.1.0.apk`（旧品牌名，不包含当前功能，请勿作为最新版安装）
- 大小：53,419,115 bytes（约 51.0 MiB）
- SHA-256：`30DDBEA65FDAB1E1ACE81A5647087912AB74B12F29BEA3641B23963725E584E1`
- 构建模式：Flutter Android Release

当前版本采用纯黑 Apple 风格与自定义 Liquid Glass 导航。手机不运行 Codex；Android 通过 AILearningOS HTTPS 后端使用当前选择的 AI 来源。DeepSeek API Key 只以服务器加密密文保存；ChatGPT 凭据由后端启动的 Codex App Server 管理，不会返回手机。Claw 是独立更新机器人，不参与 Codex 登录、凭据管理或 AI 请求。
