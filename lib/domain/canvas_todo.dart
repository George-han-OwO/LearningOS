class CanvasTodoItem {
  const CanvasTodoItem({
    required this.id,
    required this.courseName,
    required this.title,
    required this.completed,
    required this.statusLabel,
    this.dueAt,
    this.submittedAt,
    this.missing = false,
    this.late = false,
    this.score,
    this.pointsPossible,
    this.htmlUrl,
  });

  final String id;
  final String courseName;
  final String title;
  final DateTime? dueAt;
  final DateTime? submittedAt;
  final bool completed;
  final bool missing;
  final bool late;
  final num? score;
  final num? pointsPossible;
  final String? htmlUrl;
  final String statusLabel;

  bool get overdue =>
      !completed && dueAt != null && dueAt!.isBefore(DateTime.now());

  factory CanvasTodoItem.fromApi({
    required Map<String, dynamic> assignment,
    required String courseName,
  }) {
    final rawSubmission = assignment['submission'];
    final submission = rawSubmission is Map
        ? Map<String, dynamic>.from(rawSubmission)
        : const <String, dynamic>{};
    final workflow = submission['workflow_state']?.toString() ?? '';
    final submittedAt = DateTime.tryParse(
      submission['submitted_at']?.toString() ?? '',
    )?.toLocal();
    final completed =
        const {'submitted', 'graded', 'pending_review'}.contains(workflow) ||
        submittedAt != null;
    final missing = submission['missing'] == true;
    final late = submission['late'] == true;
    final status = switch (workflow) {
      'submitted' => '已提交',
      'graded' => '已评分',
      'pending_review' => '待评审',
      'unsubmitted' => missing ? '缺交' : '未提交',
      _ => missing ? '缺交' : (completed ? '已提交' : '未提交'),
    };
    return CanvasTodoItem(
      id: assignment['id']?.toString() ?? '',
      courseName: courseName.trim().isEmpty ? 'Canvas 课程' : courseName,
      title: assignment['name']?.toString().trim().isNotEmpty == true
          ? assignment['name'].toString().trim()
          : '未命名作业',
      dueAt: DateTime.tryParse(
        assignment['due_at']?.toString() ?? '',
      )?.toLocal(),
      submittedAt: submittedAt,
      completed: completed,
      missing: missing,
      late: late,
      score: _asNum(submission['score']),
      pointsPossible: _asNum(assignment['points_possible']),
      htmlUrl: assignment['html_url']?.toString(),
      statusLabel: [
        status,
        if (late) '迟交',
        if (submission['score'] != null) '得分 ${submission['score']}',
      ].join(' · '),
    );
  }

  static num? _asNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }
}

class CanvasTodoState {
  const CanvasTodoState({
    required this.connected,
    required this.loading,
    required this.items,
    this.profileName,
    this.error,
    this.refreshedAt,
  });

  const CanvasTodoState.initial()
    : connected = false,
      loading = false,
      items = const [],
      profileName = null,
      error = null,
      refreshedAt = null;

  final bool connected;
  final bool loading;
  final List<CanvasTodoItem> items;
  final String? profileName;
  final String? error;
  final DateTime? refreshedAt;

  List<CanvasTodoItem> get pending =>
      items.where((item) => !item.completed).toList(growable: false)
        ..sort(_pendingOrder);

  List<CanvasTodoItem> get completed =>
      items.where((item) => item.completed).toList(growable: false)
        ..sort(_completedOrder);

  static int _pendingOrder(CanvasTodoItem left, CanvasTodoItem right) {
    if (left.dueAt == null && right.dueAt == null) {
      return left.title.compareTo(right.title);
    }
    if (left.dueAt == null) return 1;
    if (right.dueAt == null) return -1;
    return left.dueAt!.compareTo(right.dueAt!);
  }

  static int _completedOrder(CanvasTodoItem left, CanvasTodoItem right) {
    final leftDate = left.submittedAt ?? left.dueAt;
    final rightDate = right.submittedAt ?? right.dueAt;
    if (leftDate == null && rightDate == null) {
      return left.title.compareTo(right.title);
    }
    if (leftDate == null) return 1;
    if (rightDate == null) return -1;
    return rightDate.compareTo(leftDate);
  }
}
