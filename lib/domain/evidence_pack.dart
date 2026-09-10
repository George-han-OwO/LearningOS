import 'canvas_todo.dart';
import 'models.dart';

enum EvidenceOrigin { original, learnerReflection, aiGenerated, unknown }

enum EvidenceRole { learner, coach, mel }

enum EvidencePeriod { daily, weekly, monthly }

extension EvidenceOriginLabel on EvidenceOrigin {
  String get label => switch (this) {
    EvidenceOrigin.original => '原始记录',
    EvidenceOrigin.learnerReflection => '学生解释 / 反思',
    EvidenceOrigin.aiGenerated => 'AI 生成',
    EvidenceOrigin.unknown => '待确认',
  };
}

extension EvidenceRoleLabel on EvidenceRole {
  String get label => switch (this) {
    EvidenceRole.learner => 'Learner',
    EvidenceRole.coach => 'Coach',
    EvidenceRole.mel => 'MEL',
  };

  String get scope => switch (this) {
    EvidenceRole.learner => '个人记录、反馈、决定、作品版本和复盘',
    EvidenceRole.coach => '课程进度与学生已确认的反思；不显示原始录音或未确认 AI 内容',
    EvidenceRole.mel => '项目/课程目标、任务进展、状态证据和已确认的项目反思',
  };
}

extension EvidencePeriodLabel on EvidencePeriod {
  String get label => switch (this) {
    EvidencePeriod.daily => 'Daily',
    EvidencePeriod.weekly => 'Weekly',
    EvidencePeriod.monthly => 'Monthly',
  };

  Duration get duration => switch (this) {
    EvidencePeriod.daily => const Duration(days: 1),
    EvidencePeriod.weekly => const Duration(days: 7),
    EvidencePeriod.monthly => const Duration(days: 30),
  };
}

class EvidenceRecord {
  const EvidenceRecord({
    required this.id,
    required this.title,
    required this.content,
    required this.source,
    required this.occurredAt,
    required this.origin,
    required this.relation,
    required this.project,
    required this.studentConfirmed,
    this.status,
  });

  final String id;
  final String title;
  final String content;
  final String source;
  final DateTime occurredAt;
  final EvidenceOrigin origin;
  final String relation;
  final String project;
  final bool studentConfirmed;
  final String? status;

  bool visibleTo(EvidenceRole role) => switch (role) {
    EvidenceRole.learner => true,
    EvidenceRole.coach =>
      relation == '课程任务' ||
          (origin == EvidenceOrigin.learnerReflection && studentConfirmed),
    EvidenceRole.mel =>
      relation == '课程任务' ||
          (origin == EvidenceOrigin.learnerReflection &&
              studentConfirmed &&
              project.trim().isNotEmpty),
  };

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return '$title\n$content\n$source\n$relation\n$project\n${status ?? ''}'
        .toLowerCase()
        .contains(normalized);
  }

  factory EvidenceRecord.fromNote(StudyNote note) {
    final source = note.source.trim();
    final content = note.contentChinese.trim().isNotEmpty
        ? note.contentChinese.trim()
        : note.contentEnglish.trim();
    final lower = source.toLowerCase();
    final manual = lower.contains('手动') || lower.contains('学生确认');
    final ai =
        lower.contains('ai') ||
        lower.contains('codex') ||
        lower.contains('deepseek') ||
        source.startsWith('飞书录音每日总结');
    final original =
        source.startsWith('飞书录音原稿') ||
        lower.contains('原稿') ||
        lower.contains('原始');
    final project = _projectFrom(note.title, source, content);
    return EvidenceRecord(
      id: 'note:${note.id}',
      title: note.title,
      content: content,
      source: source.isEmpty ? '未记录来源' : source,
      occurredAt: note.updatedAt,
      origin: manual
          ? EvidenceOrigin.learnerReflection
          : (original
                ? EvidenceOrigin.original
                : (ai ? EvidenceOrigin.aiGenerated : EvidenceOrigin.unknown)),
      relation: _relationFrom(content, source),
      project: project,
      studentConfirmed: manual || lower.contains('学生确认'),
    );
  }

  factory EvidenceRecord.fromCanvas(CanvasTodoItem item) {
    final score = item.score == null
        ? ''
        : '；得分 ${item.score}/${item.pointsPossible ?? '—'}';
    final due = item.dueAt == null ? '未设置截止时间' : '截止 ${_dateTime(item.dueAt!)}';
    return EvidenceRecord(
      id: 'canvas:${item.id}',
      title: item.title,
      content: '${item.courseName}；$due；${item.statusLabel}$score',
      source: 'Canvas 作业与提交状态',
      occurredAt: item.submittedAt ?? item.dueAt ?? DateTime.now(),
      origin: EvidenceOrigin.original,
      relation: '课程任务',
      project: item.courseName,
      studentConfirmed: true,
      status: item.statusLabel,
    );
  }

  static String _relationFrom(String content, String source) {
    final value = '$source\n$content'.toLowerCase();
    if (value.contains('反馈') || value.contains('feedback')) return '反馈';
    if (value.contains('决定') || value.contains('取舍')) return '决定';
    if (value.contains('版本') || value.contains('version')) return '作品版本';
    if (value.contains('行动') || value.contains('下一步')) return '行动';
    if (source.startsWith('飞书录音')) return '线下交流';
    return '学习记录';
  }

  static String _projectFrom(String title, String source, String content) {
    final match = RegExp(
      r'(?:项目|课程|主题)：\s*([^\n；;]+)',
      caseSensitive: false,
    ).firstMatch('$title\n$source\n$content');
    return match?.group(1)?.trim() ?? '';
  }

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class EvidencePack {
  EvidencePack({required List<EvidenceRecord> records})
    : records = List.unmodifiable(
        [...records]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)),
      );

  factory EvidencePack.fromLearningData({
    required Iterable<StudyNote> notes,
    required Iterable<CanvasTodoItem> canvasItems,
  }) => EvidencePack(
    records: [
      for (final note in notes) EvidenceRecord.fromNote(note),
      for (final item in canvasItems) EvidenceRecord.fromCanvas(item),
    ],
  );

  final List<EvidenceRecord> records;

  List<EvidenceRecord> query({
    EvidenceRole role = EvidenceRole.learner,
    EvidenceOrigin? origin,
    String text = '',
  }) => records
      .where((record) => record.visibleTo(role))
      .where((record) => origin == null || record.origin == origin)
      .where((record) => record.matches(text))
      .toList(growable: false);

  List<EvidenceRecord> forPeriod(EvidencePeriod period, {DateTime? now}) {
    final end = now ?? DateTime.now();
    final start = end.subtract(period.duration);
    return records
        .where(
          (record) =>
              !record.occurredAt.isBefore(start) &&
              !record.occurredAt.isAfter(end),
        )
        .toList(growable: false);
  }

  String confirmedReview(EvidencePeriod period, {DateTime? now}) {
    final end = now ?? DateTime.now();
    final selected = forPeriod(period, now: end);
    final label = period.label;
    final date = _date(end);
    if (selected.isEmpty) {
      return '# $label Review\n\n- 日期：$date\n- 证据：0 条\n\n当前证据包没有这一周期的记录，因此不知道具体发生了什么。';
    }
    final lines = selected
        .take(12)
        .map((record) {
          final project = record.project.isEmpty ? '' : ' · ${record.project}';
          return '- ${_date(record.occurredAt)} · ${record.origin.label} · ${record.title}$project'
              '\n  来源：${record.source}';
        })
        .join('\n');
    final unresolved = selected.where(
      (record) =>
          record.status?.contains('未提交') == true ||
          record.status?.contains('缺交') == true ||
          record.origin == EvidenceOrigin.unknown ||
          (record.origin == EvidenceOrigin.aiGenerated &&
              !record.studentConfirmed),
    );
    return '# $label Review\n\n'
        '- 日期：$date\n'
        '- 证据：${selected.length} 条\n'
        '- 学生状态：已检查并确认\n\n'
        '## 证据索引\n\n$lines\n\n'
        '## 待处理 / 未知\n\n'
        '${unresolved.isEmpty ? '- 未发现明确阻塞。' : unresolved.map((record) => '- ${record.title}：${record.status ?? '需要学生确认内容是否准确'}').join('\n')}\n'
        '- 这不代表不存在未记录的问题。\n\n'
        '## 学生反思\n\n- 请在此处用自己的话补充：哪些改变最重要？下一步是什么？';
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
