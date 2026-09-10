import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/evidence_pack.dart';

class EvidencePackPage extends StatefulWidget {
  const EvidencePackPage({super.key});

  @override
  State<EvidencePackPage> createState() => _EvidencePackPageState();
}

class _EvidencePackPageState extends State<EvidencePackPage> {
  final _search = TextEditingController();
  EvidenceRole _role = EvidenceRole.learner;
  EvidenceOrigin? _origin;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final pack = EvidencePack.fromLearningData(
      notes: controller.notes,
      canvasItems: controller.canvasTodoState.items,
    );
    final results = pack.query(
      role: _role,
      origin: _origin,
      text: _search.text,
    );
    return AppPage(
      title: 'Evidence Pack',
      subtitle: '来源可追溯的学习证据 · ${pack.records.length} 条',
      actions: [
        AppIconButton(
          key: const ValueKey('evidence-back'),
          icon: CupertinoIcons.chevron_back,
          semanticLabel: '返回 Learning Journal',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      mobileActions: [
        AppIconButton(
          key: const ValueKey('evidence-back'),
          icon: CupertinoIcons.chevron_back,
          semanticLabel: '返回 Learning Journal',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleLens(
            role: _role,
            onChanged: (value) => setState(() => _role = value),
          ),
          const SizedBox(height: 14),
          _ReviewStudio(pack: pack),
          const SizedBox(height: 20),
          CupertinoSearchTextField(
            key: const ValueKey('evidence-search'),
            controller: _search,
            placeholder: '搜索课程、项目、反馈、决定或来源',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: '全部',
                  selected: _origin == null,
                  onPressed: () => setState(() => _origin = null),
                ),
                for (final origin in EvidenceOrigin.values) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: origin.label,
                    selected: _origin == origin,
                    onPressed: () => setState(() => _origin = origin),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_role.label} 视图 · ${results.length} 条',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              Text(
                '本机授权预览',
                style: AppTextStyles.caption.copyWith(
                  color: AppPalette.resolve(context, AppPalette.secondaryText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (results.isEmpty)
            _UnknownResult(query: _search.text)
          else
            for (final record in results) ...[
              _EvidenceCard(record: record),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _RoleLens extends StatelessWidget {
  const _RoleLens({required this.role, required this.onChanged});

  final EvidenceRole role;
  final ValueChanged<EvidenceRole> onChanged;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(CupertinoIcons.person_2_fill, size: 20),
            SizedBox(width: 9),
            Text('角色查询', style: AppTextStyles.sectionTitle),
          ],
        ),
        const SizedBox(height: 12),
        CupertinoSlidingSegmentedControl<EvidenceRole>(
          groupValue: role,
          children: {
            for (final value in EvidenceRole.values)
              value: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(value.label),
              ),
          },
          onValueChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
        const SizedBox(height: 11),
        Text(
          role.scope,
          style: AppTextStyles.caption.copyWith(
            color: AppPalette.resolve(context, AppPalette.secondaryText),
          ),
        ),
      ],
    ),
  );
}

class _ReviewStudio extends StatelessWidget {
  const _ReviewStudio({required this.pack});

  final EvidencePack pack;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(CupertinoIcons.clock_fill, size: 20),
            SizedBox(width: 9),
            Text('周期复盘', style: AppTextStyles.sectionTitle),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '先生成可追溯证据索引，由你检查、修正并确认后才保存。',
          style: AppTextStyles.caption.copyWith(
            color: AppPalette.resolve(context, AppPalette.secondaryText),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in EvidencePeriod.values)
              AppPrimaryButton(
                key: ValueKey('review-${period.label.toLowerCase()}'),
                label: '${period.label} · ${pack.forPeriod(period).length}',
                icon: CupertinoIcons.doc_text_search,
                filled: false,
                onPressed: () => _openReview(context, period),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _openReview(
    BuildContext pageContext,
    EvidencePeriod period,
  ) async {
    final controller = TextEditingController(
      text: pack.confirmedReview(period),
    );
    await showCupertinoModalPopup<void>(
      context: pageContext,
      barrierColor: const Color(0xB8000000),
      builder: (sheetContext) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.sizeOf(sheetContext).height - 24,
            ),
            margin: const EdgeInsets.all(12),
            child: LiquidGlassSurface(
              radius: 26,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${period.label} Review',
                          style: AppTextStyles.title,
                        ),
                      ),
                      AppIconButton(
                        icon: CupertinoIcons.xmark,
                        semanticLabel: '关闭',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '这是证据索引草稿，不会在未点击确认时冒充你的反思。',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: CupertinoTextField(
                      key: const ValueKey('review-editor'),
                      controller: controller,
                      minLines: 14,
                      maxLines: 28,
                      padding: const EdgeInsets.all(14),
                      style: AppTextStyles.caption.copyWith(
                        fontFamily: 'monospace',
                        height: 1.55,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.resolve(
                          sheetContext,
                          AppPalette.softSurface,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppPrimaryButton(
                    key: const ValueKey('confirm-review'),
                    label: '我已检查，确认并保存',
                    icon: CupertinoIcons.check_mark_circled_solid,
                    fullWidth: true,
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      await AppScope.of(pageContext).addNote(
                        title: '${period.label} Review · ${_today()}',
                        contentEnglish: '',
                        contentChinese: text,
                        source: '学生确认 · ${period.label} Review',
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
    );
    controller.dispose();
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    minimumSize: const Size(0, 34),
    borderRadius: BorderRadius.circular(18),
    color: selected
        ? AppPalette.resolve(context, AppPalette.blue)
        : AppPalette.resolve(context, AppPalette.softSurface),
    onPressed: onPressed,
    child: Text(
      label,
      style: TextStyle(
        color: selected
            ? const Color(0xFFFFFFFF)
            : AppPalette.resolve(context, AppPalette.text),
        fontSize: 13,
      ),
    ),
  );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.record});

  final EvidenceRecord record;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: () => Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => _EvidenceDetailPage(record: record),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _originColor(context, record.origin, soft: true),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _originIcon(record.origin),
                size: 19,
                color: _originColor(context, record.origin),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.title, style: AppTextStyles.sectionTitle),
                  const SizedBox(height: 3),
                  Text(
                    '${_dateTime(record.occurredAt)} · ${record.source}',
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
            ),
            const Icon(CupertinoIcons.chevron_forward, size: 15),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: [
            _EvidenceBadge(label: record.origin.label),
            _EvidenceBadge(label: '关联：${record.relation}'),
            if (record.project.isNotEmpty)
              _EvidenceBadge(label: '项目：${record.project}'),
            if (record.studentConfirmed)
              const _EvidenceBadge(label: '学生已确认', positive: true),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          record.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body,
        ),
      ],
    ),
  );
}

class _EvidenceBadge extends StatelessWidget {
  const _EvidenceBadge({required this.label, this.positive = false});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppPalette.resolve(
        context,
        positive ? AppPalette.greenSoft : AppPalette.softSurface,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: AppTextStyles.caption),
  );
}

class _UnknownResult extends StatelessWidget {
  const _UnknownResult({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(CupertinoIcons.question_circle, size: 34),
          const SizedBox(height: 10),
          Text('不知道', style: AppTextStyles.title.copyWith(fontSize: 20)),
          const SizedBox(height: 6),
          Text(
            query.trim().isEmpty
                ? '当前角色权限内没有可见证据。'
                : '证据包中没有找到“${query.trim()}”，不会用 AI 推断冒充事实。',
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

class _EvidenceDetailPage extends StatelessWidget {
  const _EvidenceDetailPage({required this.record});

  final EvidenceRecord record;

  @override
  Widget build(BuildContext context) => AppPage(
    title: record.title,
    subtitle: '${record.origin.label} · ${_dateTime(record.occurredAt)}',
    actions: [
      AppIconButton(
        icon: CupertinoIcons.chevron_back,
        semanticLabel: '返回证据包',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
    mobileActions: [
      AppIconButton(
        icon: CupertinoIcons.chevron_back,
        semanticLabel: '返回证据包',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Meta(label: '来源', value: record.source),
              _Meta(label: '时间', value: _dateTime(record.occurredAt)),
              _Meta(label: '记录类型', value: record.origin.label),
              _Meta(label: '关联', value: record.relation),
              if (record.project.isNotEmpty)
                _Meta(label: '项目 / 课程', value: record.project),
              _Meta(
                label: '学生确认',
                value: record.studentConfirmed ? '已确认' : '未确认，不能当作学生观点',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Text(
            record.content,
            style: AppTextStyles.body.copyWith(height: 1.6),
          ),
        ),
      ],
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppPalette.resolve(context, AppPalette.secondaryText),
            ),
          ),
        ),
        Expanded(child: Text(value, style: AppTextStyles.body)),
      ],
    ),
  );
}

IconData _originIcon(EvidenceOrigin origin) => switch (origin) {
  EvidenceOrigin.original => CupertinoIcons.doc_text_search,
  EvidenceOrigin.learnerReflection =>
    CupertinoIcons.person_crop_circle_badge_checkmark,
  EvidenceOrigin.aiGenerated => CupertinoIcons.sparkles,
  EvidenceOrigin.unknown => CupertinoIcons.question_circle,
};

Color _originColor(
  BuildContext context,
  EvidenceOrigin origin, {
  bool soft = false,
}) => AppPalette.resolve(context, switch ((origin, soft)) {
  (EvidenceOrigin.original, false) => AppPalette.blue,
  (EvidenceOrigin.original, true) => AppPalette.blueSoft,
  (EvidenceOrigin.learnerReflection, false) => AppPalette.green,
  (EvidenceOrigin.learnerReflection, true) => AppPalette.greenSoft,
  (EvidenceOrigin.aiGenerated, false) => AppPalette.purple,
  (EvidenceOrigin.aiGenerated, true) => AppPalette.purpleSoft,
  (EvidenceOrigin.unknown, false) => AppPalette.orange,
  (EvidenceOrigin.unknown, true) => AppPalette.orangeSoft,
});

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
