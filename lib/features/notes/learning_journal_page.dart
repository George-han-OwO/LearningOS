import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/learning_journal.dart';
import '../../domain/models.dart';

class LearningJournalPage extends StatelessWidget {
  const LearningJournalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final journals = controller.notes;
    return AppPage(
      title: 'Learning Journal',
      subtitle: '${journals.length} 篇学习笔记 · 统一结构化格式',
      actions: [
        AppPrimaryButton(
          label: 'AI 分析',
          icon: CupertinoIcons.sparkles,
          filled: false,
          onPressed: controller.busy ? null : () => _showAiImport(context),
        ),
        AppPrimaryButton(
          label: '新建 Journal',
          icon: CupertinoIcons.add,
          onPressed: controller.busy ? null : () => _showEditor(context),
        ),
      ],
      mobileActions: [
        AppPrimaryButton(
          label: 'AI 分析',
          icon: CupertinoIcons.sparkles,
          filled: false,
          onPressed: controller.busy ? null : () => _showAiImport(context),
        ),
        AppPrimaryButton(
          label: '新建',
          icon: CupertinoIcons.add,
          onPressed: controller.busy ? null : () => _showEditor(context),
        ),
      ],
      child: journals.isEmpty
          ? const _EmptyJournal()
          : Column(
              children: [
                for (final journal in journals) ...[
                  _JournalCard(journal: journal),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Future<void> _showEditor(BuildContext pageContext) async {
    final title = TextEditingController(text: '今日学习记录');
    final content = TextEditingController(
      text: LearningJournalTemplate.blank(),
    );
    await showCupertinoModalPopup<void>(
      context: pageContext,
      barrierColor: const Color(0xB8000000),
      builder: (sheetContext) => _EditorSheet(
        title: title,
        content: content,
        onSave: () async {
          if (title.text.trim().isEmpty || content.text.trim().isEmpty) {
            await showAppMessage(
              sheetContext,
              title: '内容不完整',
              message: '请填写标题和 Learning Journal 内容。',
              tone: AppMessageTone.warning,
            );
            return;
          }
          await AppScope.of(pageContext).addNote(
            title: title.text.trim(),
            contentEnglish: '',
            contentChinese: content.text.trim(),
            source: '手动 Learning Journal',
          );
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
    title.dispose();
    content.dispose();
  }

  Future<void> _showAiImport(BuildContext pageContext) async {
    final source = TextEditingController();
    await showCupertinoModalPopup<void>(
      context: pageContext,
      barrierColor: const Color(0xB8000000),
      builder: (sheetContext) => _AiImportSheet(
        source: source,
        onAnalyze: () async {
          if (source.text.trim().isEmpty) {
            await showAppMessage(
              sheetContext,
              title: '还没有学习材料',
              message: '请粘贴文章、课堂记录、AI 对话或其他学习内容。',
              tone: AppMessageTone.warning,
            );
            return;
          }
          try {
            final result = await AppScope.of(
              pageContext,
            ).importConversation(source.text);
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
            await showAppMessage(
              pageContext,
              title: 'Learning Journal 已生成',
              message:
                  '${result.title}\n同时加入 ${result.insertedWords} 个候选单词。${result.warning == null ? '' : '\n${result.warning}'}',
              tone: AppMessageTone.success,
            );
          } catch (error) {
            if (!sheetContext.mounted) return;
            await showAppMessage(
              sheetContext,
              title: 'AI 分析失败',
              message: '$error',
              tone: AppMessageTone.warning,
            );
          }
        },
      ),
    );
    source.dispose();
  }
}

class _EditorSheet extends StatelessWidget {
  const _EditorSheet({
    required this.title,
    required this.content,
    required this.onSave,
  });

  final TextEditingController title;
  final TextEditingController content;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) => _SheetFrame(
    heading: '新建 Learning Journal',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(controller: title, placeholder: '标题', maxLines: 1),
        const SizedBox(height: 12),
        _Field(
          key: const ValueKey('journal-editor'),
          controller: content,
          placeholder: 'Learning Journal Markdown',
          minLines: 18,
          maxLines: 30,
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          label: '保存 Journal',
          icon: CupertinoIcons.check_mark,
          fullWidth: true,
          onPressed: onSave,
        ),
      ],
    ),
  );
}

class _AiImportSheet extends StatelessWidget {
  const _AiImportSheet({required this.source, required this.onAnalyze});

  final TextEditingController source;
  final Future<void> Function() onAnalyze;

  @override
  Widget build(BuildContext context) => _SheetFrame(
    heading: 'AI 分析并生成 Journal',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '粘贴学习材料。当前选择的 DeepSeek 或 ChatGPT-Codex 会提取重点、行动项和单词，并按固定 Learning Journal 模板保存。',
          style: AppTextStyles.body.copyWith(
            color: AppPalette.resolve(context, AppPalette.secondaryText),
          ),
        ),
        const SizedBox(height: 12),
        _Field(
          key: const ValueKey('journal-ai-source'),
          controller: source,
          placeholder: '文章、课堂记录、AI 对话……',
          minLines: 14,
          maxLines: 24,
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          key: const ValueKey('journal-ai-submit'),
          label: 'AI 分析总结',
          icon: CupertinoIcons.sparkles,
          fullWidth: true,
          onPressed: onAnalyze,
        ),
      ],
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.heading, required this.child});

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
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight:
                MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                24,
          ),
          margin: const EdgeInsets.all(12),
          child: LiquidGlassSurface(
            radius: 28,
            blur: 34,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(heading, style: AppTextStyles.title),
                      ),
                      AppIconButton(
                        icon: CupertinoIcons.xmark,
                        semanticLabel: '关闭',
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
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.placeholder,
    this.minLines,
    this.maxLines,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final int? minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => CupertinoTextField(
    controller: controller,
    placeholder: placeholder,
    minLines: minLines,
    maxLines: maxLines,
    padding: const EdgeInsets.all(14),
    textCapitalization: TextCapitalization.sentences,
    style: TextStyle(
      color: AppPalette.resolve(context, AppPalette.text),
      fontFamily: maxLines == 1 ? null : 'monospace',
      fontSize: maxLines == 1 ? 16 : 13,
      height: 1.5,
    ),
    decoration: BoxDecoration(
      color: AppPalette.resolve(context, AppPalette.softSurface),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppPalette.resolve(context, AppPalette.separator),
      ),
    ),
  );
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({required this.journal});

  final StudyNote journal;

  @override
  Widget build(BuildContext context) {
    final content = journal.contentChinese.trim().isNotEmpty
        ? journal.contentChinese.trim()
        : journal.contentEnglish.trim();
    return AppCard(
      onTap: () => showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => _SheetFrame(
          heading: journal.title,
          child: Text(
            content,
            style: AppTextStyles.body.copyWith(
              color: AppPalette.resolve(context, AppPalette.text),
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppPalette.resolve(context, AppPalette.blueSoft),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              CupertinoIcons.doc_text_fill,
              color: AppPalette.resolve(context, AppPalette.blue),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(journal.title, style: AppTextStyles.sectionTitle),
                const SizedBox(height: 4),
                Text(
                  '${_date(journal.updatedAt)} · ${journal.source}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppPalette.resolve(
                      context,
                      AppPalette.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _preview(content),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: AppPalette.resolve(context, AppPalette.secondaryText),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  static String _preview(String value) {
    final lines = value
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^#+\s*'), '').trim())
        .where(
          (line) =>
              line.isNotEmpty && line != '---' && line != '# Learning Journal',
        )
        .take(4);
    return lines.join(' · ');
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.doc_text,
            size: 38,
            color: AppPalette.resolve(context, AppPalette.secondaryText),
          ),
          const SizedBox(height: 12),
          const Text('还没有 Learning Journal', style: AppTextStyles.title),
          const SizedBox(height: 6),
          Text(
            '手动填写固定模板，或让当前 AI 分析学习材料后自动生成。',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
          ),
        ],
      ),
    ),
  );
}
