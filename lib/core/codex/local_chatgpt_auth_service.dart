import 'dart:io';

import 'chatgpt_auth_service.dart';
import 'codex_app_server_client.dart';

class LocalCodexChatGptAuthService extends ChatGptAuthService {
  LocalCodexChatGptAuthService({
    this.executable = 'codex',
    this.arguments = const ['app-server'],
  });

  final String executable;
  final List<String> arguments;

  CodexAppServerClient? _loginClient;

  @override
  bool get supported =>
      !Platform.isAndroid && !Platform.isIOS && !Platform.isFuchsia;

  @override
  Future<ChatGptAuthState> read() async {
    if (!supported) return const ChatGptAuthState.unavailable();
    CodexAppServerClient? client;
    try {
      client = await _startClient();
      final state = await client.readAccount(refreshToken: true);
      return _mapAccountState(state);
    } catch (error) {
      return ChatGptAuthState.unavailable('Codex 不可用：$error');
    } finally {
      await client?.dispose();
    }
  }

  @override
  Future<ChatGptLoginChallenge> startLogin({bool deviceCode = false}) async {
    if (!supported) {
      throw StateError('当前平台没有可用的 Codex App Server。');
    }

    await _loginClient?.dispose();
    final client = await _startClient();
    _loginClient = client;

    final login = deviceCode
        ? await client.startChatGptDeviceCodeLogin()
        : await client.startChatGptLogin();
    return ChatGptLoginChallenge(
      loginId: login.loginId,
      authUrl: login.authUrl,
      verificationUrl: login.verificationUrl,
      userCode: login.userCode,
    );
  }

  @override
  Future<ChatGptAuthState> completeLogin(
    ChatGptLoginChallenge challenge,
  ) async {
    final client = _loginClient;
    if (client == null) {
      throw StateError('请先开始 ChatGPT 登录流程。');
    }
    try {
      final state = await client.completeChatGptLogin(
        CodexChatGptLogin(
          loginId: challenge.loginId,
          authUrl: challenge.authUrl,
          verificationUrl: challenge.verificationUrl,
          userCode: challenge.userCode,
        ),
        timeout: const Duration(minutes: 5),
      );
      return _mapAccountState(state);
    } finally {
      await client.dispose();
      if (identical(_loginClient, client)) {
        _loginClient = null;
      }
    }
  }

  @override
  Future<void> cancelLogin(String loginId) async {
    final client = _loginClient;
    if (client == null) return;
    try {
      await client.cancelLogin(loginId);
    } finally {
      await client.dispose();
      if (identical(_loginClient, client)) {
        _loginClient = null;
      }
    }
  }

  @override
  Future<void> logout() async {
    if (!supported) return;
    CodexAppServerClient? client;
    try {
      client = await _startClient();
      await client.logout();
    } finally {
      await client?.dispose();
    }
  }

  Future<CodexAppServerClient> _startClient() async {
    final client = CodexAppServerClient(
      executable: executable,
      arguments: arguments,
    );
    await client.start();
    return client;
  }

  ChatGptAuthState _mapAccountState(CodexAccountState state) {
    final account = state.account;
    if (account == null) {
      return ChatGptAuthState.signedOut(
        message: state.requiresOpenaiAuth ? '请先完成 ChatGPT 登录。' : null,
      );
    }
    return ChatGptAuthState(
      available: true,
      authenticated: true,
      accountId: account.accountId,
      email: account.email,
      displayName: account.displayName,
      planType: account.planType,
      message: null,
    );
  }
}
