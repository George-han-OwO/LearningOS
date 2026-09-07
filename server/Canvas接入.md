# Canvas LMS 接入

本功能由 AILearningOS 后端连接学校 Canvas API，Claw 只负责把发布包更新到另一台 Super-Sever。开发电脑上的测试不代表 Super-Sever 已部署。

## 使用范围

设置 → Canvas 课程：连接本人账号，读取在读课程及课程作业，显示截止时间（按手机本地时区）、提交状态、得分和满分。支持“加载更多”分页。不会提交作业、修改成绩或调用 AI；当前没有课程内容 AI 摘要和自动定时同步。

个人开发集成使用本人的 Canvas personal access token。令牌由用户在 App 中输入，经 HTTPS 传至 AILearningOS 后端。后端先通过 `GET /api/v1/users/self/profile` 验证，再加密保存学校域名、账号资料及令牌。数据库只保存密文，手机不持久化令牌；读取配置只返回连接状态、域名、账号资料、连接时间。

需要学校 Canvas 的完整 HTTPS 域名，例如 `https://school.instructure.com`。不要把 `/profile/settings` 等页面路径填进域名。默认接受 `*.instructure.com`，学校自定义域名由后端服务账号配置 `AILO_CANVAS_ALLOWED_HOSTS=canvas.school.edu`（多个用逗号分隔，只允许管理员添加可信 Canvas 域名）。不根据令牌前缀猜学校域名。Canvas 列表通过官方 Link header 分页；仅接受同源、同一 API 路径的下一页，禁用 HTTP 自动重定向，避免把凭据发送到其他站点。

令牌过期、撤销或权限不足时显示相应错误；验证失败不会覆盖现有连接。“断开连接”删除 AILearningOS 保存的连接，Canvas 上的令牌如需撤销，请在学校 Canvas 账号设置中操作。本实现不会猜测或伪造令牌的权限列表及到期时间。

## Super-Sever 升级

后端发布版本：`2026-09-06-canvas-readonly-v3.8`，数据库 schema 从 12 升级到 13，新增账号隔离的 `canvas_connections` 表。

1. 在 Super-Sever 确认当前运行的后端和 `\LearningOS` 计划任务，记录现有动作及服务账号；不要使用旧报告中的 PID 直接停进程。
2. 停止已确认的旧后端后，备份原有程序文件及完整数据库文件（包括存在的 WAL/SHM 文件），保留原 `data`、`AILO_SECRETS_MASTER_KEY`、飞书变量、代理和真实 Cloudflare 配置。
3. 替换 `bin/server.exe`、两个位置的 `sqlite3.dll`，复制新版 `start-server.ps1`。不要覆盖生产数据或用包里的 Cloudflare 模板替换真实配置。
4. 当前先启用 Canvas，而服务器还没有 Codex CLI 时，使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\AI-自学OS\server\start-server.ps1" -DataDirectory "D:\AI-自学OS\server\data" -Port 8080 -DisableCodex
```

`-DisableCodex` 明确关闭 Codex 网关，Canvas 和 DeepSeek 可以独立运行。计划任务需使用相同参数及已有服务账号。以后安装并验证 Codex CLI 后，去掉此参数即可恢复默认 Codex 网关启动。已正常运行 Codex 的服务器不要加此参数。

5. 验证 `/health` 为 OK；`/version` 应包含 `build=2026-09-06-canvas-readonly-v3.8` 与 `canvas=account-bound-readonly-courses-assignments-v1`。未登录请求 `/api/integrations/canvas/connection` 应返回 401。
6. 安装包含 Canvas 设置页的新 APK，在 App 登录已有 AILearningOS 账号后输入学校域名和令牌，点击“验证并连接”，确认本人资料、课程及作业。

Canvas 凭据加密复用现有 `AILO_SECRETS_MASTER_KEY`，无需新建主密钥。后端未配置主密钥时拒绝保存。恢复旧程序时注意 schema 已升级；如需恢复旧数据库，应使用停机备份，并明确会失去升级后新增的数据。

## API

所有接口都要求 AILearningOS `Authorization: Bearer <device-session>`，从设备会话确定用户，不接受客户端指定其他用户 ID。

- `GET /api/integrations/canvas/connection`：无令牌的连接状态。
- `PUT /api/integrations/canvas/connection`：JSON 包含 `base_url`、`token`；验证后加密保存。
- `DELETE /api/integrations/canvas/connection`：删除当前账号连接。
- `GET /api/integrations/canvas/courses`：`items`、`next_cursor`。
- `GET /api/integrations/canvas/courses/{courseId}/assignments`：`items`、`next_cursor`。

下一页传 `?cursor=<经过 URL 编码的 next_cursor>`。API 不返回 Canvas 原始响应中的无关资料，也不记录请求令牌或上游原始错误体。

官方资料：[Users](https://developerdocs.instructure.com/services/canvas/resources/users)、[Courses](https://developerdocs.instructure.com/services/canvas/resources/courses)、[Assignments](https://developerdocs.instructure.com/services/canvas/resources/assignments)、[Pagination](https://developerdocs.instructure.com/services/canvas/basics/file.pagination)。
