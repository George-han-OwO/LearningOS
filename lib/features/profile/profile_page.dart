import 'package:flutter/cupertino.dart';

import '../../core/app_controller.dart';
import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';
import '../auth/chatgpt_login_dialog.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.onOpenSafety, super.key});

  final VoidCallback onOpenSafety;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.currentUser!;
    return AppPage(
      title: '我的与设置',
      subtitle: '账号、安全、数据与 AI 连接',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final account = Column(
            children: [
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppPalette.resolve(context, AppPalette.blue),
                            AppPalette.resolve(context, AppPalette.purple),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        user.displayName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.displayName, style: AppTextStyles.title),
                          const SizedBox(height: 4),
                          Text(
                            user.email,
                            style: AppTextStyles.body.copyWith(
                              color: AppPalette.resolve(
                                context,
                                AppPalette.secondaryText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _StatusPill(
                            label: user.isExternal
                                ? 'ChatGPT · ${controller.chatGptAuth.planLabel}'
                                : '本地账号',
                            color: user.isExternal
                                ? AppPalette.purple
                                : AppPalette.green,
                            background: user.isExternal
                                ? AppPalette.purpleSoft
                                : AppPalette.greenSoft,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppGroup(
                title: '学习数据',
                children: [
                  AppGroupRow(
                    icon: CupertinoIcons.book_fill,
                    title: '${controller.words.length} 个单词',
                    subtitle: '${controller.dueWords.length} 个当前待复习',
                  ),
                  AppGroupRow(
                    icon: CupertinoIcons.doc_text_fill,
                    title: '${controller.notes.length} 篇双语笔记',
                    subtitle: '${controller.captures.length} 份采集资料',
                    tint: AppPalette.green,
                    tintBackground: AppPalette.greenSoft,
                  ),
                ],
              ),
            ],
          );

          final settings = Column(
            children: [
              AppGroup(
                title: '服务与安全',
                children: [
                  AppGroupRow(
                    icon: CupertinoIcons.chat_bubble_2_fill,
                    title: 'ChatGPT 登录',
                    subtitle: controller.chatGptAuth.authenticated
                        ? '已登录 · chatgpt5.5 · 词库补全优先走 Codex 额度'
                        : controller.chatGptAuth.available
                        ? '未登录 · 通过官方浏览器流程连接 chatgpt5.5'
                        : '当前设备不可用 · Windows 需安装 Codex，Android 需受信任网关',
                    tint: controller.chatGptAuth.authenticated
                        ? AppPalette.green
                        : AppPalette.purple,
                    tintBackground: controller.chatGptAuth.authenticated
                        ? AppPalette.greenSoft
                        : AppPalette.softSurface,
                    trailing: _StatusPill(
                      label: controller.chatGptAuth.authenticated
                          ? '已登录'
                          : controller.chatGptAuth.available
                          ? '待登录'
                          : '不可用',
                      color: controller.chatGptAuth.authenticated
                          ? AppPalette.green
                          : AppPalette.orange,
                      background: controller.chatGptAuth.authenticated
                          ? AppPalette.greenSoft
                          : AppPalette.orangeSoft,
                    ),
                    onTap: () => _showChatGptConnectionSheet(context),
                  ),
                  AppGroupRow(
                    icon: CupertinoIcons.sparkles,
                    title: 'DeepSeek API',
                    subtitle: controller.deepSeekReady
                        ? '服务器已加密保存 · ${controller.aiSettings.model} · 后台自动补全'
                        : controller.aiSettings.serverEncryptionReady
                        ? '未连接 · 填写 DeepSeek API Key 后自动处理队列'
                        : '服务器密钥保险库尚未配置',
                    tint: controller.deepSeekReady
                        ? AppPalette.green
                        : AppPalette.blue,
                    tintBackground: controller.deepSeekReady
                        ? AppPalette.greenSoft
                        : AppPalette.softSurface,
                    trailing: _StatusPill(
                      label: controller.deepSeekReady ? '已开启' : '备用',
                      color: controller.deepSeekReady
                          ? AppPalette.green
                          : AppPalette.blue,
                      background: controller.deepSeekReady
                          ? AppPalette.greenSoft
                          : AppPalette.blueSoft,
                    ),
                    onTap: () => _showAiConnectionSheet(context),
                  ),
                  AppGroupRow(
                    icon: CupertinoIcons.cloud,
                    title: '自动安排生成笔记',
                    subtitle: controller.conversationSyncState.enabled
                        ? '高频模式 · 每 15 分钟检查 ChatGPT 倒数第二条已完成对话'
                        : '高频模式未开启 · 每天 23:00 统一生成摘要',
                    tint: controller.conversationSyncState.enabled
                        ? AppPalette.green
                        : AppPalette.secondaryText,
                    tintBackground: controller.conversationSyncState.enabled
                        ? AppPalette.greenSoft
                        : AppPalette.softSurface,
                    trailing: CupertinoSwitch(
                      value: controller.conversationSyncState.enabled,
                      onChanged: controller.busy
                          ? null
                          : (value) async {
                              final error = await controller
                                  .setConversationSyncEnabled(value);
                              if (!context.mounted || error == null) return;
                              await showAppMessage(
                                context,
                                title: '同步设置失败',
                                message: error,
                                tone: AppMessageTone.warning,
                              );
                            },
                    ),
                  ),
                  AppGroupRow(
                    icon: CupertinoIcons.arrow_2_circlepath,
                    title: '立即同步对话',
                    subtitle: _syncSubtitle(controller.conversationSyncState),
                    tint: AppPalette.blue,
                    tintBackground: AppPalette.blueSoft,
                    onTap: controller.busy
                        ? null
                        : () async {
                            final result = await controller
                                .syncChatGptConversation(manual: true);
                            if (!context.mounted) return;
                            await showAppMessage(
                              context,
                              title: result.synced ? '对话已生成笔记' : '同步结果',
                              message: result.message,
                              tone: result.synced
                                  ? AppMessageTone.success
                                  : AppMessageTone.info,
                            );
                          },
                  ),
                  _emailSyncRow(context, controller, EmailProvider.outlook),
                  _emailSyncRow(context, controller, EmailProvider.qq),
                  AppGroupRow(
                    icon: CupertinoIcons.shield_fill,
                    title: '安全防炸',
                    subtitle: '防密码爆破、恶意请求与 DDoS 分层防护',
                    tint: AppPalette.red,
                    tintBackground: AppPalette.redSoft,
                    onTap: onOpenSafety,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppGroup(
                title: '本地存储',
                children: [
                  AppGroupRow(
                    icon: CupertinoIcons.lock_shield_fill,
                    title: '密码保护',
                    subtitle: 'PBKDF2 加盐哈希；不会保存明文密码',
                    tint: AppPalette.green,
                    tintBackground: AppPalette.greenSoft,
                  ),
                  AppGroupRow(
                    icon: CupertinoIcons.archivebox_fill,
                    title: 'SQLite 数据库',
                    subtitle: controller.databasePath,
                    tint: AppPalette.blue,
                    tintBackground: AppPalette.blueSoft,
                    onTap: () => showAppMessage(
                      context,
                      title: '本地数据库位置',
                      message: controller.databasePath,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: AppPalette.resolve(context, AppPalette.raisedSurface),
                  borderRadius: BorderRadius.circular(14),
                  onPressed: () => _confirmSignOut(context),
                  child: Text(
                    '退出本地账号',
                    style: TextStyle(
                      color: AppPalette.resolve(context, AppPalette.red),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'AILearningOS · First runnable build',
                style: AppTextStyles.caption.copyWith(
                  color: AppPalette.resolve(context, AppPalette.secondaryText),
                ),
              ),
            ],
          );

          if (constraints.maxWidth >= 760) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: account),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: settings),
              ],
            );
          }
          return Column(
            children: [account, const SizedBox(height: 16), settings],
          );
        },
      ),
    );
  }

  static String _syncSubtitle(ConversationSyncState state) {
    if (state.lastError != null &&
        state.status == ConversationSyncStatus.error) {
      return state.lastError!;
    }
    if (state.lastSyncedTitle != null && state.lastSyncedAt != null) {
      return '上次已处理：${state.lastSyncedTitle} · ${_timeLabel(state.lastSyncedAt!)}';
    }
    return switch (state.status) {
      ConversationSyncStatus.disabled => '高频模式未开启 · 每天 23:00 统一生成摘要',
      ConversationSyncStatus.syncing => '正在检查收件箱…',
      ConversationSyncStatus.waiting => '等待 Bridge 提供至少两条对话快照',
      ConversationSyncStatus.synced => '暂无新的倒数第二条对话',
      ConversationSyncStatus.error => '等待修复同步配置后重试',
    };
  }

  static String _timeLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  AppGroupRow _emailSyncRow(
    BuildContext context,
    AppController controller,
    EmailProvider provider,
  ) {
    final state = controller.emailSyncState(provider);
    final connectedLabel = provider == EmailProvider.outlook
        ? 'OAuth 连接后自动读取新邮件'
        : 'IMAP / Bridge 连接后自动读取新邮件';
    return AppGroupRow(
      icon: CupertinoIcons.mail_solid,
      title: '${provider.label} 自动摘要',
      subtitle:
          state.lastError != null &&
              state.status == ConversationSyncStatus.error
          ? state.lastError!
          : state.lastSyncedSubject == null
          ? '${state.enabled ? (controller.conversationSyncState.enabled ? '每 15 分钟检查' : '每天 23:00 检查') : '此来源已关闭'} · $connectedLabel'
          : '上次已总结：${state.lastSyncedSubject}',
      tint: state.enabled ? AppPalette.blue : AppPalette.secondaryText,
      tintBackground: state.enabled
          ? AppPalette.blueSoft
          : AppPalette.softSurface,
      trailing: CupertinoSwitch(
        value: state.enabled,
        onChanged: controller.busy
            ? null
            : (value) async {
                final error = await controller.setEmailSyncEnabled(
                  provider,
                  value,
                );
                if (!context.mounted || error == null) return;
                await showAppMessage(
                  context,
                  title: '${provider.label} 设置失败',
                  message: error,
                  tone: AppMessageTone.warning,
                );
              },
      ),
      onTap: controller.busy
          ? null
          : () async {
              final result = await controller.syncEmailProvider(
                provider,
                manual: true,
              );
              if (!context.mounted) return;
              await showAppMessage(
                context,
                title: result.synced ? '邮件已生成摘要' : '同步结果',
                message: result.message,
                tone: result.synced
                    ? AppMessageTone.success
                    : AppMessageTone.info,
              );
            },
    );
  }

  Future<void> _startChatGptLogin(BuildContext pageContext) async {
    final controller = AppScope.of(pageContext);
    final error = await controller.signInWithChatGPT(
      presentChallenge: (challenge) =>
          presentChatGptLoginChallenge(pageContext, challenge),
    );
    if (!pageContext.mounted || error == null) return;
    await showAppMessage(
      pageContext,
      title: 'ChatGPT 登录未完成',
      message: error,
      tone: AppMessageTone.warning,
    );
  }

  Future<void> _showChatGptConnectionSheet(BuildContext pageContext) async {
    final controller = AppScope.of(pageContext);
    await showCupertinoModalPopup<void>(
      context: pageContext,
      barrierColor: const Color(0xB8000000),
      builder: (sheetContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight:
                    MediaQuery.of(sheetContext).size.height -
                    MediaQuery.of(sheetContext).viewInsets.bottom -
                    24,
              ),
              margin: const EdgeInsets.all(12),
              child: LiquidGlassSurface(
                tone: LiquidGlassTone.accent,
                radius: 30,
                blur: 34,
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'ChatGPT 登录 · chatgpt5.5',
                              style: AppTextStyles.title,
                            ),
                          ),
                          AppIconButton(
                            icon: CupertinoIcons.xmark,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        controller.chatGptAuth.authenticated
                            ? '当前已通过官方 ChatGPT 流程登录。后续词库联网补全会优先走 Codex 额度；Codex 负责保存和刷新授权，应用只保存本地账号关联信息。'
                            : '使用官方 ChatGPT 浏览器登录流程接入 chatgpt5.5，不会要求你把 ChatGPT 密码或 token 粘贴到应用里。',
                        style: AppTextStyles.body.copyWith(
                          color: const Color(0xE6FFFFFF),
                        ),
                      ),
                      if (controller.chatGptAuth.authenticated) ...[
                        const SizedBox(height: 16),
                        AppCard(
                          color: AppPalette.greenSoft,
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.check_mark_circled_solid,
                                color: Color(0xFFFFFFFF),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${controller.chatGptAuth.email ?? 'ChatGPT 账号'} · ${controller.chatGptAuth.planLabel}',
                                  style: AppTextStyles.body.copyWith(
                                    color: const Color(0xFFFFFFFF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        AppPrimaryButton(
                          label: '断开 ChatGPT 会话',
                          icon: CupertinoIcons.arrow_right_square,
                          fullWidth: true,
                          filled: false,
                          onPressed: controller.busy
                              ? null
                              : () async {
                                  Navigator.of(sheetContext).pop();
                                  final error = await controller
                                      .disconnectChatGpt();
                                  if (!pageContext.mounted) return;
                                  await showAppMessage(
                                    pageContext,
                                    title: error == null ? '已断开' : '断开失败',
                                    message:
                                        error ??
                                        'ChatGPT 会话已从 Codex App Server 退出。',
                                    tone: error == null
                                        ? AppMessageTone.success
                                        : AppMessageTone.warning,
                                  );
                                },
                        ),
                      ] else ...[
                        const SizedBox(height: 18),
                        AppPrimaryButton(
                          label: controller.busy ? '登录中…' : '使用 ChatGPT 登录',
                          icon: CupertinoIcons.chat_bubble_2_fill,
                          fullWidth: true,
                          onPressed:
                              controller.busy || !controller.chatGptSupported
                              ? null
                              : () async {
                                  Navigator.of(sheetContext).pop();
                                  await _startChatGptLogin(pageContext);
                                },
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        controller.chatGptSupported
                            ? '登录后会优先尝试使用 Codex 额度；如果本机没有 Codex 或你想改走独立 API，也可以继续使用下方的 DeepSeek API。'
                            : 'Windows 端请安装 Codex 后重试；Android 端需要连接受信任的 Codex 网关。',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          color: const Color(0xD9FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAiConnectionSheet(BuildContext pageContext) async {
    final controller = AppScope.of(pageContext);
    final apiKeyController = TextEditingController(
      text: controller.aiSettings.apiKey,
    );
    var enabled = controller.aiSettings.enabled;
    var saving = false;
    var testing = false;

    try {
      await showCupertinoModalPopup<void>(
        context: pageContext,
        barrierColor: const Color(0xB8000000),
        builder: (sheetContext) => AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 640,
                  maxHeight:
                      MediaQuery.of(sheetContext).size.height -
                      MediaQuery.of(sheetContext).viewInsets.bottom -
                      24,
                ),
                margin: const EdgeInsets.all(12),
                child: LiquidGlassSurface(
                  radius: 30,
                  blur: 34,
                  padding: const EdgeInsets.all(22),
                  child: StatefulBuilder(
                    builder: (context, setModalState) {
                      final currentSettings = AiConnectionSettings(
                        enabled: enabled,
                        apiKey: apiKeyController.text,
                        model: AiConnectionSettings.defaultModel,
                        apiKeyConfigured:
                            apiKeyController.text.trim().isNotEmpty ||
                            controller.aiSettings.apiKeyConfigured,
                        apiKeyHint: controller.aiSettings.apiKeyHint,
                        serverEncryptionReady:
                            controller.aiSettings.serverEncryptionReady,
                      );

                      Future<void> saveSettings() async {
                        if (saving) return;
                        setModalState(() => saving = true);
                        final error = await controller.saveAiSettings(
                          enabled: currentSettings.enabled,
                          apiKey: currentSettings.apiKey,
                          model: currentSettings.model,
                        );
                        if (!sheetContext.mounted || !pageContext.mounted)
                          return;
                        setModalState(() => saving = false);
                        if (error != null) {
                          await showAppMessage(
                            pageContext,
                            title: '保存失败',
                            message: error,
                            tone: AppMessageTone.warning,
                          );
                          return;
                        }
                        Navigator.of(sheetContext).pop();
                        await showAppMessage(
                          pageContext,
                          title: '已保存',
                          message:
                              'DeepSeek API Key 已用 AES-256-GCM 加密保存在服务器；待翻译、待识别词性和其他字段会由后台队列自动处理。',
                          tone: AppMessageTone.success,
                        );
                      }

                      Future<void> testConnection() async {
                        if (testing || !currentSettings.ready) return;
                        setModalState(() => testing = true);
                        final error = await controller.testAiConnection(
                          settings: currentSettings,
                        );
                        if (!sheetContext.mounted || !pageContext.mounted)
                          return;
                        setModalState(() => testing = false);
                        await showAppMessage(
                          pageContext,
                          title: error == null ? '连接正常' : '连接失败',
                          message:
                              error ?? 'DeepSeek 已连通，DeepSeek-V4-flash 可正常响应。',
                          tone: error == null
                              ? AppMessageTone.success
                              : AppMessageTone.warning,
                        );
                      }

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'DeepSeek API',
                                    style: AppTextStyles.title,
                                  ),
                                ),
                                AppIconButton(
                                  icon: CupertinoIcons.xmark,
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '这里填写 DeepSeek API Key。保存后，Key 只以 AES-256-GCM 密文留在服务器；服务器只在有待补全字段时每 30 秒重试，队列清空后自动停止。App 不会取回明文。',
                              style: AppTextStyles.body.copyWith(
                                color: AppPalette.resolve(
                                  context,
                                  AppPalette.secondaryText,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            AppCard(
                              color: enabled
                                  ? AppPalette.greenSoft
                                  : AppPalette.orangeSoft,
                              child: Row(
                                children: [
                                  Icon(
                                    enabled
                                        ? CupertinoIcons.cloud_fill
                                        : CupertinoIcons.cloud,
                                    color: AppPalette.resolve(
                                      context,
                                      enabled
                                          ? AppPalette.green
                                          : AppPalette.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      enabled
                                          ? '联网 AI 已启用；导入后立即进入服务器队列，自动补全翻译、音标、词性和例句。'
                                          : '当前已关闭联网 AI；你可以先保存 API Key，再手动开启。',
                                      style: AppTextStyles.body,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            CupertinoTextField(
                              controller: apiKeyController,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              placeholder:
                                  controller.aiSettings.apiKeyConfigured
                                  ? '已保存 ${controller.aiSettings.apiKeyHint ?? '加密 Key'}；留空保持不变'
                                  : 'DeepSeek API Key',
                              onChanged: (_) => setModalState(() {}),
                              prefix: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Icon(
                                  CupertinoIcons.lock_fill,
                                  size: 18,
                                  color: AppPalette.resolve(
                                    context,
                                    AppPalette.secondaryText,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: AppPalette.resolve(
                                  context,
                                  AppPalette.softSurface,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppPalette.resolve(
                                    context,
                                    AppPalette.separator,
                                  ),
                                  width: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Text(
                                  '启用联网 AI',
                                  style: AppTextStyles.body,
                                ),
                                const Spacer(),
                                CupertinoSwitch(
                                  value: enabled,
                                  onChanged: saving
                                      ? null
                                      : (value) => setModalState(
                                          () => enabled = value,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              controller.aiSettings.serverEncryptionReady
                                  ? '服务器加密层已就绪 · 模型固定为 DeepSeek-V4-flash · Key 不会返回客户端。'
                                  : '服务器还未设置 AILO_SECRETS_MASTER_KEY；设置前不会接受或明文保存 API Key。',
                              style: AppTextStyles.caption.copyWith(
                                color: AppPalette.resolve(
                                  context,
                                  AppPalette.secondaryText,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            AppPrimaryButton(
                              label: saving ? '保存中…' : '保存设置',
                              fullWidth: true,
                              onPressed: saving ? null : saveSettings,
                            ),
                            const SizedBox(height: 10),
                            AppPrimaryButton(
                              label: testing ? '测试中…' : '测试连接',
                              fullWidth: true,
                              filled: false,
                              onPressed:
                                  (testing || saving || !currentSettings.ready)
                                  ? null
                                  : testConnection,
                            ),
                            const SizedBox(height: 8),
                            CupertinoButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(sheetContext).pop(),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      apiKeyController.dispose();
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final shouldSignOut = await showAppConfirmation(
      context,
      title: '退出本地账号？',
      message: '学习数据不会删除，下次用同一邮箱和密码登录即可继续。',
      confirmLabel: '退出',
      destructive: true,
    );
    if (shouldSignOut && context.mounted) {
      await AppScope.of(context).signOut();
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppPalette.resolve(context, background),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppPalette.resolve(context, color),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
