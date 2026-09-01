# 个人信息自动摘要与 Obsidian 知识库

## 一句话定义

个人信息自动摘要会定期读取 ChatGPT、Outlook 和 QQ 邮箱的授权快照，把内容总结成笔记，并自动分类写入服务器上的 Obsidian 知识管理体系。

## 核心规则

1. “自动安排生成笔记”开关默认关闭。关闭时不启动高频循环，而是在设备本地时间每天 23:00 统一检查并生成一次；用户打开开关后才启动 15 分钟循环。用户也可以在“笔记”页或“我的与设置”中立即检查一次。
2. ChatGPT Bridge 每次应至少提交最新的两条会话快照，并保留 `is_complete` 状态。
3. ChatGPT 按 `updated_at DESC` 排序后只取索引为 `1` 的会话，也就是“最新一条的上一条”。
4. ChatGPT 候选会话必须 `is_complete = true`；否则本轮只记录“等待完成”，不生成笔记。
5. Outlook 和 QQ 邮箱按邮件 ID 增量处理，只总结未处理且已完整接收的邮件。
6. 已经成功处理过的 `external_id` 不会再次生成重复笔记。
7. 总结成功后，笔记保存双语摘要、学习概念、待复习行动和原始内容证据；有价值的英文词会进入 Word Bank。
8. AI 同时输出一个知识分类和 1-5 个标签，服务器据此生成 Obsidian Markdown 文件和索引。

## 信息来源

| 来源 | 同步规则 | 接入方式 |
| --- | --- | --- |
| ChatGPT | 只处理最新会话的上一条，且必须已完成 | ChatGPT Web Bridge |
| Outlook | 增量处理未总结的完整邮件 | OAuth / Microsoft Graph Bridge |
| QQ 邮箱 | 增量处理未总结的完整邮件 | IMAP / QQ 邮箱 Bridge |

Outlook 和 QQ 邮箱不会把密码交给摘要应用。Outlook 应通过 OAuth 授权；QQ 邮箱应使用 IMAP 授权码或一个独立的本地 Bridge。摘要应用只接收规范化后的邮件快照。

## 为什么不直接读取 ChatGPT 历史

ChatGPT 登录态只能用于官方授权流程，应用不读取或保存 ChatGPT 密码、Cookie、access token 或 refresh token。当前架构因此把“读取 ChatGPT 会话”隔离为 Bridge：Bridge 负责把用户授权范围内的会话快照写入服务端收件箱，学习应用只负责选择、总结和归档。

ChatGPT Bridge 的写入接口：

```text
POST /api/conversation-sync/{userId}/inbox
```

请求体示例：

```json
{
  "conversations": [
    {
      "external_id": "chat-older",
      "title": "Older conversation",
      "transcript": "User: ...\nAssistant: ...",
      "updated_at": "2026-08-27T08:00:00.000Z",
      "is_complete": true
    },
    {
      "external_id": "chat-newest",
      "title": "Newest conversation",
      "transcript": "User: ...\nAssistant: ...",
      "updated_at": "2026-08-27T08:10:00.000Z",
      "is_complete": false
    }
  ]
}
```

收件箱只作为短期同步缓冲区；应用不会因为最新会话仍在生成而提前总结它。当前客户端在前台运行时启动 15 分钟定时器；移动端真正的后台定时执行还需要接入系统 WorkManager/后台任务能力。

邮箱 Bridge 的写入接口：

```text
POST /api/email-sync/{userId}/outlook/inbox
POST /api/email-sync/{userId}/qq/inbox
```

请求体示例：

```json
{
  "messages": [
    {
      "external_id": "outlook-message-id",
      "subject": "Project update",
      "sender": "sender@example.com",
      "recipients": "me@example.com",
      "body": "完整邮件正文",
      "received_at": "2026-08-27T08:30:00.000Z",
      "is_complete": true
    }
  ]
}
```

## Obsidian 归档规则

服务器会把每条 AI 摘要写入：

```text
server/data/obsidian-vault/{userId}/{category}/{title}-{source_id}.md
```

每个 Markdown 文件包含 YAML frontmatter：`title`、`category`、`source`、`source_id`、`updated`、`ai_generated` 和 `tags`。服务器同时维护 `00 Index.md`，将分类目录下的笔记链接起来。相同 `source_id` 重试时会覆盖同一文件，不会在 Obsidian 中生成重复文件。

## 界面表达

- “笔记”页顶部显示自动摘要状态、最近一次处理的 ChatGPT 会话和“立即检查”。
- “我的与设置”中的“自动安排生成笔记”开关只控制频率：打开是每 15 分钟循环，关闭是每天 23:00 日总结，并不等于关闭自动摘要。
- “我的与设置”中分别显示 Outlook 和 QQ 邮箱的摘要开关、授权方式和最近一次处理的邮件。
- 手动粘贴入口保留为“补录”能力，不改变自动同步的倒数第二条规则。
- 自动摘要成功后，服务器会按 AI 分类自动写入 Obsidian 知识库。
- 同步失败、缺少 AI、快照不足、候选未完成都会显示为可解释状态，而不是伪装成成功。

## 调度边界

- 15 分钟循环和 23:00 日总结由已登录的客户端调度；服务端负责收件箱、AI 摘要、数据库与 Obsidian 写入。
- 客户端启动或从后台恢复时，如果发现当天 23:00 已错过且尚未记录当天的日总结，会补执行一次，避免设备在 23:00 离线导致整晚丢失。
- 飞书录音 webhook 是事件触发链路，收到可用转写后即时生成，不等待 15 分钟或 23:00 调度。
- Outlook、QQ 的各自开关控制该邮箱是否纳入摘要；主开关关闭时，它们随 23:00 日总结处理，主开关打开时按 15 分钟循环处理。
