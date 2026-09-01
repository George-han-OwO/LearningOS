import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/models.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final notes = controller.notes;
    final user = controller.currentUser!;
    StudyNote? selected;
    if (notes.isNotEmpty) {
      selected =
          notes.where((note) => note.id == _selectedId).firstOrNull ??
          notes.first;
    }

    return AppPage(
      title: '${user.displayName} Library',
      subtitle: '${notes.length} 篇 Note · ChatGPT / 录音豆 / Outlook / QQ',
      actions: [
        AppIconButton(
          icon: CupertinoIcons.square_arrow_down,
          semanticLabel: '导出全部笔记',
          onPressed: notes.isEmpty ? null : () => _exportNotes(context, notes),
        ),
        AppIconButton(
          icon: CupertinoIcons.archivebox,
          semanticLabel: '导出 Obsidian 知识库',
          onPressed: notes.isEmpty
              ? null
              : () => _exportObsidianVault(context, notes),
        ),
        AppPrimaryButton(
          label: '手动补录',
          icon: CupertinoIcons.chat_bubble_2_fill,
          filled: false,
          onPressed: () => _showConversationImport(context),
        ),
        AppPrimaryButton(
          label: '新建',
          icon: CupertinoIcons.add,
          onPressed: () => _showAddNote(context),
        ),
      ],
      mobileActions: [
        AppIconButton(
          icon: CupertinoIcons.ellipsis,
          semanticLabel: '更多 Library 工具',
          onPressed: () => _showLibraryActions(context, notes),
        ),
        AppPrimaryButton(
          label: '新建',
          icon: CupertinoIcons.add,
          onPressed: () => _showAddNote(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ConversationSyncCard(),
          const SizedBox(height: 22),
          _LibrarySectionHeader(count: notes.length),
          const SizedBox(height: 12),
          if (notes.isEmpty)
            const _EmptyNotes()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 760) {
                  return SizedBox(
                    height: 620,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _NoteList(
                            notes: notes,
                            selectedId: selected!.id,
                            onSelected: (note) =>
                                setState(() => _selectedId = note.id),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _NoteDetail(note: selected)),
                      ],
                    ),
                  );
                }
                final columnCount = constraints.maxWidth < 600 ? 1 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: notes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: columnCount == 1 ? 154 : 184,
                  ),
                  itemBuilder: (context, index) => _MobileNoteCard(
                    note: notes[index],
                    compact: columnCount > 1,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showLibraryActions(
    BuildContext pageContext,
    List<StudyNote> notes,
  ) {
    return showCupertinoModalPopup<void>(
      context: pageContext,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Library 工具'),
        message: const Text('补录学习内容，或把现有笔记导出到其他知识库。'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _showConversationImport(pageContext);
            },
            child: const Text('手动补录 AI 对话'),
          ),
          if (notes.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _exportNotes(pageContext, notes);
              },
              child: const Text('导出 Markdown'),
            ),
          if (notes.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _exportObsidianVault(pageContext, notes);
              },
              child: const Text('导出 Obsidian Vault'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _showConversationImport(BuildContext pageContext) async {
    final transcript = TextEditingController();
    await showCupertinoModalPopup<void>(
      context: pageContext,
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
                maxWidth: 720,
                maxHeight:
                    MediaQuery.of(sheetContext).size.height -
                    MediaQuery.of(sheetContext).viewInsets.bottom -
                    24,
              ),
              margin: const EdgeInsets.all(12),
              child: LiquidGlassSurface(
                radius: 30,
                blur: 34,
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '手动补录 AI 对话',
                              style: AppTextStyles.title,
                            ),
                          ),
                          AppIconButton(
                            icon: CupertinoIcons.xmark,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '粘贴你和 AI 的对话。系统会保存原始证据，生成中英双语学习摘要，并把值得复习的英文词自动加入 Word Bank。',
                        style: AppTextStyles.body.copyWith(
                          color: AppPalette.resolve(
                            context,
                            AppPalette.secondaryText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoTextField(
                        controller: transcript,
                        placeholder: '例如：User: ...\nAI: ...',
                        minLines: 12,
                        maxLines: 20,
                        padding: const EdgeInsets.all(14),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: BoxDecoration(
                          color: AppPalette.resolve(
                            context,
                            AppPalette.softSurface,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppPalette.resolve(
                              context,
                              AppPalette.separator,
                            ),
                            width: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppPrimaryButton(
                        label: '分析并加入学习记录',
                        icon: CupertinoIcons.sparkles,
                        fullWidth: true,
                        onPressed: () async {
                          if (transcript.text.trim().isEmpty) {
                            await showAppMessage(
                              sheetContext,
                              title: '内容为空',
                              message: '请先粘贴 AI 对话内容。',
                              tone: AppMessageTone.warning,
                            );
                            return;
                          }
                          try {
                            final result = await AppScope.of(
                              pageContext,
                            ).importConversation(transcript.text);
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop();
                            await showAppMessage(
                              pageContext,
                              title: '对话已归档',
                              message:
                                  '${result.title}\n已加入 ${result.insertedWords} 个生词。${result.warning == null ? '' : '\n${result.warning}'}',
                              tone: AppMessageTone.success,
                            );
                          } catch (error) {
                            if (!sheetContext.mounted) return;
                            await showAppMessage(
                              sheetContext,
                              title: '分析失败',
                              message: '$error',
                              tone: AppMessageTone.warning,
                            );
                          }
                        },
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
    transcript.dispose();
  }

  Future<void> _showAddNote(BuildContext pageContext) async {
    final title = TextEditingController();
    final english = TextEditingController();
    final chinese = TextEditingController();
    final source = TextEditingController();

    await showCupertinoModalPopup<void>(
      context: pageContext,
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
                maxWidth: 680,
                maxHeight:
                    MediaQuery.of(sheetContext).size.height -
                    MediaQuery.of(sheetContext).viewInsets.bottom -
                    24,
              ),
              margin: const EdgeInsets.all(12),
              child: LiquidGlassSurface(
                radius: 30,
                blur: 34,
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('新建双语笔记', style: AppTextStyles.title),
                          ),
                          AppIconButton(
                            icon: CupertinoIcons.xmark,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _NoteField(
                        controller: title,
                        placeholder: '标题',
                        maxLines: 1,
                      ),
                      const SizedBox(height: 10),
                      _NoteField(
                        controller: english,
                        placeholder: 'English note',
                        minLines: 5,
                        maxLines: 8,
                      ),
                      const SizedBox(height: 10),
                      _NoteField(
                        controller: chinese,
                        placeholder: '中文笔记',
                        minLines: 5,
                        maxLines: 8,
                      ),
                      const SizedBox(height: 10),
                      _NoteField(
                        controller: source,
                        placeholder: '来源（可选）',
                        maxLines: 1,
                      ),
                      const SizedBox(height: 18),
                      AppPrimaryButton(
                        label: '保存到本机',
                        icon: CupertinoIcons.check_mark,
                        fullWidth: true,
                        onPressed: () async {
                          if (title.text.trim().isEmpty ||
                              (english.text.trim().isEmpty &&
                                  chinese.text.trim().isEmpty)) {
                            await showAppMessage(
                              sheetContext,
                              title: '内容不完整',
                              message: '请填写标题，并至少写入一种语言的内容。',
                              tone: AppMessageTone.warning,
                            );
                            return;
                          }
                          await AppScope.of(pageContext).addNote(
                            title: title.text.trim(),
                            contentEnglish: english.text.trim(),
                            contentChinese: chinese.text.trim(),
                            source: source.text.trim().isEmpty
                                ? '手动创建'
                                : source.text.trim(),
                          );
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
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

    title.dispose();
    english.dispose();
    chinese.dispose();
    source.dispose();
  }

  Future<void> _exportNotes(BuildContext context, List<StudyNote> notes) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        p.join(documents.path, 'AILearningOS Exports'),
      );
      if (!directory.existsSync()) await directory.create(recursive: true);
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
      final file = File(p.join(directory.path, 'bilingual-notes-$stamp.md'));
      final buffer = StringBuffer('# AILearningOS · 双语笔记\n\n');
      for (final note in notes) {
        buffer
          ..writeln('## ${note.title}')
          ..writeln()
          ..writeln('**Source / 来源：** ${note.source}')
          ..writeln()
          ..writeln('### English')
          ..writeln()
          ..writeln(
            note.contentEnglish.isEmpty ? '_暂无英文内容_' : note.contentEnglish,
          )
          ..writeln()
          ..writeln('### 中文')
          ..writeln()
          ..writeln(
            note.contentChinese.isEmpty ? '_暂无中文内容_' : note.contentChinese,
          )
          ..writeln()
          ..writeln('---')
          ..writeln();
      }
      await file.writeAsString(buffer.toString(), flush: true);
      if (!context.mounted) return;
      await showAppMessage(
        context,
        title: '导出完成',
        message: 'Markdown 文件已保存到：\n${file.path}',
        tone: AppMessageTone.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      await showAppMessage(
        context,
        title: '导出失败',
        message: '$error',
        tone: AppMessageTone.warning,
      );
    }
  }

  Future<void> _exportObsidianVault(
    BuildContext context,
    List<StudyNote> notes,
  ) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final vault = Directory(
        p.join(documents.path, 'AILearningOS Obsidian Vault'),
      );
      final notesDirectory = Directory(p.join(vault.path, 'Learning Notes'));
      final wordsDirectory = Directory(p.join(vault.path, 'Word Bank'));
      await notesDirectory.create(recursive: true);
      await wordsDirectory.create(recursive: true);
      for (final note in notes) {
        final fileName = '${_safeFileName(note.title)}-${note.id}.md';
        final content = StringBuffer()
          ..writeln('---')
          ..writeln('title: "${_yaml(note.title)}"')
          ..writeln('source: "${_yaml(note.source)}"')
          ..writeln('updated: ${note.updatedAt.toIso8601String()}')
          ..writeln('evidence_type: conversation_or_manual_note')
          ..writeln('ai_generated: true')
          ..writeln('tags: [ai-learning-os, bilingual-note]')
          ..writeln('---')
          ..writeln()
          ..writeln('# ${note.title}')
          ..writeln()
          ..writeln('> Source / 来源：${note.source}')
          ..writeln()
          ..writeln('## English')
          ..writeln()
          ..writeln(
            note.contentEnglish.isEmpty
                ? '_No English content_'
                : note.contentEnglish,
          )
          ..writeln()
          ..writeln('## 中文')
          ..writeln()
          ..writeln(
            note.contentChinese.isEmpty ? '_暂无中文内容_' : note.contentChinese,
          )
          ..writeln()
          ..writeln('## Links')
          ..writeln()
          ..writeln('- [[Word Bank]]')
          ..writeln('- [[Learning Dashboard]]');
        await File(
          p.join(notesDirectory.path, fileName),
        ).writeAsString(content.toString());
      }
      await File(p.join(wordsDirectory.path, 'Word Bank.md')).writeAsString(
        '# Word Bank\n\n由 AILearningOS 导出的词库入口。请从 App 的 Word Bank 页面查看完整复习数据。\n',
      );
      await File(p.join(vault.path, 'Learning Dashboard.md')).writeAsString(
        '# Learning Dashboard\n\n- [[Learning Notes]]\n- [[Word Bank/Word Bank]]\n',
      );
      if (!context.mounted) return;
      await showAppMessage(
        context,
        title: 'Obsidian 知识库已导出',
        message: '已生成可直接打开的 Vault：\n${vault.path}',
        tone: AppMessageTone.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      await showAppMessage(
        context,
        title: 'Obsidian 导出失败',
        message: '$error',
        tone: AppMessageTone.warning,
      );
    }
  }

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
    return cleaned.isEmpty ? 'learning-note' : cleaned;
  }

  String _yaml(String value) =>
      value.replaceAll('"', '\\"').replaceAll('\n', ' ');

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _ConversationSyncCard extends StatelessWidget {
  const _ConversationSyncCard();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final state = controller.conversationSyncState;
    final active = state.enabled;
    final status = !active
        ? '每日 23:00'
        : switch (state.status) {
            ConversationSyncStatus.disabled => '已关闭',
            ConversationSyncStatus.syncing => '检查中',
            ConversationSyncStatus.synced => '已同步',
            ConversationSyncStatus.error => '需要处理',
            ConversationSyncStatus.waiting => '等待新对话',
          };
    final detail =
        state.lastError != null && state.status == ConversationSyncStatus.error
        ? state.lastError!
        : state.lastSyncedTitle == null
        ? active
              ? '每 15 分钟读取一次 Bridge 收件箱，只总结按时间排序后倒数第二条对话；邮件也会自动增量摘要。'
              : '高频循环未开启；每天 23:00 读取一次 Bridge 收件箱并生成摘要。'
        : '上次已总结「${state.lastSyncedTitle}」。摘要会自动分类并写入服务器 Obsidian 知识库。';
    return AppCard(
      color: active ? AppPalette.blueSoft : AppPalette.softSurface,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final leading = Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      colors: [
                        AppPalette.resolve(context, AppPalette.blue),
                        AppPalette.resolve(context, AppPalette.purple),
                      ],
                    )
                  : null,
              color: active
                  ? null
                  : AppPalette.resolve(context, AppPalette.secondaryText),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              CupertinoIcons.sparkles,
              size: 20,
              color: Color(0xFFFFFFFF),
            ),
          );
          final statusPill = Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x20FFFFFF), width: 0.6),
            ),
            child: Text(
              status,
              style: AppTextStyles.caption.copyWith(
                color: AppPalette.resolve(
                  context,
                  state.status == ConversationSyncStatus.error
                      ? AppPalette.orange
                      : AppPalette.text,
                ),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          final description = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自动整理',
                style: AppTextStyles.sectionTitle.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: AppPalette.resolve(context, AppPalette.secondaryText),
                ),
              ),
            ],
          );
          final refresh = AppPrimaryButton(
            label: compact ? '检查' : '立即检查',
            icon: CupertinoIcons.refresh,
            filled: false,
            onPressed: controller.busy
                ? null
                : () async {
                    final result = await controller.syncChatGptConversation(
                      manual: true,
                    );
                    if (!context.mounted) return;
                    await showAppMessage(
                      context,
                      title: result.synced ? '已生成笔记' : '同步结果',
                      message: result.message,
                      tone: result.synced
                          ? AppMessageTone.success
                          : AppMessageTone.info,
                    );
                  },
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(child: description),
                  ],
                ),
                const SizedBox(height: 13),
                Row(children: [statusPill, const Spacer(), refresh]),
              ],
            );
          }

          return Row(
            children: [
              leading,
              const SizedBox(width: 13),
              Expanded(child: description),
              const SizedBox(width: 14),
              statusPill,
              const SizedBox(width: 10),
              refresh,
            ],
          );
        },
      ),
    );
  }
}

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Text('所有笔记', style: AppTextStyles.sectionTitle)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppPalette.resolve(context, AppPalette.softSurface),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: AppTextStyles.caption.copyWith(
              color: AppPalette.resolve(context, AppPalette.secondaryText),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.placeholder,
    this.minLines = 1,
    required this.maxLines,
  });

  final TextEditingController controller;
  final String placeholder;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      minLines: minLines,
      maxLines: maxLines,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppPalette.resolve(context, AppPalette.softSurface),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppPalette.resolve(context, AppPalette.separator),
          width: 0.5,
        ),
      ),
    );
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({
    required this.notes,
    required this.selectedId,
    required this.onSelected,
  });

  final List<StudyNote> notes;
  final int selectedId;
  final ValueChanged<StudyNote> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(8),
      child: ListView.separated(
        itemCount: notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final note = notes[index];
          final selected = note.id == selectedId;
          return CupertinoButton(
            padding: const EdgeInsets.all(12),
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? AppPalette.resolve(context, AppPalette.blueSoft)
                : null,
            onPressed: () => onSelected(note),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  note.contentChinese.isEmpty
                      ? note.contentEnglish
                      : note.contentChinese,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppPalette.resolve(
                      context,
                      AppPalette.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NoteDetail extends StatelessWidget {
  const _NoteDetail({required this.note, this.showCloseButton = false});

  final StudyNote note;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.fromLTRB(
        showCloseButton ? 20 : 28,
        showCloseButton ? 18 : 28,
        showCloseButton ? 20 : 28,
        showCloseButton ? 24 : 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      maxLines: showCloseButton ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SourceBadge(source: note.source),
                        Text(
                          '${note.updatedAt.month}月${note.updatedAt.day}日',
                          style: AppTextStyles.caption.copyWith(
                            color: AppPalette.resolve(
                              context,
                              AppPalette.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showCloseButton) ...[
                const SizedBox(width: 10),
                AppIconButton(
                  icon: CupertinoIcons.xmark,
                  semanticLabel: '关闭笔记',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _LanguageLabel(
                    label: 'ENGLISH',
                    color: AppPalette.blue,
                  ),
                  const SizedBox(height: 9),
                  Text(
                    note.contentEnglish.isEmpty
                        ? '暂无英文内容'
                        : note.contentEnglish,
                    style: AppTextStyles.body,
                  ),
                  const SizedBox(height: 26),
                  Container(
                    height: 0.5,
                    color: AppPalette.resolve(context, AppPalette.separator),
                  ),
                  const SizedBox(height: 26),
                  const _LanguageLabel(label: '中文', color: AppPalette.green),
                  const SizedBox(height: 9),
                  Text(
                    note.contentChinese.isEmpty
                        ? '暂无中文内容'
                        : note.contentChinese,
                    style: AppTextStyles.body,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppPalette.resolve(context, AppPalette.blueSoft),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        source,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          color: AppPalette.resolve(context, AppPalette.blue),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LanguageLabel extends StatelessWidget {
  const _LanguageLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppPalette.resolve(context, color),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _MobileNoteCard extends StatelessWidget {
  const _MobileNoteCard({required this.note, required this.compact});

  final StudyNote note;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => showCupertinoModalPopup<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 720,
                maxHeight: MediaQuery.sizeOf(context).height * 0.84,
              ),
              margin: const EdgeInsets.all(12),
              child: _NoteDetail(note: note, showCloseButton: true),
            ),
          ),
        ),
      ),
      padding: EdgeInsets.all(compact ? 14 : 18),
      radius: compact ? 17 : 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle.copyWith(
                    fontSize: compact ? 15 : null,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                CupertinoIcons.chevron_forward,
                size: compact ? 14 : 16,
                color: AppPalette.resolve(context, AppPalette.secondaryText),
              ),
            ],
          ),
          SizedBox(height: compact ? 7 : 8),
          Expanded(
            child: Text(
              note.contentChinese.isEmpty
                  ? note.contentEnglish
                  : note.contentChinese,
              maxLines: compact ? 4 : 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontSize: compact ? 13 : null,
                color: AppPalette.resolve(context, AppPalette.secondaryText),
              ),
            ),
          ),
          SizedBox(height: compact ? 7 : 10),
          Row(
            children: [
              Expanded(child: _SourceBadge(source: note.source)),
              const SizedBox(width: 8),
              Text(
                '${note.updatedAt.month}/${note.updatedAt.day}',
                style: AppTextStyles.caption.copyWith(
                  color: AppPalette.resolve(context, AppPalette.secondaryText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 36,
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
            const SizedBox(height: 10),
            const Text('还没有笔记', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 5),
            Text(
              '新建一篇中英双语笔记，所有内容会保存在本机。',
              style: AppTextStyles.body.copyWith(
                color: AppPalette.resolve(context, AppPalette.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
