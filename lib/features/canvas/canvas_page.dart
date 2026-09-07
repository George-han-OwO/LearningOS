import 'package:flutter/cupertino.dart';

import '../../core/app_controller.dart';
import '../../design/app_widgets.dart';

class CanvasPage extends StatefulWidget {
  const CanvasPage({required this.controller, super.key});
  final AppController controller;

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  Map<String, dynamic> _connection = {};
  final List<Map<String, dynamic>> _courses = [];
  final List<Map<String, dynamic>> _assignments = [];
  Map<String, dynamic>? _course;
  String? _courseCursor;
  String? _assignmentCursor;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _run(() async {
      _connection = await widget.controller.canvasConnection();
      if (!mounted) return;
      _url.text = _connection['base_url'] as String? ?? '';
      if (_connection['connected'] == true) await _loadCourses();
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _error = error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> value) =>
      (value['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Future<void> _loadCourses({bool more = false}) async {
    final page = await widget.controller.canvasCourses(
      cursor: more ? _courseCursor : null,
    );
    if (!mounted) return;
    if (!more) {
      _courses.clear();
      _course = null;
      _assignments.clear();
    }
    final ids = _courses.map((item) => item['id']).toSet();
    _courses.addAll(_items(page).where((item) => ids.add(item['id'])));
    _courseCursor = page['next_cursor'] as String?;
  }

  Future<void> _loadAssignments(
    Map<String, dynamic> course, {
    bool more = false,
  }) async {
    final page = await widget.controller.canvasAssignments(
      course['id'].toString(),
      cursor: more ? _assignmentCursor : null,
    );
    if (!mounted) return;
    _course = course;
    if (!more) _assignments.clear();
    final ids = _assignments.map((item) => item['id']).toSet();
    _assignments.addAll(_items(page).where((item) => ids.add(item['id'])));
    _assignmentCursor = page['next_cursor'] as String?;
  }

  Future<void> _connect() => _run(() async {
    final result = await widget.controller.connectCanvas(
      _url.text,
      _token.text,
    );
    if (!mounted) return;
    _token.clear();
    _connection = result;
    _courses.clear();
    _assignments.clear();
    _course = null;
    _courseCursor = null;
    _assignmentCursor = null;
    await _loadCourses();
  });

  Future<void> _disconnect() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('断开 Canvas？'),
        content: const Text(
          '将删除 AILearningOS 保存的 Canvas 连接。学校 Canvas 中的课程和作业不受影响。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await widget.controller.disconnectCanvas();
      if (!mounted) return;
      _connection = {};
      _courses.clear();
      _assignments.clear();
      _course = null;
      _courseCursor = null;
      _assignmentCursor = null;
      _token.clear();
    });
  }

  String _due(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '未设置截止时间';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _status(Map item) {
    final submission = item['submission'];
    if (submission is! Map) return '提交状态未提供';
    final state = switch (submission['workflow_state']) {
      'submitted' => '已提交',
      'graded' => '已评分',
      'pending_review' => '待审核',
      'unsubmitted' => '未提交',
      _ => '状态未提供',
    };
    return [
      state,
      if (submission['missing'] == true) '缺交',
      if (submission['late'] == true) '迟交',
      if (submission['score'] != null) '得分 ${submission['score']}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final profile = _connection['profile'];
    final connected = _connection['connected'] == true;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Canvas 课程')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('连接学校 Canvas，查看课程、作业与截止时间。'),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (connected)
                    Text('已连接：${profile is Map ? profile['name'] : ''}'),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: _url,
                    enabled: !_busy,
                    placeholder: 'https://学校名称.instructure.com',
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    padding: const EdgeInsets.all(12),
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: _token,
                    enabled: !_busy,
                    placeholder: connected ? '更换连接时填写新令牌' : 'Canvas 访问令牌',
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    padding: const EdgeInsets.all(12),
                  ),
                  const SizedBox(height: 8),
                  const Text('令牌由后端加密保存。此入口用于连接你自己的 Canvas 账号。'),
                  const SizedBox(height: 12),
                  CupertinoButton.filled(
                    onPressed: _busy ? null : _connect,
                    child: Text(connected ? '验证并更新连接' : '验证并连接'),
                  ),
                  if (connected)
                    CupertinoButton(
                      onPressed: _busy ? null : _disconnect,
                      child: const Text('断开连接'),
                    ),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CupertinoActivityIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ),
            if (connected) ...[
              CupertinoButton(
                onPressed: _busy ? null : () => _run(() => _loadCourses()),
                child: const Text('刷新课程'),
              ),
              if (!_busy && _courses.isEmpty && _error == null)
                const Text('当前没有可读取的在读课程。'),
              for (final course in _courses)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onPressed: _busy
                      ? null
                      : () => _run(() => _loadAssignments(course)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${course['name'] ?? course['course_code'] ?? '课程'} →',
                    ),
                  ),
                ),
              if (_courseCursor != null)
                CupertinoButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _loadCourses(more: true)),
                  child: const Text('加载更多课程'),
                ),
              if (_course != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${_course!['name'] ?? '课程'} · 作业',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_assignments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('此课程暂无可读取的作业。'),
                  ),
                for (final assignment in _assignments)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${assignment['name'] ?? '未命名作业'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text('截止：${_due(assignment['due_at'])}'),
                          Text(_status(assignment)),
                          if (assignment['points_possible'] != null)
                            Text('满分：${assignment['points_possible']}'),
                        ],
                      ),
                    ),
                  ),
                if (_assignmentCursor != null)
                  CupertinoButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => _loadAssignments(_course!, more: true),
                          ),
                    child: const Text('加载更多作业'),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
