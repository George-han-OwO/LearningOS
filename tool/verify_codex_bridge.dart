// This executable intentionally prints a safe verification summary.
// ignore_for_file: avoid_print

import 'package:ai_study_os/core/codex/local_chatgpt_auth_service.dart';

Future<void> main() async {
  final service = LocalCodexChatGptAuthService();
  try {
    final account = await service.read();
    if (!account.authenticated) {
      throw StateError(account.message ?? 'Codex 尚未使用 ChatGPT 登录。');
    }
    final quota = await service.readQuota();
    final history = await service.readCodexHistory(fullRefresh: true);
    final incremental = await service.readCodexHistory();
    final primaryRemaining = quota.primaryRemainingPercent;
    final secondaryRemaining = quota.secondaryRemainingPercent;
    print('ChatGPT Codex: connected (${account.planLabel})');
    print(
      'Quota remaining: '
      '${primaryRemaining?.toStringAsFixed(0) ?? '-'}% / '
      '${secondaryRemaining?.toStringAsFixed(0) ?? '-'}%',
    );
    print(
      'Codex ${history.folderName} history: '
      '${history.totalThreads} threads, '
      '${history.changedConversations.length} readable snapshots',
    );
    print(
      'Incremental check: ${incremental.changedConversations.length} changed snapshots',
    );
  } finally {
    await service.dispose();
  }
}
