// Models and platform-neutral contract for the official Codex App Server
// ChatGPT sign-in flow.
//
// The app deliberately keeps provider access tokens inside Codex App Server.
// These objects contain only display-safe account metadata and the short-lived
// browser/device-code challenge needed to complete sign-in.

class ChatGptAuthState {
  const ChatGptAuthState({
    required this.available,
    required this.authenticated,
    this.accountId,
    this.email,
    this.displayName,
    this.planType,
    this.message,
  });

  const ChatGptAuthState.unavailable([String? message])
    : available = false,
      authenticated = false,
      accountId = null,
      email = null,
      displayName = null,
      planType = null,
      message = message ?? '当前平台没有可用的 Codex App Server。';

  const ChatGptAuthState.signedOut({this.message})
    : available = true,
      authenticated = false,
      accountId = null,
      email = null,
      displayName = null,
      planType = null;

  final bool available;
  final bool authenticated;
  final String? accountId;
  final String? email;
  final String? displayName;
  final String? planType;
  final String? message;

  String get planLabel {
    final value = planType?.trim();
    if (value == null || value.isEmpty) return 'ChatGPT';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class ChatGptLoginChallenge {
  const ChatGptLoginChallenge({
    required this.loginId,
    this.authUrl,
    this.verificationUrl,
    this.userCode,
  });

  final String loginId;
  final Uri? authUrl;
  final Uri? verificationUrl;
  final String? userCode;

  bool get isBrowserFlow => authUrl != null;
  bool get isDeviceCodeFlow => verificationUrl != null && userCode != null;
}

abstract class ChatGptAuthService {
  const ChatGptAuthService();

  bool get supported;

  Future<ChatGptAuthState> read();

  Future<ChatGptLoginChallenge> startLogin({bool deviceCode = false});

  Future<ChatGptAuthState> completeLogin(ChatGptLoginChallenge challenge);

  Future<void> cancelLogin(String loginId);

  Future<void> logout();
}

class NoopChatGptAuthService extends ChatGptAuthService {
  const NoopChatGptAuthService();

  @override
  bool get supported => false;

  @override
  Future<ChatGptAuthState> read() async => const ChatGptAuthState.unavailable();

  @override
  Future<ChatGptLoginChallenge> startLogin({bool deviceCode = false}) {
    return Future<ChatGptLoginChallenge>.error(
      StateError('Codex App Server 在此平台不可用。'),
    );
  }

  @override
  Future<ChatGptAuthState> completeLogin(ChatGptLoginChallenge challenge) {
    return Future<ChatGptAuthState>.error(
      StateError('Codex App Server 在此平台不可用。'),
    );
  }

  @override
  Future<void> cancelLogin(String loginId) async {}

  @override
  Future<void> logout() async {}
}
