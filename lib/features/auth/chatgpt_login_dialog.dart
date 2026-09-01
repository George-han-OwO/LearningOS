import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/codex/chatgpt_auth_service.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';

/// Presents the short-lived challenge returned by Codex App Server.
///
/// The callback intentionally receives only a URL/device code. The OAuth
/// credentials stay inside Codex App Server and never pass through Flutter.
Future<void> presentChatGptLoginChallenge(
  BuildContext context,
  ChatGptLoginChallenge challenge,
) async {
  final authUrl = challenge.authUrl;
  if (authUrl != null) {
    final launched = await launchUrl(
      authUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('无法打开系统浏览器，请复制登录链接后重试。');
    }
    if (!context.mounted) return;
    await _showChallengeSheet(
      context,
      title: '已打开 ChatGPT 登录',
      description: '请在浏览器中完成登录和授权。完成后回到这里，应用会自动确认登录状态。',
      url: authUrl.toString(),
      primaryLabel: '知道了',
    );
    return;
  }

  final verificationUrl = challenge.verificationUrl;
  final userCode = challenge.userCode;
  if (verificationUrl != null && userCode != null) {
    await _showChallengeSheet(
      context,
      title: '使用设备码登录 ChatGPT',
      description: '打开下面的地址，输入设备码并完成授权。授权完成后返回应用即可。',
      url: verificationUrl.toString(),
      code: userCode,
      primaryLabel: '完成后继续',
      onOpenUrl: () async {
        await launchUrl(verificationUrl, mode: LaunchMode.externalApplication);
      },
    );
    return;
  }

  throw StateError('Codex 返回了无法识别的登录挑战。');
}

Future<void> _showChallengeSheet(
  BuildContext context, {
  required String title,
  required String description,
  required String url,
  required String primaryLabel,
  String? code,
  Future<void> Function()? onOpenUrl,
}) async {
  await showCupertinoModalPopup<void>(
    context: context,
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
              maxWidth: 620,
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
                            'ChatGPT 登录 · chatgpt5.5',
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
                      title,
                      style: AppTextStyles.largeTitle.copyWith(
                        color: const Color(0xFFFFFFFF),
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: AppTextStyles.body.copyWith(
                        color: const Color(0xE6FFFFFF),
                      ),
                    ),
                    if (code != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        code,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _CopyableLink(url: url),
                    const SizedBox(height: 18),
                    if (onOpenUrl != null) ...[
                      AppPrimaryButton(
                        label: '打开验证页面',
                        icon: CupertinoIcons.arrow_up_right,
                        fullWidth: true,
                        onPressed: () async {
                          try {
                            await onOpenUrl();
                          } catch (_) {
                            // The parent flow will surface the final login
                            // result. Keeping this button non-fatal lets the
                            // user copy the URL manually.
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    AppPrimaryButton(
                      label: primaryLabel,
                      fullWidth: true,
                      filled: false,
                      onPressed: () => Navigator.of(sheetContext).pop(),
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

class _CopyableLink extends StatelessWidget {
  const _CopyableLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              url,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xF2FFFFFF), fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              await showAppMessage(
                context,
                title: '已复制',
                message: '登录链接已复制到剪贴板。',
                tone: AppMessageTone.success,
              );
            },
            child: const Text(
              '复制',
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
