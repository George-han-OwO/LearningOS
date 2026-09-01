import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import '../../domain/security_policy.dart';

class SafetyPage extends StatelessWidget {
  const SafetyPage({this.showBackButton = false, this.onBack, super.key});

  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final security = controller.loginSecurity;
    final remaining = security.remainingAt(DateTime.now());
    final locked = remaining > Duration.zero;

    return AppPage(
      title: '安全防炸',
      subtitle: '防密码爆破、恶意请求与 DDoS 的分层保护',
      actions: [
        if (showBackButton)
          AppIconButton(
            icon: CupertinoIcons.back,
            semanticLabel: '返回',
            onPressed: onBack,
          ),
      ],
      child: Column(
        children: [
          _LocalSurfaceHero(locked: locked, remaining: remaining),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final active = _ActiveProtection(
                failedAttempts: security.failedAttempts,
                locked: locked,
                remaining: remaining,
              );
              const deployment = _DeploymentProtection();
              if (constraints.maxWidth >= 760) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: active),
                    const SizedBox(width: 16),
                    const Expanded(child: deployment),
                  ],
                );
              }
              return Column(
                children: [active, const SizedBox(height: 16), deployment],
              );
            },
          ),
          const SizedBox(height: 16),
          const _DdosBoundaryNotice(),
        ],
      ),
    );
  }
}

class _LocalSurfaceHero extends StatelessWidget {
  const _LocalSurfaceHero({required this.locked, required this.remaining});

  final bool locked;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: locked ? AppPalette.orangeSoft : AppPalette.greenSoft,
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppPalette.resolve(
                context,
                locked ? AppPalette.orangeSoft : AppPalette.raisedSurface,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Icon(
              locked
                  ? CupertinoIcons.lock_shield_fill
                  : CupertinoIcons.shield_fill,
              size: 31,
              color: AppPalette.resolve(
                context,
                locked ? AppPalette.orange : AppPalette.green,
              ),
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locked ? '登录保护正在锁定' : '本地攻击面已收紧',
                  style: AppTextStyles.title,
                ),
                const SizedBox(height: 6),
                Text(
                  locked
                      ? '剩余 ${SecurityPolicy.formatRemaining(remaining)}，期间拒绝继续验证密码。'
                      : '当前版本不监听公网端口；学习数据与账号认证只在设备本地运行。',
                  style: AppTextStyles.body.copyWith(
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
    );
  }
}

class _ActiveProtection extends StatelessWidget {
  const _ActiveProtection({
    this.failedAttempts = 0,
    this.locked = false,
    this.remaining = Duration.zero,
  });

  final int failedAttempts;
  final bool locked;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return AppGroup(
      title: '当前已经启用',
      children: [
        AppGroupRow(
          icon: CupertinoIcons.lock_shield_fill,
          title: '登录防爆破',
          subtitle: locked
              ? '已触发指数退避，剩余 ${SecurityPolicy.formatRemaining(remaining)}'
              : '失败 $failedAttempts 次 · 第 3 次起指数退避，最长锁定 15 分钟',
          tint: AppPalette.green,
          tintBackground: AppPalette.greenSoft,
          trailing: _StatusPill(
            label: locked ? '锁定中' : '已开启',
            color: locked ? AppPalette.orange : AppPalette.green,
            background: locked ? AppPalette.orangeSoft : AppPalette.greenSoft,
          ),
        ),
        const AppGroupRow(
          icon: CupertinoIcons.number_square_fill,
          title: '密码安全存储',
          subtitle: 'PBKDF2-HMAC-SHA256 · 120,000 次迭代 · 随机盐',
          tint: AppPalette.blue,
          tintBackground: AppPalette.blueSoft,
        ),
        const AppGroupRow(
          icon: CupertinoIcons.text_badge_plus,
          title: '输入体积限制',
          subtitle: '资料单文件 25 MB；Word Bank 单次 100,000 字符',
          tint: AppPalette.purple,
          tintBackground: AppPalette.softSurface,
        ),
        const AppGroupRow(
          icon: CupertinoIcons.device_phone_portrait,
          title: 'Local First',
          subtitle: '无公开监听端口，不把 SQLite、密码或原始资料暴露到公网',
          tint: AppPalette.green,
          tintBackground: AppPalette.greenSoft,
        ),
      ],
    );
  }
}

class _DeploymentProtection extends StatelessWidget {
  const _DeploymentProtection();

  @override
  Widget build(BuildContext context) {
    return AppGroup(
      title: '接入云端时必须部署',
      children: const [
        AppGroupRow(
          icon: CupertinoIcons.cloud_fill,
          title: 'CDN / Anycast / DDoS 清洗',
          subtitle: '在流量到达源站前吸收大规模网络层与传输层攻击',
          tint: AppPalette.blue,
          tintBackground: AppPalette.blueSoft,
        ),
        AppGroupRow(
          icon: CupertinoIcons.shield_lefthalf_fill,
          title: 'WAF 与 API Gateway',
          subtitle: 'IP、账号、设备三维限流；请求体限制；恶意模式拦截',
          tint: AppPalette.orange,
          tintBackground: AppPalette.orangeSoft,
        ),
        AppGroupRow(
          icon: CupertinoIcons.speedometer,
          title: '令牌桶与并发上限',
          subtitle: '昂贵的 OCR / AI 请求单独配额、排队、超时和熔断',
          tint: AppPalette.purple,
          tintBackground: AppPalette.softSurface,
        ),
        AppGroupRow(
          icon: CupertinoIcons.eye_fill,
          title: '监控与自动封禁',
          subtitle: '异常 QPS、登录失败率、成本突增告警和短期黑名单',
          tint: AppPalette.red,
          tintBackground: AppPalette.redSoft,
        ),
      ],
    );
  }
}

class _DdosBoundaryNotice extends StatelessWidget {
  const _DdosBoundaryNotice();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppPalette.orangeSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: AppPalette.resolve(context, AppPalette.orange),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'DDoS 不能靠 APK 或 EXE 单独抵挡。当前本地版没有公网服务，因此没有可被网络洪泛的源站；未来一旦增加账号云同步、OCR 或 AI 网关，必须把源站藏在 CDN/WAF 后并实施服务端限流。',
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
