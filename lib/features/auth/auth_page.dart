import 'package:flutter/cupertino.dart';

import '../../core/app_scope.dart';
import '../../design/app_theme.dart';
import '../../design/app_widgets.dart';
import 'chatgpt_login_dialog.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _registering = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = AppScope.of(context);
    final error = _registering
        ? await controller.register(
            displayName: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          )
        : await controller.signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
    if (!mounted || error == null) return;
    await showAppMessage(
      context,
      title: '无法继续',
      message: error,
      tone: AppMessageTone.warning,
    );
  }

  Future<void> _enterDemo() async {
    final error = await AppScope.of(context).enterLocalDemo();
    if (!mounted || error == null) return;
    await showAppMessage(
      context,
      title: '无法进入体验',
      message: error,
      tone: AppMessageTone.warning,
    );
  }

  Future<void> _signInWithChatGpt() async {
    final controller = AppScope.of(context);
    final error = await controller.signInWithChatGPT(
      presentChallenge: (challenge) =>
          presentChatGptLoginChallenge(context, challenge),
    );
    if (!mounted || error == null) return;
    await showAppMessage(
      context,
      title: 'ChatGPT 登录未完成',
      message: error,
      tone: AppMessageTone.warning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return CupertinoPageScaffold(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.resolve(context, AppPalette.background),
          gradient: RadialGradient(
            center: const Alignment(0.72, -0.8),
            radius: 1.25,
            colors: [
              AppPalette.resolve(
                context,
                AppPalette.blue,
              ).withValues(alpha: dark ? 0.18 : 0.12),
              AppPalette.resolve(context, AppPalette.background),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                22,
                22,
                22,
                22 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    LiquidGlassSurface(
                      padding: EdgeInsets.zero,
                      radius: 23,
                      tone: LiquidGlassTone.accent,
                      child: const SizedBox(
                        width: 68,
                        height: 68,
                        child: Icon(
                          CupertinoIcons.sparkles,
                          color: Color(0xFFFFFFFF),
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('AILearningOS', style: AppTextStyles.largeTitle),
                    const SizedBox(height: 7),
                    Text(
                      '把资料变成可以真正记住的知识',
                      style: AppTextStyles.body.copyWith(
                        color: AppPalette.resolve(
                          context,
                          AppPalette.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AppCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CupertinoSlidingSegmentedControl<bool>(
                            groupValue: _registering,
                            children: const {
                              false: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 18),
                                child: Text('登录'),
                              ),
                              true: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 18),
                                child: Text('注册'),
                              ),
                            },
                            onValueChanged: (value) {
                              if (controller.busy || value == null) return;
                              setState(() => _registering = value);
                            },
                          ),
                          const SizedBox(height: 18),
                          if (_registering) ...[
                            _AuthField(
                              controller: _nameController,
                              placeholder: '昵称',
                              icon: CupertinoIcons.person,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 11),
                          ],
                          _AuthField(
                            controller: _emailController,
                            placeholder: '邮箱',
                            icon: CupertinoIcons.mail,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 11),
                          _AuthField(
                            controller: _passwordController,
                            placeholder: _registering ? '密码（至少 8 位）' : '密码',
                            icon: CupertinoIcons.lock,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 16),
                          AppPrimaryButton(
                            label: controller.busy
                                ? '请稍候…'
                                : (_registering ? '创建本地账号' : '登录'),
                            fullWidth: true,
                            onPressed: controller.busy ? null : _submit,
                          ),
                          const SizedBox(height: 10),
                          CupertinoButton(
                            onPressed: controller.busy ? null : _enterDemo,
                            child: const Text('快速进入本地体验'),
                          ),
                          const SizedBox(height: 2),
                          AppPrimaryButton(
                            label: controller.busy ? '请稍候…' : '使用 ChatGPT 登录',
                            icon: CupertinoIcons.chat_bubble_2_fill,
                            filled: false,
                            fullWidth: true,
                            onPressed:
                                controller.busy || !controller.chatGptSupported
                                ? null
                                : _signInWithChatGpt,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            controller.chatGptSupported
                                ? '通过官方 ChatGPT 登录流程接入 chatgpt5.5，登录后会优先使用 Codex 额度，不需要在这里输入 ChatGPT 密码。'
                                : 'ChatGPT 登录需要 Windows 上的 Codex App Server；Android 端请先配置受信任网关。',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption.copyWith(
                              color: AppPalette.resolve(
                                context,
                                AppPalette.secondaryText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '当前账号和密码仅保存在本机；云端同步将在下一阶段接入。',
                            textAlign: TextAlign.center,
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
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.placeholder,
    required this.icon,
    required this.textInputAction,
    this.keyboardType,
    this.obscureText = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final IconData icon;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      prefix: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Icon(
          icon,
          size: 18,
          color: AppPalette.resolve(context, AppPalette.secondaryText),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: AppPalette.resolve(context, AppPalette.softSurface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.resolve(context, AppPalette.separator),
          width: 0.6,
        ),
      ),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autocorrect: false,
      onSubmitted: onSubmitted,
    );
  }
}
