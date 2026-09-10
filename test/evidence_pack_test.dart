import 'package:ai_study_os/domain/canvas_todo.dart';
import 'package:ai_study_os/domain/evidence_pack.dart';
import 'package:ai_study_os/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 10, 12);

  EvidencePack buildPack() => EvidencePack.fromLearningData(
    notes: [
      StudyNote(
        id: 1,
        userId: 7,
        title: '项目决定',
        contentEnglish: '',
        contentChinese: '学习主题：AI Learning OS\n我决定优先保存来源。',
        source: '手动 Learning Journal',
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      StudyNote(
        id: 2,
        userId: 7,
        title: '飞书总结',
        contentEnglish: '',
        contentChinese: 'AI 总结的课堂记录。',
        source: '飞书录音每日总结:2026-09-10',
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
    ],
    canvasItems: [
      CanvasTodoItem(
        id: 'a1',
        courseName: 'MEL',
        title: 'Prototype Demo',
        completed: false,
        statusLabel: '未提交',
        dueAt: now.subtract(const Duration(hours: 3)),
      ),
    ],
  );

  test('证据包保留来源、时间、关联和人机内容区分', () {
    final pack = buildPack();
    expect(pack.records, hasLength(3));
    expect(
      pack.records.singleWhere((record) => record.id == 'note:1').origin,
      EvidenceOrigin.learnerReflection,
    );
    expect(
      pack.records.singleWhere((record) => record.id == 'note:2').origin,
      EvidenceOrigin.aiGenerated,
    );
    final canvas = pack.records.singleWhere(
      (record) => record.id == 'canvas:a1',
    );
    expect(canvas.origin, EvidenceOrigin.original);
    expect(canvas.relation, '课程任务');
    expect(canvas.project, 'MEL');
  });

  test('角色视图不向 Coach 和 MEL 暴露未确认 AI 摘要', () {
    final pack = buildPack();
    expect(pack.query(role: EvidenceRole.learner), hasLength(3));
    expect(pack.query(role: EvidenceRole.coach), hasLength(2));
    expect(pack.query(role: EvidenceRole.mel), hasLength(2));
    expect(
      pack
          .query(role: EvidenceRole.coach)
          .any((record) => record.title == '飞书总结'),
      isFalse,
    );
  });

  test('查无证据时返回空结果，不生成推断', () {
    final pack = buildPack();
    expect(pack.query(text: '不存在的证据'), isEmpty);
  });

  test('学生确认复盘包含来源索引和未知边界', () {
    final pack = buildPack();
    final review = pack.confirmedReview(EvidencePeriod.weekly, now: now);
    expect(review, contains('# Weekly Review'));
    expect(review, contains('来源：Canvas 作业与提交状态'));
    expect(review, contains('学生状态：已检查并确认'));
    expect(review, contains('这不代表不存在未记录的问题'));
  });
}
