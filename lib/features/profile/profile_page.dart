import 'package:flutter/cupertino.dart';

import '../../core/app_controller.dart';
import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';
import '../auth/chatgpt_login_dialog.dart';
import '../canvas/canvas_page.dart';

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
                        ? _codexConnectionSubtitle(controller)
                        : controller.chatGptAuth.available
                        ? '未登录 · 通过官方浏览器流程连接 Codex'
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
                    title: 'AI 模型源',
                    subtitle: controller.aiSettings.usesCodex
                        ? controller.chatGptAiReady
                              ? '已选择 Codex · ${controller.aiSettings.codexModel} · 使用 ChatGPT 额度'
                              : '已选择 Codex · 当前模型不可用'
                        : controller.deepSeekReady
                        ? '已选择 DeepSeek · ${controller.aiSettings.model} · 服务器后台运行'
                        : '已选择 DeepSeek · API Key 尚未启用',
                    tint: controller.aiReady
                        ? AppPalette.green
                        : AppPalette.blue,
                    tintBackground: controller.aiReady
                        ? AppPalette.greenSoft
                        : AppPalette.softSurface,
                    trailing: _StatusPill(
                      label: controller.aiReady ? '可用' : '待配置',
                      color: controller.aiReady
                          ? AppPalette.green
                          : AppPalette.blue,
                      background: controller.aiReady
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
                    icon: CupertinoIcons.book,
                    title: 'Canvas 课程',
                    subtitle: '连接学校账号 · 课程、作业与截止时间',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => CanvasPage(controller: controller),
                      ),
                    ),
                  ),
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

  static String _codexConnectionSubtitle(AppController controller) {
    final history = controller.codexHistory;
    final remaining = controller.codexQuota.primaryRemainingPercent;
    final quota = remaining == null
        ? '额度读取中'
        : '短周期剩余 ${remaining.toStringAsFixed(0)}%';
    if (history.lastError != null) return '$quota · OSS 读取需重试';
    return '$quota · OSS ${history.threadCount} 条实时读取';
  }

  static String _quotaWindowLabel(int? minutes) {
    if (minutes == null) return '额度周期';
    if (minutes % (24 * 60) == 0) return '${minutes ~/ (24 * 60)} 天额度';
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时额度';
    return '$minutes 分钟额度';
  }

  static String _quotaLine({
    required int? minutes,
    required double? used,
    required DateTime? resetsAt,
  }) {
    final label = _quotaWindowLabel(minutes);
    if (used == null) return '$label：等待 Codex 返回';
    final remaining = (100 - used).clamp(0, 100);
    final reset = resetsAt == null ? '' : ' · ${_timeLabel(resetsAt)} 重置';
    return '$label：已用 ${used.toStringAsFixed(0)}% · 剩余 ${remaining.toStringAsFixed(0)}%$reset';
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
                              'ChatGPT / Codex',
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
                            ? '已接入 ChatGPT 订阅对应的 Codex 额度，并通过官方 App Server 增量读取隔离 OSS 会话。应用不读取或保存 ChatGPT 密码、token、推理、命令及工具输出。'
                            : '使用官方 ChatGPT 浏览器登录流程接入 Codex 订阅额度，不会要求你把 ChatGPT 密码或 token 粘贴到应用里。',
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
                        const SizedBox(height: 12),
                        AppCard(
                          color: AppPalette.softSurface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Codex 额度 · ${controller.codexQuota.planType ?? controller.chatGptAuth.planLabel}',
                                style: AppTextStyles.body.copyWith(
                                  color: const Color(0xFFFFFFFF),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _quotaLine(
                                  minutes: controller
                                      .codexQuota
                                      .primaryWindowMinutes,
                                  used:
                                      controller.codexQuota.primaryUsedPercent,
                                  resetsAt:
                                      controller.codexQuota.primaryResetsAt,
                                ),
                                style: AppTextStyles.caption.copyWith(
                                  color: const Color(0xD9FFFFFF),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _quotaLine(
                                  minutes: controller
                                      .codexQuota
                                      .secondaryWindowMinutes,
                                  used: controller
                                      .codexQuota
                                      .secondaryUsedPercent,
                                  resetsAt:
                                      controller.codexQuota.secondaryResetsAt,
                                ),
                                style: AppTextStyles.caption.copyWith(
                                  color: const Color(0xD9FFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          color: controller.codexHistory.lastError == null
                              ? AppPalette.greenSoft
                              : AppPalette.orangeSoft,
                          child: Text(
                            controller.codexHistory.lastError ??
                                'OSS 会话实时读取已运行 · ${controller.codexHistory.threadCount} 条 · ${controller.codexHistory.lastReadAt == null ? '正在首次读取' : '上次 ${_timeLabel(controller.codexHistory.lastReadAt!)}'}',
                            style: AppTextStyles.body.copyWith(
                              color: const Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppPrimaryButton(
                          label: '刷新额度与 OSS 会话',
                          icon: CupertinoIcons.arrow_2_circlepath,
                          fullWidth: true,
                          onPressed: controller.busy
                              ? null
                              : () async {
                                  final error = await controller
                                      .refreshCodexConnection();
                                  if (!pageContext.mounted) return;
                                  await showAppMessage(
                                    pageContext,
                                    title: error == null ? '刷新完成' : '刷新未完成',
                                    message:
                                        error ?? 'Codex 额度与 OSS 会话记录已经重新读取。',
                                    tone: error == null
                                        ? AppMessageTone.success
                                        : AppMessageTone.warning,
                                  );
                                },
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
                            ? '登录后可把账号的全局 AI 源切换为 Codex；也可手动选择 DeepSeek。系统不会自动在两者之间切换。'
                            : 'Windows 端请安装 Codex；手机端请确认服务器已启用受信任 Codex 网关。',
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
    var provider = controller.aiSettings.provider;
    var saving = false;
    var testing = false;
    String? testedCandidateKey;

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
                        provider: provider,
                        codexModel: controller.aiSettings.codexModel,
                        apiKeyConfigured:
                            apiKeyController.text.trim().isNotEmpty ||
                            controller.aiSettings.apiKeyConfigured,
                        apiKeyHint: controller.aiSettings.apiKeyHint,
                        serverEncryptionReady:
                            controller.aiSettings.serverEncryptionReady,
                      );

                      Future<void> saveSettings() async {
                        if (saving) return;
                        final candidateKey = apiKeyController.text.trim();
                        if (currentSettings.usesDeepSeek &&
                            candidateKey.isNotEmpty &&
                            testedCandidateKey != candidateKey) {
                          await showAppMessage(
                            pageContext,
                            title: '请先测试新 API Key',
                            message:
                                '为避免误覆盖当前账号已保存的 Key，请点击“测试连接”，选择“测试新填写 API”，测试成功后再保存。',
                            tone: AppMessageTone.warning,
                          );
                          return;
                        }
                        if (currentSettings.usesDeepSeek &&
                            candidateKey.isNotEmpty &&
                            controller.aiSettings.apiKeyConfigured) {
                          final confirmed = await showAppConfirmation(
                            pageContext,
                            title: '替换当前账号的旧 API Key？',
                            message:
                                '新 API 已测试成功。保存后会覆盖服务器中与当前账号绑定的旧 Key；旧 Key 不会显示，也无法从 App 恢复。',
                            confirmLabel: '确认替换',
                            destructive: true,
                          );
                          if (!confirmed) return;
                        }
                        setModalState(() => saving = true);
                        final error = await controller.saveAiSettings(
                          enabled: currentSettings.enabled,
                          apiKey: currentSettings.apiKey,
                          model: currentSettings.model,
                          provider: currentSettings.provider,
                          codexModel: currentSettings.codexModel,
                        );
                        if (!sheetContext.mounted || !pageContext.mounted) {
                          return;
                        }
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
                          message: currentSettings.usesCodex
                              ? '全局 AI 源已切换为 Codex ${currentSettings.codexModel}。词库、摘要、课程计划和 AI Chat 将只使用 ChatGPT Codex 额度，不会回退到 DeepSeek。'
                              : '全局 AI 源已切换为 DeepSeek V4 Flash。词库、摘要、课程计划和 AI Chat 将只使用 DeepSeek；API Key 以 AES-256-GCM 密文保存在服务器。',
                          tone: AppMessageTone.success,
                        );
                      }

                      Future<void> testConnection() async {
                        if (testing) return;
                        var keySource = AiApiKeyTestSource.stored;
                        if (currentSettings.usesDeepSeek) {
                          final hasStoredKey =
                              controller.aiSettings.apiKeyConfigured;
                          final hasCandidateKey = apiKeyController.text
                              .trim()
                              .isNotEmpty;
                          final selected =
                              await showCupertinoModalPopup<AiApiKeyTestSource>(
                                context: pageContext,
                                builder: (choiceContext) => CupertinoActionSheet(
                                  title: const Text('选择要测试的 API Key'),
                                  message: const Text(
                                    '测试只验证连接，不会保存、替换或删除服务器上的任何 Key。',
                                  ),
                                  actions: [
                                    CupertinoActionSheetAction(
                                      onPressed: hasStoredKey
                                          ? () => Navigator.of(
                                              choiceContext,
                                            ).pop(AiApiKeyTestSource.stored)
                                          : () {},
                                      child: Text(
                                        hasStoredKey
                                            ? '测试旧 API · ${controller.aiSettings.apiKeyHint ?? '服务器已保存'}'
                                            : '测试旧 API · 当前账号未保存',
                                        style: TextStyle(
                                          color: hasStoredKey
                                              ? null
                                              : CupertinoColors.inactiveGray,
                                        ),
                                      ),
                                    ),
                                    CupertinoActionSheetAction(
                                      onPressed: hasCandidateKey
                                          ? () => Navigator.of(
                                              choiceContext,
                                            ).pop(AiApiKeyTestSource.candidate)
                                          : () {},
                                      child: Text(
                                        hasCandidateKey
                                            ? '测试新填写 API · 不保存'
                                            : '测试新填写 API · 请先输入',
                                        style: TextStyle(
                                          color: hasCandidateKey
                                              ? null
                                              : CupertinoColors.inactiveGray,
                                        ),
                                      ),
                                    ),
                                  ],
                                  cancelButton: CupertinoActionSheetAction(
                                    onPressed: () =>
                                        Navigator.of(choiceContext).pop(),
                                    child: const Text('取消'),
                                  ),
                                ),
                              );
                          if (selected == null) return;
                          keySource = selected;
                        } else if (!controller.chatGptAiReady) {
                          return;
                        }
                        setModalState(() => testing = true);
                        final error = await controller.testAiConnection(
                          settings: currentSettings,
                          keySource: keySource,
                        );
                        if (!sheetContext.mounted || !pageContext.mounted) {
                          return;
                        }
                        setModalState(() {
                          testing = false;
                          if (error == null &&
                              keySource == AiApiKeyTestSource.candidate) {
                            testedCandidateKey = apiKeyController.text.trim();
                          }
                        });
                        await showAppMessage(
                          pageContext,
                          title: error == null ? '连接正常' : '连接失败',
                          message:
                              error ??
                              (currentSettings.usesCodex
                                  ? 'Codex 已使用 ${currentSettings.codexModel} 完成真实响应测试。'
                                  : keySource == AiApiKeyTestSource.stored
                                  ? '当前账号服务器上已保存的旧 API Key 连接正常；没有修改任何 Key。'
                                  : '新填写的 API Key 连接正常；尚未保存，确认保存后才会替换旧 Key。'),
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
                                    'AI 模型源',
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
                              '这是账号级全局 AI 开关。词库、对话与邮件/飞书摘要、课程计划和 AI Chat 都使用这里选中的来源。两个来源严格分流，失败时不会静默切换。',
                              style: AppTextStyles.body.copyWith(
                                color: AppPalette.resolve(
                                  context,
                                  AppPalette.secondaryText,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            CupertinoSlidingSegmentedControl<AiProvider>(
                              groupValue: provider,
                              children: const {
                                AiProvider.codex: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Text('Codex'),
                                ),
                                AiProvider.deepSeek: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Text('DeepSeek V4'),
                                ),
                              },
                              onValueChanged: (value) {
                                if (!saving && value != null) {
                                  setModalState(() => provider = value);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            AppCard(
                              color:
                                  (provider == AiProvider.codex
                                      ? controller.chatGptAiReady
                                      : enabled)
                                  ? AppPalette.greenSoft
                                  : AppPalette.orangeSoft,
                              child: Row(
                                children: [
                                  Icon(
                                    (provider == AiProvider.codex
                                            ? controller.chatGptAiReady
                                            : enabled)
                                        ? CupertinoIcons.cloud_fill
                                        : CupertinoIcons.cloud,
                                    color: AppPalette.resolve(
                                      context,
                                      (provider == AiProvider.codex
                                              ? controller.chatGptAiReady
                                              : enabled)
                                          ? AppPalette.green
                                          : AppPalette.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      provider == AiProvider.codex
                                          ? controller.chatGptAiReady
                                                ? '${currentSettings.codexModel} 已由当前 Codex 模型列表确认；所有已接入的 AI 功能都会统一使用它。'
                                                : '${currentSettings.codexModel} 当前不可用。请重新登录并刷新 Codex 模型列表。'
                                          : enabled
                                          ? 'DeepSeek 已启用；服务器可在 App 关闭后继续处理待补全队列。'
                                          : 'DeepSeek 当前关闭；可先保存 API Key，再手动开启。',
                                      style: AppTextStyles.body,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (provider == AiProvider.deepSeek)
                              CupertinoTextField(
                                controller: apiKeyController,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                placeholder:
                                    controller.aiSettings.apiKeyConfigured
                                    ? '已保存 ${controller.aiSettings.apiKeyHint ?? '加密 Key'}；留空保持不变'
                                    : 'DeepSeek API Key',
                                onChanged: (_) => setModalState(
                                  () => testedCandidateKey = null,
                                ),
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
                            if (provider == AiProvider.deepSeek)
                              const SizedBox(height: 10),
                            if (provider == AiProvider.deepSeek)
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
                              provider == AiProvider.codex
                                  ? 'Codex 模型来自 App Server 的实时 model/list；手机使用实际后端的账号隔离 App Server，不在客户端保存 ChatGPT token。当前：${currentSettings.codexModel}。'
                                  : controller.aiSettings.serverEncryptionReady
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
                                  (testing ||
                                      saving ||
                                      (currentSettings.usesCodex
                                          ? !controller.chatGptAiReady
                                          : !currentSettings.ready))
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
