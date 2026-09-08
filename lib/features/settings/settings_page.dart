import 'package:flutter/cupertino.dart';

import '../../core/app_controller.dart';
import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';
import '../auth/chatgpt_login_dialog.dart';
import '../canvas/canvas_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.currentUser!;
    final displayName = user.displayName.trim();
    final initial = displayName.isEmpty ? '?' : displayName.substring(0, 1);
    return AppPage(
      title: 'Settings',
      subtitle: '账号与 AI 连接',
      child: Column(
        children: [
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppPalette.resolve(context, AppPalette.blue),
                        AppPalette.resolve(context, AppPalette.purple),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName, style: AppTextStyles.title),
                      const SizedBox(height: 3),
                      Text(
                        user.email,
                        style: AppTextStyles.caption.copyWith(
                          color: AppPalette.resolve(
                            context,
                            AppPalette.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppGroup(
            title: '信息源',
            children: [
              AppGroupRow(
                icon: CupertinoIcons.calendar_badge_plus,
                title: 'Canvas LMS',
                subtitle: _canvasSubtitle(controller),
                tint: controller.canvasTodoState.connected
                    ? AppPalette.green
                    : AppPalette.blue,
                tintBackground: controller.canvasTodoState.connected
                    ? AppPalette.greenSoft
                    : AppPalette.blueSoft,
                trailing: controller.canvasTodoState.loading
                    ? const CupertinoActivityIndicator()
                    : null,
                onTap: controller.canvasTodoState.loading
                    ? null
                    : () => _openCanvas(context, controller),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppGroup(
            title: 'AI 模型源',
            children: [
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '单词 AI 导入和 Learning Journal 分析使用这里选中的路线。只有开启“额度恢复自动回切”后，Codex 五小时额度用尽才会临时转 DeepSeek。',
                      style: AppTextStyles.caption.copyWith(
                        color: AppPalette.resolve(
                          context,
                          AppPalette.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CupertinoSlidingSegmentedControl<AiProvider>(
                      groupValue: controller.aiSettings.provider,
                      children: const {
                        AiProvider.deepSeek: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('DeepSeek'),
                        ),
                        AiProvider.codex: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('ChatGPT-Codex'),
                        ),
                      },
                      onValueChanged: (provider) {
                        if (controller.busy || provider == null) return;
                        _changeProvider(context, controller, provider);
                      },
                    ),
                  ],
                ),
              ),
              AppGroupRow(
                icon: CupertinoIcons.sparkles,
                title: 'DeepSeek',
                subtitle: controller.aiSettings.apiKeyConfigured
                    ? '${controller.aiSettings.model} · Key 已保存在服务器'
                    : '尚未配置 API Key',
                tint: controller.deepSeekReady
                    ? AppPalette.green
                    : AppPalette.blue,
                tintBackground: controller.deepSeekReady
                    ? AppPalette.greenSoft
                    : AppPalette.blueSoft,
                onTap: () => _showDeepSeekSheet(context, controller),
              ),
              AppGroupRow(
                icon: CupertinoIcons.chat_bubble_2_fill,
                title: 'ChatGPT-Codex',
                subtitle: controller.chatGptAuth.authenticated
                    ? '${controller.chatGptAuth.planLabel} · ${controller.aiSettings.codexModel}'
                    : '使用官方设备码流程连接 Codex 额度',
                tint: controller.chatGptAuth.authenticated
                    ? AppPalette.green
                    : AppPalette.purple,
                tintBackground: controller.chatGptAuth.authenticated
                    ? AppPalette.greenSoft
                    : AppPalette.softSurface,
                onTap: () => _showCodexActions(context, controller),
              ),
              AppGroupRow(
                icon: CupertinoIcons.arrow_2_circlepath,
                title: '额度恢复后自动切回 Codex',
                subtitle: _autoReturnSubtitle(controller),
                tint: controller.aiSettings.autoReturnToCodex
                    ? AppPalette.green
                    : AppPalette.blue,
                tintBackground: controller.aiSettings.autoReturnToCodex
                    ? AppPalette.greenSoft
                    : AppPalette.blueSoft,
                trailing: CupertinoSwitch(
                  value: controller.aiSettings.autoReturnToCodex,
                  onChanged:
                      controller.busy ||
                          !controller.chatGptAuth.authenticated ||
                          !controller.aiSettings.apiKeyConfigured
                      ? null
                      : (value) => _setAutoReturn(context, controller, value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppGroup(
            title: 'AI 用量 / 剩余额度',
            trailing: AppIconButton(
              icon: CupertinoIcons.refresh,
              semanticLabel: '刷新 AI 用量',
              onPressed: controller.chatGptAuth.authenticated
                  ? controller.refreshAiUsage
                  : null,
            ),
            children: [_AiUsagePanel(controller: controller)],
          ),
          const SizedBox(height: 16),
          AppGroup(
            title: '当前数据',
            children: [
              AppGroupRow(
                icon: CupertinoIcons.book_fill,
                title: '${controller.words.length} 个单词',
                subtitle: '${controller.dueWords.length} 个待复习',
              ),
              AppGroupRow(
                icon: CupertinoIcons.doc_text_fill,
                title: '${controller.notes.length} 篇 Learning Journal',
                subtitle: '旧笔记继续保留并可查看',
                tint: AppPalette.green,
                tintBackground: AppPalette.greenSoft,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: AppPalette.resolve(context, AppPalette.raisedSurface),
              borderRadius: BorderRadius.circular(14),
              onPressed: () => _confirmSignOut(context, controller),
              child: Text(
                '退出账号',
                style: TextStyle(
                  color: AppPalette.resolve(context, AppPalette.red),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<String?> _selectProvider(
    AppController controller,
    AiProvider provider,
  ) => controller.saveAiSettings(
    enabled: true,
    apiKey: '',
    model: controller.aiSettings.model,
    provider: provider,
    codexModel: controller.aiSettings.codexModel,
  );

  static String _canvasSubtitle(AppController controller) {
    final state = controller.canvasTodoState;
    if (state.loading) return '正在同步课程与作业…';
    if (state.error != null) return '同步失败：${state.error}';
    if (!state.connected) return '连接学校 Canvas，将作业加入主页待办';
    final name = state.profileName?.trim();
    return '${name == null || name.isEmpty ? '已连接' : '已连接：$name'} · ${state.pending.length} 项待办';
  }

  static String _autoReturnSubtitle(AppController controller) {
    if (!controller.chatGptAuth.authenticated) return '先连接 ChatGPT-Codex';
    if (!controller.aiSettings.apiKeyConfigured) return '先配置 DeepSeek API Key';
    if (!controller.aiSettings.autoReturnToCodex) {
      return '关闭；AI 路线只按手动选择变化';
    }
    final resumeAt = controller.aiSettings.codexResumeAt;
    if (resumeAt == null) return '已开启；Codex 额度用尽时临时转 DeepSeek';
    return '正在使用 DeepSeek；${_QuotaWindow.dateTime(resumeAt)} 后由服务器检查并回切';
  }

  static Future<void> _setAutoReturn(
    BuildContext context,
    AppController controller,
    bool enabled,
  ) async {
    final error = await controller.saveAiSettings(
      enabled: true,
      apiKey: '',
      model: controller.aiSettings.model,
      provider: controller.aiSettings.provider,
      codexModel: controller.aiSettings.codexModel,
      autoReturnToCodex: enabled,
    );
    if (!context.mounted) return;
    await showAppMessage(
      context,
      title: error == null ? '自动回切已${enabled ? '开启' : '关闭'}' : '设置失败',
      message:
          error ??
          (enabled
              ? 'Codex 五小时额度用尽后会临时使用 DeepSeek，并在官方重置时间后自动切回。'
              : '之后只按手动选择的 AI 路线运行。'),
      tone: error == null ? AppMessageTone.success : AppMessageTone.warning,
    );
  }

  static Future<void> _openCanvas(
    BuildContext context,
    AppController controller,
  ) async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(builder: (_) => CanvasPage(controller: controller)),
    );
    await controller.refreshCanvasTodos();
  }

  static Future<void> _changeProvider(
    BuildContext context,
    AppController controller,
    AiProvider provider,
  ) async {
    final error = await _selectProvider(controller, provider);
    if (!context.mounted) return;
    await showAppMessage(
      context,
      title: error == null ? 'AI 来源已切换' : '无法切换',
      message:
          error ??
          '现在使用 ${provider == AiProvider.codex ? 'ChatGPT-Codex' : 'DeepSeek'}。',
      tone: error == null ? AppMessageTone.success : AppMessageTone.warning,
    );
  }

  Future<void> _showDeepSeekSheet(
    BuildContext pageContext,
    AppController controller,
  ) async {
    final key = TextEditingController();
    final model = TextEditingController(text: controller.aiSettings.model);
    await showCupertinoModalPopup<void>(
      context: pageContext,
      builder: (sheetContext) => _SettingsSheet(
        heading: 'DeepSeek 设置',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoTextField(
              controller: key,
              obscureText: true,
              placeholder: controller.aiSettings.apiKeyConfigured
                  ? 'Key 已保存；留空表示不替换'
                  : 'DeepSeek API Key',
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 10),
            CupertinoTextField(
              controller: model,
              placeholder: AiConnectionSettings.defaultModel,
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              label: '保存 DeepSeek',
              fullWidth: true,
              onPressed: () async {
                final error = await controller.saveAiSettings(
                  enabled: true,
                  apiKey: key.text,
                  model: model.text,
                  provider: AiProvider.deepSeek,
                  codexModel: controller.aiSettings.codexModel,
                );
                if (!sheetContext.mounted) return;
                if (error != null) {
                  await showAppMessage(
                    sheetContext,
                    title: '保存失败',
                    message: error,
                    tone: AppMessageTone.warning,
                  );
                  return;
                }
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );
    key.dispose();
    model.dispose();
  }

  Future<void> _showCodexActions(
    BuildContext pageContext,
    AppController controller,
  ) async {
    if (!controller.chatGptAuth.authenticated) {
      final error = await controller.signInWithChatGPT(
        deviceCode: controller.usesRemoteCodexGateway,
        presentChallenge: (challenge) =>
            presentChatGptLoginChallenge(pageContext, challenge),
      );
      if (!pageContext.mounted) return;
      await showAppMessage(
        pageContext,
        title: error == null ? 'ChatGPT 已连接' : 'ChatGPT 登录未完成',
        message: error ?? '现在可以手动切换到 ChatGPT-Codex。',
        tone: error == null ? AppMessageTone.success : AppMessageTone.warning,
      );
      return;
    }
    await showCupertinoModalPopup<void>(
      context: pageContext,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('ChatGPT-Codex'),
        message: Text(
          '${controller.chatGptAuth.planLabel} · ${controller.aiSettings.codexModel}',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              final error = await controller.refreshCodexConnection();
              if (!pageContext.mounted) return;
              await showAppMessage(
                pageContext,
                title: error == null ? '连接已刷新' : '刷新失败',
                message: error ?? '账号、模型和额度状态已更新。',
                tone: error == null
                    ? AppMessageTone.success
                    : AppMessageTone.warning,
              );
            },
            child: const Text('刷新连接'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              final error = await controller.disconnectChatGpt();
              if (!pageContext.mounted || error == null) return;
              await showAppMessage(
                pageContext,
                title: '断开失败',
                message: error,
                tone: AppMessageTone.warning,
              );
            },
            child: const Text('断开 ChatGPT'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    AppController controller,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('退出账号？'),
        content: const Text('服务器中的单词和 Learning Journal 不会被删除。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.signOut();
  }
}

class _AiUsagePanel extends StatelessWidget {
  const _AiUsagePanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final quota = controller.codexQuota;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppPalette.resolve(context, AppPalette.softSurface),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.chart_bar_fill,
                  size: 17,
                  color: AppPalette.resolve(context, AppPalette.purple),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  '当前路线：${controller.activeAiProviderLabel}',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!controller.chatGptAuth.authenticated)
            Text(
              '连接 ChatGPT-Codex 后，这里会显示官方短周期/长周期已用比例、剩余比例和重置时间。DeepSeek API 的账户余额需在 DeepSeek 平台查看。',
              style: AppTextStyles.caption.copyWith(
                color: AppPalette.resolve(context, AppPalette.secondaryText),
              ),
            )
          else if (!quota.available)
            Text(
              quota.message ?? 'Codex 用量暂时不可用。',
              style: AppTextStyles.caption.copyWith(
                color: AppPalette.resolve(context, AppPalette.orange),
              ),
            )
          else ...[
            if (quota.planType?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'ChatGPT ${quota.planType}',
                  style: AppTextStyles.caption,
                ),
              ),
            _QuotaWindow(
              label: '短周期',
              used: quota.primaryUsedPercent,
              remaining: quota.primaryRemainingPercent,
              minutes: quota.primaryWindowMinutes,
              resetsAt: quota.primaryResetsAt,
            ),
            const SizedBox(height: 14),
            _QuotaWindow(
              label: '长周期',
              used: quota.secondaryUsedPercent,
              remaining: quota.secondaryRemainingPercent,
              minutes: quota.secondaryWindowMinutes,
              resetsAt: quota.secondaryResetsAt,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuotaWindow extends StatelessWidget {
  const _QuotaWindow({
    required this.label,
    required this.used,
    required this.remaining,
    required this.minutes,
    required this.resetsAt,
  });

  final String label;
  final double? used;
  final double? remaining;
  final int? minutes;
  final DateTime? resetsAt;

  @override
  Widget build(BuildContext context) {
    final fraction = ((used ?? 0) / 100).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label${minutes == null ? '' : ' · ${_duration(minutes!)}'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              used == null
                  ? '暂无数据'
                  : '已用 ${used!.toStringAsFixed(0)}% · 剩余 ${(remaining ?? 0).toStringAsFixed(0)}%',
              style: AppTextStyles.caption,
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 7,
            color: AppPalette.resolve(context, AppPalette.softSurface),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: ColoredBox(
                color: AppPalette.resolve(
                  context,
                  fraction >= 0.9 ? AppPalette.orange : AppPalette.blue,
                ),
              ),
            ),
          ),
        ),
        if (resetsAt != null) ...[
          const SizedBox(height: 5),
          Text(
            '重置：${dateTime(resetsAt!)}',
            style: AppTextStyles.caption.copyWith(
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
          ),
        ],
      ],
    );
  }

  static String _duration(int value) {
    if (value % (24 * 60) == 0) return '${value ~/ (24 * 60)} 天';
    if (value % 60 == 0) return '${value ~/ 60} 小时';
    return '$value 分钟';
  }

  static String dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.heading, required this.child});

  final String heading;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.all(12),
          child: LiquidGlassSurface(
            radius: 28,
            blur: 34,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(heading, style: AppTextStyles.title)),
                    AppIconButton(
                      icon: CupertinoIcons.xmark,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
